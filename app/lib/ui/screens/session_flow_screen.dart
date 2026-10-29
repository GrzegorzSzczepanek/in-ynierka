import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/db/session_persistence.dart';
import '../../core/db/session_repository.dart';
import '../../core/session/session_controller.dart';
import '../../core/session/session_models.dart';
import '../../core/session/training_protocol.dart';
import '../app_services.dart';
import '../format.dart';
import 'calibration_screen.dart';
import 'connection_screen.dart';
import 'summary_screen.dart';
import 'training_screen.dart';

/// Jedna sesja od laczenia do podsumowania. Ekran wynika z fazy sesji.
class SessionFlowScreen extends StatefulWidget {
  const SessionFlowScreen({
    super.key,
    this.protocol = TrainingProtocol.relaks,
    this.calibrationOnly = false,
  });

  final TrainingProtocol protocol;

  /// Tylko kalibracja, bez blokow; po wyniku ekran sam sie zamyka.
  final bool calibrationOnly;

  @override
  State<SessionFlowScreen> createState() => _SessionFlowScreenState();
}

class _SessionFlowScreenState extends State<SessionFlowScreen> {
  SessionController? _controller;
  int? _sessionId;
  int? _mood;
  StreamSubscription<SessionSnapshot>? _sub;
  late SessionConfig _config;
  SessionSnapshot? _snapshot;
  SessionResult? _result;
  List<SessionRow> _recent = const [];
  final _log = <TrainingLogEntry>[];
  final _history = <double>[];
  int _lastRewards = 0;
  bool _lastValid = true;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _start();
    }
  }

  void _start() {
    final services = ServicesScope.of(context);
    _config = services.sessionConfigFor(widget.protocol, calibrationOnly: widget.calibrationOnly);
    _result = null;
    _mood = null;
    _log.clear();
    _history.clear();
    _lastRewards = 0;
    _lastValid = true;
    final persistence = SessionPersistence.begin(
      repo: services.repository,
      config: _config,
      sourceType: services.sourceType,
      deviceIdentifier: services.deviceIdentifier,
      deviceModel: services.deviceModel,
      appVersion: services.appVersion,
      rawDir: services.rawDir,
    );
    _sessionId = persistence.sessionId;
    final controller = _controller = SessionController(
      sourceFactory: services.sourceFactoryFor(widget.protocol),
      config: _config,
      onItem: persistence.onItem,
      stored: services.repository.lastCalibration(widget.protocol),
    );
    _sub = controller.snapshots.listen(_onSnapshot);
    unawaited(_run(controller, persistence, services.repository));
  }

  Future<void> _run(SessionController c, SessionPersistence p, SessionRepository repo) async {
    final result = await c.run();
    await p.finish(result);
    if (!mounted) return;
    if (widget.calibrationOnly && result.status == SessionStatus.completed) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _result = result;
      _recent = repo.history().where((s) => s.id != p.sessionId).toList();
    });
  }

  void _onSnapshot(SessionSnapshot s) {
    if (!mounted) return;
    final fb = s.feedback;
    if (s.phase == SessionPhase.training && fb != null) {
      final t = mmss(s.phaseElapsedS);
      if (s.rewardCount > _lastRewards) _log.add(TrainingLogEntry(t, 'Nagroda'));
      if (!fb.valid && _lastValid) {
        _log.add(TrainingLogEntry(
            t, s.lastInvalid == null ? 'Sygnał niewiarygodny' : reasonTitle(s.lastInvalid!)));
      } else if (fb.valid && !_lastValid) {
        _log.add(TrainingLogEntry(t, 'Sygnał wrócił'));
      }
      _lastValid = fb.valid;
      if (fb.valid) {
        _history.add(fb.y);
        if (_history.length > 120) _history.removeAt(0);
      }
    }
    _lastRewards = s.phase == SessionPhase.training ? s.rewardCount : 0;
    setState(() => _snapshot = s);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller?.finish();
    super.dispose();
  }

  void _finish() => _controller?.finish();

  void _leave() {
    final id = _sessionId;
    final mood = _mood;
    if (id != null && mood != null && (_result?.countsForProgress ?? false)) {
      ServicesScope.of(context).repository.setMood(id, mood);
    }
    Navigator.of(context).pop();
  }

  void _restart() {
    _sub?.cancel();
    setState(() {
      _snapshot = null;
      _start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final s = _snapshot;
    if (result != null && result.status != SessionStatus.connectionLost) {
      return SummaryScreen(
        result: result,
        recent: _recent,
        onDone: _leave,
        protocol: widget.protocol,
        mood: _mood,
        onMood: (v) => setState(() => _mood = v),
      );
    }
    if (s == null) {
      return ConnectionScreen(
        snapshot: const SessionSnapshot(phase: SessionPhase.connecting, phaseElapsedS: 0, attempt: 1),
        trainingChannels: _config.trainingChannels,
        maxAttempts: _config.connectAttempts,
        onFinish: _finish,
      );
    }
    switch (s.phase) {
      case SessionPhase.calibrating:
      case SessionPhase.calibratingClosed:
      case SessionPhase.calibrationResult:
        return CalibrationScreen(
          snapshot: s,
          onFinish: _finish,
          closedStep: _config.closedStep,
          reactivityMin: _config.alphaReactivityMin,
          onSkip: s.canSkipCalibration ? _controller?.skipCalibration : null,
        );
      case SessionPhase.training:
      case SessionPhase.breakBetweenBlocks:
        return TrainingScreen(
            snapshot: s,
            log: _log,
            history: List.of(_history),
            onFinish: _finish,
            protocol: widget.protocol,
            onPause: _controller?.pause,
            onResume: _controller?.resume,
            onRate: (r) => _controller?.rateBlock(s.blockNo, r));
      case SessionPhase.connecting:
      case SessionPhase.contactCheck:
      case SessionPhase.reconnecting:
      case SessionPhase.connectionLost:
      case SessionPhase.deviceSelection:
      case SessionPhase.summary:
      case SessionPhase.completed:
      case SessionPhase.interrupted:
        final lostEnd = result?.status == SessionStatus.connectionLost;
        return ConnectionScreen(
          snapshot: s,
          trainingChannels: _config.trainingChannels,
          maxAttempts: s.phase == SessionPhase.reconnecting
              ? _config.reconnectAttempts
              : _config.connectAttempts,
          onFinish: lostEnd ? _leave : _finish,
          onRetry: s.phase == SessionPhase.connectionLost
              ? _controller?.retry
              : s.phase == SessionPhase.deviceSelection || lostEnd
                  ? _restart
                  : null,
        );
    }
  }
}
