import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/db/session_persistence.dart';
import '../../core/db/session_repository.dart';
import '../../core/session/session_controller.dart';
import '../../core/session/session_models.dart';
import '../app_services.dart';
import '../format.dart';
import 'calibration_screen.dart';
import 'connection_screen.dart';
import 'summary_screen.dart';
import 'training_screen.dart';

/// Jedna sesja od laczenia do podsumowania. Ekran wynika z fazy sesji.
class SessionFlowScreen extends StatefulWidget {
  const SessionFlowScreen({super.key});

  @override
  State<SessionFlowScreen> createState() => _SessionFlowScreenState();
}

class _SessionFlowScreenState extends State<SessionFlowScreen> {
  SessionController? _controller;
  StreamSubscription<SessionSnapshot>? _sub;
  late SessionConfig _config;
  SessionSnapshot? _snapshot;
  SessionResult? _result;
  List<SessionRow> _recent = const [];
  final _log = <TrainingLogEntry>[];
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
    _config = services.sessionConfig;
    _result = null;
    _log.clear();
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
    final controller = _controller = SessionController(
      sourceFactory: services.sourceFactory,
      config: _config,
      onItem: persistence.onItem,
    );
    _sub = controller.snapshots.listen(_onSnapshot);
    unawaited(_run(controller, persistence, services.repository));
  }

  Future<void> _run(SessionController c, SessionPersistence p, SessionRepository repo) async {
    final result = await c.run();
    await p.finish(result);
    if (!mounted) return;
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

  void _leave() => Navigator.of(context).pop();

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
      return SummaryScreen(result: result, recent: _recent, onDone: _leave);
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
        return CalibrationScreen(snapshot: s, onFinish: _finish);
      case SessionPhase.training:
      case SessionPhase.breakBetweenBlocks:
        return TrainingScreen(snapshot: s, log: _log, onFinish: _finish);
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
