import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/db/app_database.dart';
import 'package:neurotchi/core/db/session_persistence.dart';
import 'package:neurotchi/core/db/session_repository.dart';
import 'package:neurotchi/core/dsp/processing_config.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/session/session_controller.dart';
import 'package:neurotchi/core/session/session_models.dart';
import 'package:neurotchi/core/session/training_protocol.dart';
import 'package:sqlite3/sqlite3.dart';

const cfg = SessionConfig(
  calibrationS: 20,
  blockS: 10,
  breakS: 4,
  contactSettleS: 1,
  contactStableS: 1,
  calibrationClosedS: 0,
);

MockSource mock({int? disconnectAfter, Set<int> drop = const {}}) => MockSource(
      duration: const Duration(seconds: 200),
      alphaAmplitudeUv: (t) => t < 25 ? 10 : 30,
      noiseUv: 2,
      disconnectAfterChunk: disconnectAfter,
      dropChunks: drop,
    );

Future<void> instant(Duration _) async {}

late AppDatabase database;
late SessionRepository repo;
late Directory tmp;

Future<SessionResult> runSession(SourceFactory factory) async {
  final p = SessionPersistence.begin(
    repo: repo,
    config: cfg,
    sourceType: 'mock',
    appVersion: '0.1.0',
    rawDir: tmp.path,
  );
  final c = SessionController(
    sourceFactory: factory,
    config: cfg,
    onItem: p.onItem,
    delay: instant,
  );
  final r = await c.run();
  await p.finish(r);
  return r;
}

ResultSet q(String sql, [List<Object?> params = const []]) =>
    database.db.select(sql, params);

