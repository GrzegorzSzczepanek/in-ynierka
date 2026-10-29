import 'package:sqlite3/sqlite3.dart';

import '../dsp/calibration.dart';
import '../dsp/processing_config.dart';
import '../eeg/stream_item.dart';
import '../session/session_models.dart';
import '../session/training_protocol.dart';
import 'app_database.dart';

class AvatarStage {
  const AvatarStage(this.name, this.requiredValidMinutes, this.sortOrder);

  final String name;
  final int requiredValidMinutes;
  final int sortOrder;
}

class SessionRow {
  const SessionRow({
    required this.id,
    required this.createdAt,
    required this.status,
    required this.validMinutes,
    required this.blocksTotal,
    this.protocol = TrainingProtocol.relaks,
  });

  final TrainingProtocol protocol;
  final int id;
  final DateTime createdAt;
  final String status;
  final double validMinutes;
  final int blocksTotal;
}

class ExportableSession {
  const ExportableSession({
    required this.id,
    required this.createdAt,
    required this.status,
    required this.protocol,
  });

  final int id;
  final DateTime createdAt;
  final String status;
  final TrainingProtocol protocol;
}

class DailyStat {
  const DailyStat(this.date, this.validMinutes, this.blocksTotal, this.sessions);

  final String date;
  final double validMinutes;
  final int blocksTotal;
  final int sessions;
}

class SessionRepository {
  SessionRepository(this.database, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final AppDatabase database;
  final DateTime Function() _now;

  Database get _db => database.db;

  /// Dostep do bazy dla eksportu i narzedzi badacza.
  Database get db => database.db;

  int ensureProtocol(ProcessingConfig c, {String name = 'Trening alfa'}) {
    final configId = _ensureConfig(c);
    final rows = _db.select(
        'SELECT id, version, processing_config_id FROM protocols '
        'WHERE name = ? ORDER BY version DESC',
        [name]);
    if (rows.isNotEmpty && rows.first['processing_config_id'] == configId) {
      return rows.first['id'] as int;
    }
    final version = rows.isEmpty ? 1 : (rows.first['version'] as int) + 1;
    _db.execute(
        'INSERT INTO protocols (name, version, processing_config_id) VALUES (?, ?, ?)',
        [name, version, configId]);
    return _db.lastInsertRowId;
  }

  int _ensureConfig(ProcessingConfig c) {
    final values = [
      c.filterType, c.filterOrder, c.filterLowHz, c.filterHighHz, c.windowS,
      c.stepSamples, c.eps, c.p0, c.madScale, c.sMin, c.mapA, c.mapB,
      c.smoothingLambda, c.notchHz, c.welchSegmentS, c.welchOverlap,
      c.alphaLowHz, c.alphaHighHz, c.ampThresholdUv, c.hfRatioThreshold,
      c.warmupSkipS, c.calibMinValidRatio, c.thresholdPercentile, c.holdTimeS,
    ];
    const cols = [
      'filter_type', 'filter_order', 'filter_low_hz', 'filter_high_hz',
      'window_s', 'step_samples', 'eps', 'p0', 'mad_scale', 's_min', 'map_a',
      'map_b', 'smoothing_lambda', 'notch_hz', 'welch_segment_s',
      'welch_overlap', 'alpha_low_hz', 'alpha_high_hz', 'amp_threshold_uv',
      'hf_ratio_threshold', 'warmup_skip_s', 'calib_min_valid_ratio',
      'threshold_percentile', 'hold_time_s',
    ];
    final found = _db.select(
        'SELECT id FROM processing_configs WHERE ${cols.map((c) => '$c IS ?').join(' AND ')}',
        values);
    if (found.isNotEmpty) return found.first['id'] as int;
    _db.execute(
        'INSERT INTO processing_configs (${cols.join(', ')}) '
        'VALUES (${List.filled(cols.length, '?').join(', ')})',
        values);
    return _db.lastInsertRowId;
  }

  int ensureDevice({
    required String identifier,
    String manufacturer = 'BrainAccess',
    required String model,
  }) {
    final existing = _db.select(
        'SELECT id FROM devices WHERE device_identifier = ?', [identifier]);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    final m = _db.select(
        'SELECT dm.id FROM device_models dm JOIN manufacturers mf ON mf.id = dm.manufacturer_id '
        'WHERE mf.name = ? AND dm.name = ?',
        [manufacturer, model]);
    if (m.isEmpty) throw StateError('Nieznany model $manufacturer $model');
    _db.execute('INSERT INTO devices (device_identifier, model_id) VALUES (?, ?)',
        [identifier, m.first['id']]);
    return _db.lastInsertRowId;
  }

  int startSession({
    required int protocolId,
    required String sourceType,
    int? deviceId,
    required int plannedDurationS,
    required String appVersion,
    String? firmware,
    required List<String> channels,
  }) {
    return database.transaction(() {
      _db.execute(
          'INSERT INTO sessions (protocol_id, source_type, device_id, created_at, '
          'planned_duration_s, app_version, firmware) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            protocolId, sourceType, deviceId, _now().toUtc().toIso8601String(),
            plannedDurationS, appVersion, firmware,
          ]);
      final id = _db.lastInsertRowId;
      for (final c in channels) {
        _db.execute(
            'INSERT INTO session_channels (session_id, channel_name) VALUES (?, ?)',
            [id, c]);
      }
      return id;
    });
  }

