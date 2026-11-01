import 'dart:io';

import '../eeg/recording_writer.dart';
import '../eeg/stream_item.dart';
import '../session/session_models.dart';
import 'session_repository.dart';

/// Podpina sie pod `SessionController.onItem`: zapisuje surowe EEG zawsze
/// (jeden plik na segment) oraz segmenty i luki w bazie. Na koniec zapisuje
/// wynik sesji.
class SessionPersistence {
  SessionPersistence._(this.repo, this.sessionId, this.rawDir);

  final SessionRepository repo;
  final int sessionId;
  final String rawDir;
  final _clock = Stopwatch()..start();
  final _pendingCloses = <Future<void>>[];

  int _segmentNo = 0;
  int? _segmentId;
  RecordingWriter? _writer;
  int? _firstEnd;
  double? _firstT;
  int _lastEnd = 0;
  double _lastT = 0;

  factory SessionPersistence.begin({
    required SessionRepository repo,
    required SessionConfig config,
    required String sourceType,
    String? deviceIdentifier,
    String deviceModel = 'MAXI',
    String? firmware,
    required String appVersion,
    required String rawDir,
  }) {
    Directory(rawDir).createSync(recursive: true);
    final id = repo.startSession(
      protocolId: repo.ensureProtocol(
        config.processing,
        name: config.protocol.dbName,
      ),
      sourceType: sourceType,
      deviceId: sourceType == 'device'
          ? repo.ensureDevice(identifier: deviceIdentifier!, model: deviceModel)
          : null,
      plannedDurationS: config.plannedDurationS,
      appVersion: appVersion,
      firmware: firmware,
      channels: config.trainingChannels,
    );
    return SessionPersistence._(repo, id, rawDir);
  }

  void onItem(StreamItem item) {
    switch (item) {
      case SegmentStart():
        _closeSegment('restart');
        _segmentNo++;
        final base = '$rawDir/session${sessionId}_seg$_segmentNo';
        _writer = RecordingWriter(base)..add(item);
        _segmentId = repo.addSegment(
          sessionId: sessionId,
          segmentNo: _segmentNo,
          info: item.info,
          startedAtMs: _clock.elapsedMilliseconds,
          rawFilePath: '$base.csv',
        );
        _firstEnd = null;
      case EegPacket():
        _writer?.add(item);
        final end = item.firstSample + item.length;
        if (_firstEnd == null) {
          _firstEnd = end;
          _firstT = item.tRecv;
        }
        _lastEnd = end;
        _lastT = item.tRecv;
      case GapEvent():
        final id = _segmentId;
        if (id != null) repo.addGap(id, item.firstSample, item.count);
      case DisconnectedEvent():
        _closeSegment('disconnected');
    }
  }

  void _closeSegment(String reason) {
    final id = _segmentId;
    if (id == null) return;
    final span = _lastT - (_firstT ?? _lastT);
    final fs = (_firstEnd != null && span > 0)
        ? (_lastEnd - _firstEnd!) / span
        : null;
    repo.endSegment(id, fsMeasured: fs, reason: reason);
    final w = _writer;
    if (w != null) _pendingCloses.add(w.close());
    _segmentId = null;
    _writer = null;
  }

  Future<void> finish(SessionResult result) async {
    _closeSegment('stop');
    await Future.wait(_pendingCloses);
    repo.finishSession(
      sessionId,
      result,
      actualDurationS: _clock.elapsed.inSeconds,
    );
  }
}