void main() {
  setUp(() {
    database = AppDatabase.inMemory();
    repo = SessionRepository(database);
    tmp = Directory.systemTemp.createTempSync('neurotchi_db');
  });
  tearDown(() => database.close());

  test('schemat, slowniki i wersja', () {
    expect(q('PRAGMA user_version').first.values.first, 2);
    expect(q('PRAGMA foreign_keys').first.values.first, 1);
    expect(q('SELECT COUNT(*) c FROM avatar_stages').first['c'], 6);
    expect(q('SELECT COUNT(*) c FROM invalid_reasons').first['c'], 6);
    expect(
        q('SELECT name, channel_count FROM device_models ORDER BY channel_count')
            .map((r) => r['name']),
        ['MINI', 'MIDI', 'MAXI']);
  });

  test('ograniczenia CHECK i klucze obce', () {
    final protocol = repo.ensureProtocol(const ProcessingConfig());
    void insertSession(String type, int? device) => database.db.execute(
        'INSERT INTO sessions (protocol_id, source_type, device_id, created_at, '
        'planned_duration_s, app_version) VALUES (?, ?, ?, ?, 1, ?)',
        [protocol, type, device, 'x', 'v']);
    expect(() => insertSession('device', null), throwsA(isA<SqliteException>()));
    expect(() => insertSession('mock', 1), throwsA(isA<SqliteException>()));
    expect(() => insertSession('inne', null), throwsA(isA<SqliteException>()));
    expect(() => insertSession('mock', null), returnsNormally);
    expect(
        () => database.db.execute(
            'INSERT INTO segment_gaps (segment_id, first_sample, sample_count) VALUES (999, 0, 1)'),
        throwsA(isA<SqliteException>()));
    expect(
        () => database.db.execute(
            'INSERT INTO invalid_intervals (block_id, calibration_id, reason_id, start_ms, end_ms) '
            'VALUES (NULL, NULL, 1, 0, 10)'),
        throwsA(isA<SqliteException>()));
  });

  test('konfiguracja przetwarzania jest niezmienna, protokol wersjonowany', () {
    final a = repo.ensureProtocol(const ProcessingConfig());
    expect(repo.ensureProtocol(const ProcessingConfig()), a);
    final b = repo.ensureProtocol(const ProcessingConfig(filterLowHz: 4));
    expect(b, isNot(a));
    expect(q('SELECT version FROM protocols WHERE id = ?', [b]).first['version'], 2);
    expect(q('SELECT COUNT(*) c FROM processing_configs').first['c'], 2);
    expect(() => database.db.execute('UPDATE processing_configs SET eps = 1'),
        throwsA(isA<SqliteException>()));
    expect(() => database.db.execute('DELETE FROM processing_configs'),
        throwsA(isA<SqliteException>()));
  });

  test('pelna sesja zapisuje kalibracje, bloki, zdarzenia, segment i statystyki', () async {
    final r = await runSession(() => mock());
    final s = q('SELECT * FROM sessions').single;
    expect(s['status'], 'completed');
    expect(s['planned_duration_s'], cfg.plannedDurationS);
    expect(s['actual_duration_s'], isNotNull);
    expect(q('SELECT channel_name FROM session_channels ORDER BY channel_name')
        .map((x) => x['channel_name']), ['O1', 'O2']);

    final seg = q('SELECT * FROM segments').single;
    expect(seg['end_reason'], 'stop');
    expect(seg['fs_measured_hz'] as double, closeTo(250, 1));
    final lines = File(seg['raw_file_path'] as String).readAsLinesSync();
    expect(lines.length - 1, greaterThan(250 * 40));

    final cal = q('SELECT * FROM calibrations').single;
    expect(cal['succeeded'], 1);
    expect(cal['baseline_mad'], isNotNull);
    final blocks = q('SELECT * FROM blocks ORDER BY block_no');
    expect(blocks.map((b) => b['block_no']), [1, 2, 3]);
    expect(blocks.every((b) => b['calibration_id'] == cal['id']), isTrue);
    expect(blocks.first['reward_count'], greaterThanOrEqualTo(1));
    expect(
        q('SELECT COUNT(*) c FROM block_events be JOIN event_types et ON et.id = be.event_type_id '
            "WHERE et.name = 'reward'").first['c'],
        greaterThanOrEqualTo(1));

    final stats = q('SELECT * FROM session_stats').single;
    expect(stats['blocks_total'], 3);
    expect(stats['valid_minutes'] as double, closeTo(r.validSignalS / 60, 0.05));
    expect(repo.totalValidMinutes(), closeTo(stats['valid_minutes'] as double, 0.001));
    expect(repo.currentStage.name, 'soma');
    expect(repo.nextStage!.name, 'neuron');
    expect(repo.history().single.status, 'completed');
    final day = repo.dailyStats().single;
    expect(day.sessions, 1);
    expect(day.blocksTotal, 3);
  });

  test('utrata polaczenia daje dwa segmenty i dwie kalibracje', () async {
    var n = 0;
    await runSession(() => n++ == 0 ? mock(disconnectAfter: 300) : mock());
    final segs = q('SELECT * FROM segments ORDER BY segment_no');
    expect(segs.map((s) => s['end_reason']), ['disconnected', 'stop']);
    expect(segs.map((s) => s['segment_no']), [1, 2]);
    expect(q('SELECT COUNT(*) c FROM calibrations').first['c'], 2);
    expect(q('SELECT COUNT(*) c FROM blocks').first['c'], 3);
  });

  test('luka w numeracji probek trafia do segment_gaps', () async {
    await runSession(() => mock(drop: {20}));
    final gap = q('SELECT * FROM segment_gaps').single;
    expect(gap['sample_count'], 25);
    expect(gap['first_sample'], 500);
  });

  test('przerwana sesja bez bloku nie liczy sie do statystyk', () async {
    final p = SessionPersistence.begin(
        repo: repo, config: cfg, sourceType: 'mock', appVersion: '0', rawDir: tmp.path);
    late SessionController c;
    c = SessionController(
        sourceFactory: () => mock(), config: cfg, onItem: p.onItem, delay: instant);
    c.snapshots.listen((s) {
      if (s.phase == SessionPhase.training && s.phaseElapsedS > 3) c.finish();
    });
    final r = await c.run();
    await p.finish(r);
    expect(q('SELECT status FROM sessions').single['status'], 'interrupted');
    expect(q('SELECT COUNT(*) c FROM session_stats').first['c'], 0);
    expect(repo.totalValidMinutes(), 0);
  });

  test('ustawienia: wartosci domyslne i zapis', () {
    expect(repo.setting('default_block_s'), '180');
    repo.setSetting('default_block_s', '120');
    repo.setSetting('sound', '1');
    expect(repo.setting('default_block_s'), '120');
    expect(repo.setting('sound'), '1');
    final c = repo.sessionConfig(const SessionConfig());
    expect(c.blockS, 120);
    expect(c.blocks, 3);
  });

  test('trening skupienia: protokol, kanaly i historia z nazwa treningu', () async {
    const focus = SessionConfig(
      protocol: TrainingProtocol.skupienie,
      calibrationS: 20,
      blockS: 10,
      breakS: 4,
      contactSettleS: 1,
      contactStableS: 1,
    );
    final p = SessionPersistence.begin(
        repo: repo, config: focus, sourceType: 'mock', appVersion: '0', rawDir: tmp.path);
    final c = SessionController(
      sourceFactory: () => MockSource(
        duration: const Duration(seconds: 200),
        alphaAmplitudeUv: (_) => 10,
        betaAmplitudeUv: (t) => t < 25 ? 3 : 9,
        noiseUv: 1,
      ),
      config: focus,
      onItem: p.onItem,
      delay: instant,
    );
    final r = await c.run();
    await p.finish(r);
    expect(r.status, SessionStatus.completed);
    expect(q('SELECT name FROM protocols').map((x) => x['name']), ['Trening skupienia']);
    expect(q('SELECT channel_name FROM session_channels ORDER BY channel_name')
        .map((x) => x['channel_name']), ['C3', 'C4', 'F3', 'F4']);
    expect(repo.history().single.protocol.title, 'Skupienie');
  });
}