  int addSegment({
    required int sessionId,
    required int segmentNo,
    required StreamInfo info,
    required int startedAtMs,
    required String rawFilePath,
  }) {
    _db.execute(
        'INSERT INTO segments (session_id, segment_no, contract_version, source_id, '
        'fs_nominal_hz, chunk_size, started_at_ms, raw_file_path) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          sessionId, segmentNo, info.contract, info.sourceId, info.fs,
          info.chunkSize, startedAtMs, rawFilePath,
        ]);
    return _db.lastInsertRowId;
  }

  void endSegment(int segmentId, {double? fsMeasured, required String reason}) {
    _db.execute(
        'UPDATE segments SET fs_measured_hz = ?, end_reason = ? WHERE id = ?',
        [fsMeasured, reason, segmentId]);
  }

  void addGap(int segmentId, int firstSample, int count) {
    _db.execute(
        'INSERT INTO segment_gaps (segment_id, first_sample, sample_count) VALUES (?, ?, ?)',
        [segmentId, firstSample, count]);
  }

  /// Zapisuje wynik sesji w jednej transakcji: kalibracje, bloki, zdarzenia,
  /// przedzialy niewazne, statystyki oraz status i czas rzeczywisty.
  void finishSession(int sessionId, SessionResult result,
      {required int actualDurationS}) {
    database.transaction(() {
      final calibrationIds = <int, int>{};
      for (final c in result.calibrations) {
        final r = c.result;
        _db.execute(
            'INSERT INTO calibrations (session_id, attempt_no, duration_s, valid_signal_s, '
            'baseline_median, baseline_mad, threshold_y, failure_reason, succeeded, '
            'alpha_ratio, alpha_peak_hz) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              sessionId, c.attempt, c.durationS.round(), c.validSignalS.round(),
              r.baseline?.median, r.baseline?.scale, r.thresholdY,
              c.reused ? 'reused' : c.failureReason, r.accepted ? 1 : 0,
              c.alphaRatio, c.alphaPeakHz,
            ]);
        calibrationIds[c.attempt] = _db.lastInsertRowId;
      }
      for (final b in result.blocks) {
        _db.execute(
            'INSERT INTO blocks (session_id, calibration_id, block_no, planned_duration_s, '
            'actual_duration_s, threshold_used, valid_signal_s, time_above_threshold_s, '
            'reward_count, control_rating) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              sessionId, calibrationIds[b.calibrationAttempt], b.blockNo,
              b.plannedS.round(), b.actualS.round(), b.threshold,
              b.validSignalS.round(), b.timeAboveThresholdS, b.rewardCount,
              result.controlRatings[b.blockNo],
            ]);
        final blockId = _db.lastInsertRowId;
        for (final e in b.events) {
          _db.execute(
              'INSERT INTO block_events (block_id, event_type_id, occurred_at_ms) '
              'VALUES (?, (SELECT id FROM event_types WHERE name = ?), ?)',
              [blockId, e.type, e.atMs]);
        }
        for (final i in b.invalid) {
          if (i.endMs <= i.startMs) continue;
          _db.execute(
              'INSERT INTO invalid_intervals (block_id, reason_id, start_ms, end_ms) '
              'VALUES (?, (SELECT id FROM invalid_reasons WHERE name = ?), ?, ?)',
              [blockId, i.reason.name, i.startMs, i.endMs]);
        }
      }
      final status = switch (result.status) {
        SessionStatus.completed => 'completed',
        SessionStatus.interrupted => 'interrupted',
        SessionStatus.connectionLost => 'connection_lost',
      };
      _db.execute('UPDATE sessions SET status = ?, actual_duration_s = ? WHERE id = ?',
          [status, actualDurationS, sessionId]);
      if (result.countsForProgress) {
        final created = _db.select(
            'SELECT created_at FROM sessions WHERE id = ?', [sessionId]).first['created_at'] as String;
        _db.execute(
            'INSERT INTO session_stats (session_id, session_date, valid_minutes, blocks_total) '
            'VALUES (?, ?, ?, ?)',
            [sessionId, created.substring(0, 10), _sessionValidMinutes(sessionId), result.blocks.length]);
      }
    });
  }

  /// Zrodlem prawdy sa bloki, wiec statystyki licza sie z zapisanych wierszy.
  double _sessionValidMinutes(int sessionId) {
    final v = _db.select(
        'SELECT SUM(valid_signal_s) AS s FROM blocks WHERE session_id = ?', [sessionId]).first['s'];
    return v == null ? 0 : (v as num) / 60;
  }

  void setMood(int sessionId, int rating) {
    if (rating < 1 || rating > 5) throw ArgumentError('Ocena 1..5');
    _db.execute('UPDATE sessions SET mood_after = ? WHERE id = ?', [rating, sessionId]);
  }

  /// Ostatnia udana kalibracja danego treningu (do pominiecia kalibracji).
  StoredCalibration? lastCalibration(TrainingProtocol protocol) {
    final r = _db.select(
        'SELECT c.baseline_median, c.baseline_mad, c.threshold_y, c.alpha_ratio, '
        'c.alpha_peak_hz, s.created_at FROM calibrations c '
        'JOIN sessions s ON s.id = c.session_id JOIN protocols p ON p.id = s.protocol_id '
        'WHERE p.name = ? AND c.succeeded = 1 AND c.baseline_median IS NOT NULL '
        'ORDER BY c.id DESC LIMIT 1',
        [protocol.dbName]);
    if (r.isEmpty) return null;
    final row = r.first;
    return StoredCalibration(
      baseline: Baseline((row['baseline_median'] as num).toDouble(),
          (row['baseline_mad'] as num).toDouble()),
      thresholdY: (row['threshold_y'] as num).toDouble(),
      alphaRatio: (row['alpha_ratio'] as num?)?.toDouble(),
      alphaPeakHz: (row['alpha_peak_hz'] as num?)?.toDouble(),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// Ostatnie sesje (najnowsze pierwsze) do eksportu: id, data, status, trening.
  List<ExportableSession> exportableSessions({int limit = 6}) => [
        for (final r in _db.select(
            'SELECT s.id, s.created_at, s.status, p.name AS protocol FROM sessions s '
            'JOIN protocols p ON p.id = s.protocol_id ORDER BY s.id DESC LIMIT ?',
            [limit]))
          ExportableSession(
            id: r['id'] as int,
            createdAt: DateTime.parse(r['created_at'] as String),
            status: r['status'] as String,
            protocol: TrainingProtocol.byDbName(r['protocol'] as String),
          ),
      ];

  /// Srednia ocen samopoczucia z ostatnich [n] sesji (1..5) lub null.
  double? recentMoodAverage({int n = 5}) {
    final r = _db.select(
        'SELECT AVG(mood_after) AS m FROM (SELECT mood_after FROM sessions '
        'WHERE mood_after IS NOT NULL ORDER BY id DESC LIMIT ?)',
        [n]).first['m'];
    return (r as num?)?.toDouble();
  }

  /// Udzial czasu w celu w ostatniej sesji z blokami (0..1) lub null.
  double? lastSessionTargetShare() {
    final r = _db.select(
        'SELECT SUM(time_above_threshold_s) AS a, SUM(valid_signal_s) AS v FROM blocks '
        'WHERE session_id = (SELECT MAX(session_id) FROM blocks)').first;
    final v = (r['v'] as num?)?.toDouble() ?? 0;
    return v > 0 ? ((r['a'] as num).toDouble() / v).clamp(0.0, 1.0) : null;
  }

  /// Poprawne minuty treningu od [since] (UTC).
  double validMinutesSince(DateTime since) {
    final r = _db.select(
        'SELECT SUM(b.valid_signal_s) AS s FROM blocks b JOIN sessions s ON s.id = b.session_id '
        'WHERE s.created_at >= ?',
        [since.toUtc().toIso8601String()]).first['s'];
    return r == null ? 0 : (r as num) / 60;
  }

  /// Liczba kolejnych dni (do dzis lub wczoraj) z co najmniej jedna sesja z postepem.
  int streakDays(DateTime now) {
    final days = {for (final d in dailyStats()) d.date};
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    var day = DateTime(now.year, now.month, now.day);
    if (!days.contains(key(day))) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(key(day))) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  double totalValidMinutes() {
    final v = _db.select('SELECT SUM(valid_signal_s) AS s FROM blocks').first['s'];
    return v == null ? 0 : (v as num) / 60;
  }

  List<AvatarStage> unlockedStages() => [
        for (final r in _db.select(
            'SELECT name, required_valid_minutes, sort_order FROM avatar_stages '
            'WHERE required_valid_minutes <= ? ORDER BY sort_order',
            [totalValidMinutes()]))
          AvatarStage(r['name'] as String, r['required_valid_minutes'] as int,
              r['sort_order'] as int),
      ];

  List<AvatarStage> allStages() => [
        for (final r in _db.select(
            'SELECT name, required_valid_minutes, sort_order FROM avatar_stages ORDER BY sort_order'))
          AvatarStage(r['name'] as String, r['required_valid_minutes'] as int,
              r['sort_order'] as int),
      ];

  AvatarStage get currentStage => unlockedStages().last;

  AvatarStage? get nextStage {
    final r = _db.select(
        'SELECT name, required_valid_minutes, sort_order FROM avatar_stages '
        'WHERE required_valid_minutes > ? ORDER BY sort_order LIMIT 1',
        [totalValidMinutes()]);
    if (r.isEmpty) return null;
    return AvatarStage(r.first['name'] as String,
        r.first['required_valid_minutes'] as int, r.first['sort_order'] as int);
  }

  List<SessionRow> history() => [
        for (final r in _db.select(
            'SELECT s.id, s.created_at, s.status, st.valid_minutes, st.blocks_total, p.name AS protocol_name '
            'FROM sessions s JOIN session_stats st ON st.session_id = s.id '
            'JOIN protocols p ON p.id = s.protocol_id '
            'ORDER BY s.created_at DESC'))
          SessionRow(
            id: r['id'] as int,
            createdAt: DateTime.parse(r['created_at'] as String),
            status: r['status'] as String,
            validMinutes: (r['valid_minutes'] as num).toDouble(),
            blocksTotal: r['blocks_total'] as int,
            protocol: TrainingProtocol.byDbName(r['protocol_name'] as String),
          ),
      ];

  List<DailyStat> dailyStats() => [
        for (final r in _db.select('SELECT * FROM daily_stats ORDER BY session_date'))
          DailyStat(r['session_date'] as String, (r['valid_minutes'] as num).toDouble(),
              r['blocks_total'] as int, r['sessions'] as int),
      ];

  String? setting(String key) {
    final r = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  void setSetting(String key, String value) => _db.execute(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value]);

  /// Domyslne czasy sesji z ustawien, reszta z [base].
  SessionConfig sessionConfig(SessionConfig base) {
    double d(String k, double fallback) => double.tryParse(setting(k) ?? '') ?? fallback;
    return SessionConfig(
      processing: base.processing,
      protocol: base.protocol,
      trainingChannels: base.channelsOverride,
      calibrationS: d('default_calibration_s', base.calibrationS),
      blocks: d('default_blocks', base.blocks.toDouble()).round(),
      blockS: d('default_block_s', base.blockS),
      breakS: d('default_break_s', base.breakS),
      contactSettleS: base.contactSettleS,
      contactStableS: base.contactStableS,
      connectAttempts: base.connectAttempts,
      reconnectAttempts: base.reconnectAttempts,
      reconnectIntervalS: base.reconnectIntervalS,
      calibrationClosedS: base.calibrationClosedS,
      calibrationResultS: base.calibrationResultS,
      alphaReactivityMin: base.alphaReactivityMin,
      maxClosedRepeats: base.maxClosedRepeats,
      calibrationOnly: base.calibrationOnly,
    );
  }
}
