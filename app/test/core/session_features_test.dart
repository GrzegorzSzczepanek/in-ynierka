import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/db/app_database.dart';
import 'package:neurotchi/core/db/schema.dart';
import 'package:neurotchi/core/db/session_persistence.dart';
import 'package:neurotchi/core/db/session_repository.dart';
import 'package:neurotchi/core/dsp/calibration.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/session/session_controller.dart';
import 'package:neurotchi/core/session/session_models.dart';
import 'package:neurotchi/core/session/training_protocol.dart';
import 'package:sqlite3/sqlite3.dart';

const cfg = SessionConfig(
  calibrationS: 20,
  blocks: 2,
  blockS: 10,
  breakS: 4,
  contactSettleS: 1,
  contactStableS: 1,
  calibrationClosedS: 10,
  calibrationResultS: 2,
);

MockSource mock(double Function(double) amp) => MockSource(
      duration: const Duration(seconds: 300),
      alphaAmplitudeUv: amp,
      noiseUv: 2,
    );

Future<void> instant(Duration _) async {}

void main() {
  test('kalibracja dwuetapowa liczy reaktywnosc alfa i pik', () async {
    final phases = <SessionPhase>[];
    final c = SessionController(
        sourceFactory: () => mock((t) => t < 22 ? 10 : 25), config: cfg, delay: instant);
    c.snapshots.listen((s) {
      if (phases.isEmpty || phases.last != s.phase) phases.add(s.phase);
    });
    final r = await c.run();
    expect(phases, containsAllInOrder([
      SessionPhase.calibrating,
      SessionPhase.calibratingClosed,
      SessionPhase.calibrationResult,
      SessionPhase.training,
    ]));
    final cal = r.calibrations.single;
    expect(cal.alphaRatio, closeTo(6.25, 2.5));
    expect(cal.alphaPeakHz, closeTo(10, 0.6));
    expect(r.status, SessionStatus.completed);
  });

  test('niska reaktywnosc powtarza krok oczy zamkniete, potem idzie dalej', () async {
    var restarts = 0;
    double last = -1;
    final c = SessionController(sourceFactory: () => mock((_) => 10), config: cfg, delay: instant);
    c.snapshots.listen((s) {
      if (s.phase == SessionPhase.calibratingClosed) {
        if (s.phaseElapsedS < last) restarts++;
        last = s.phaseElapsedS;
      }
    });
    final r = await c.run();
    expect(restarts, 2);
    expect(r.calibrations.single.alphaRatio, lessThan(1.2));
    expect(r.status, SessionStatus.completed);
  });

  test('trening skupienia nie ma kroku oczy zamkniete', () async {
    final phases = <SessionPhase>[];
    const focus = SessionConfig(
      protocol: TrainingProtocol.skupienie,
      calibrationS: 20,
      blocks: 1,
      blockS: 10,
      contactSettleS: 1,
      contactStableS: 1,
    );
    final c = SessionController(sourceFactory: () => mock((_) => 10), config: focus, delay: instant);
    c.snapshots.listen((s) => phases.add(s.phase));
    await c.run();
    expect(phases.contains(SessionPhase.calibratingClosed), isFalse);
  });

  test('pominiecie kalibracji uzywa zapisanego baseline i progu', () async {
    const stored = StoredCalibration(baseline: Baseline(3.0, 0.4), thresholdY: 0.55);
    late SessionController c;
    c = SessionController(
        sourceFactory: () => mock((_) => 20), config: cfg, stored: stored, delay: instant);
    c.snapshots.listen((s) {
      if (s.phase == SessionPhase.calibrating && s.canSkipCalibration) c.skipCalibration();
    });
    final r = await c.run();
    expect(r.calibrations.single.reused, isTrue);
    expect(r.calibrations.single.durationS, 0);
    expect(r.blocks.length, 2);
    expect(r.blocks.first.threshold, 0.55);
  });

  test('bez zapisanej kalibracji pominiecie jest niedostepne', () async {
    var seenSkip = false;
    late SessionController c;
    c = SessionController(sourceFactory: () => mock((_) => 20), config: cfg, delay: instant);
    c.snapshots.listen((s) {
      if (s.canSkipCalibration) seenSkip = true;
      if (s.phase == SessionPhase.calibrating) c.skipCalibration();
    });
    final r = await c.run();
    expect(seenSkip, isFalse);
    expect(r.calibrations.every((x) => !x.reused), isTrue);
  });

  test('pauza zatrzymuje czas bloku i liczenie wyniku', () async {
    late SessionController c;
    var pausedSnaps = 0;
    double? frozen;
    c = SessionController(sourceFactory: () => mock((_) => 20), config: cfg, delay: instant);
    c.snapshots.listen((s) {
      if (s.phase == SessionPhase.training && s.blockNo == 1) {
        if (!s.paused && s.phaseElapsedS > 3 && pausedSnaps == 0) {
          c.pause();
        } else if (s.paused) {
          frozen ??= s.phaseElapsedS;
          expect(s.phaseElapsedS, frozen);
          if (++pausedSnaps == 25) c.resume();
        }
      }
    });
    final r = await c.run();
    expect(pausedSnaps, greaterThanOrEqualTo(25));
    final b = r.blocks.first;
    // Czas pauzy nie wchodzi do bloku: blok ma 10 s liczonego czasu.
    expect(b.actualS, closeTo(10, 0.6));
    expect(b.validSignalS, closeTo(10, 0.7));
    expect(b.windowsTotal, closeTo(10 / 0.256, 3));
    expect(r.status, SessionStatus.completed);
  });

  test('oceny kontroli, slad wyniku i liczniki okien w wyniku bloku', () async {
    late SessionController c;
    final long = SessionConfig(
      calibrationS: cfg.calibrationS,
      blocks: 2,
      blockS: 70,
      breakS: 4,
      contactSettleS: 1,
      contactStableS: 1,
      calibrationClosedS: 0,
    );
    c = SessionController(sourceFactory: () => mock((_) => 20), config: long, delay: instant);
    c.snapshots.listen((s) {
      if (s.phase == SessionPhase.breakBetweenBlocks && s.controlRating == null) {
        c.rateBlock(s.blockNo, 4);
      }
    });
    final r = await c.run();
    expect(r.controlRatings, {1: 4});
    final b = r.blocks.first;
    expect(b.yTrace.length, 3);
    expect(b.yTrace.every((y) => y >= 0 && y <= 1), isTrue);
    expect(b.windowsTotal, closeTo(70 / 0.256, 3));
    expect(b.windowsInvalid, lessThan(3));
    expect(b.meanY, inInclusiveRange(0, 1));
  });

  group('baza v2', () {
    late AppDatabase db;
    late SessionRepository repo;
    late Directory tmp;
    setUp(() {
      db = AppDatabase.inMemory();
      repo = SessionRepository(db);
      tmp = Directory.systemTemp.createTempSync('feat');
    });
    tearDown(() => db.close());

    test('sesja z ocenami: kalibracja do ponownego uzycia, nastroj i seria', () async {
      final p = SessionPersistence.begin(
          repo: repo, config: cfg, sourceType: 'mock', appVersion: '0', rawDir: tmp.path);
      late SessionController c;
      c = SessionController(
        sourceFactory: () => mock((t) => t < 22 ? 10 : 25),
        config: cfg,
        onItem: p.onItem,
        delay: instant,
      );
      c.snapshots.listen((s) {
        if (s.phase == SessionPhase.breakBetweenBlocks && s.controlRating == null) {
          c.rateBlock(s.blockNo, 3);
        }
      });
      final r = await c.run();
      await p.finish(r);
      repo.setMood(p.sessionId, 4);

      final stored = repo.lastCalibration(TrainingProtocol.relaks)!;
      expect(stored.thresholdY, r.calibrations.single.result.thresholdY);
      expect(stored.alphaRatio, closeTo(6.25, 2.5));
      expect(stored.alphaPeakHz, closeTo(10, 0.6));
      expect(repo.lastCalibration(TrainingProtocol.skupienie), isNull);
      expect(repo.recentMoodAverage(), 4.0);
      expect(db.db.select('SELECT control_rating FROM blocks ORDER BY block_no').map((x) => x['control_rating']),
          [3, null]);
      expect(repo.lastSessionTargetShare(), inInclusiveRange(0, 1));
      expect(repo.streakDays(DateTime.now()), 1);
      expect(repo.validMinutesSince(DateTime.now().subtract(const Duration(days: 1))), greaterThan(0));
      expect(() => repo.setMood(p.sessionId, 7), throwsArgumentError);
      expect(() => db.db.execute('UPDATE sessions SET mood_after = 9'), throwsA(isA<SqliteException>()));
    });

    test('migracja bazy v1 do v2 dodaje kolumny i zachowuje dane', () {
      final raw = sqlite3.openInMemory();
      final v1 = schemaSql
          .replaceAll(RegExp(r'  mood_after INTEGER CHECK[^\n]*\n'), '')
          .replaceAll('  alpha_ratio REAL,\n  alpha_peak_hz REAL,\n', '')
          .replaceAll(RegExp(r'  control_rating INTEGER CHECK[^\n]*\n'), '');
      raw.execute('PRAGMA foreign_keys = ON');
      raw.execute(v1);
      raw.execute(seedSql);
      raw.execute('PRAGMA user_version = 1');
      final cols = raw.select('PRAGMA table_info(sessions)').map((r) => r['name']);
      expect(cols.contains('mood_after'), isFalse);

      final migrated = AppDatabase.wrap(raw);
      expect(migrated.db.select('PRAGMA user_version').first.values.first, 2);
      expect(migrated.db.select('PRAGMA table_info(sessions)').map((r) => r['name']), contains('mood_after'));
      expect(migrated.db.select('PRAGMA table_info(blocks)').map((r) => r['name']), contains('control_rating'));
      expect(migrated.db.select('PRAGMA table_info(calibrations)').map((r) => r['name']),
          containsAll(['alpha_ratio', 'alpha_peak_hz']));
      expect(migrated.db.select('SELECT COUNT(*) c FROM avatar_stages').first['c'], 6);
      migrated.close();
    });
  });
}
