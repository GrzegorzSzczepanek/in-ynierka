import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/session/connection_monitor.dart';
import '../../core/session/session_models.dart';
import '../../core/session/training_protocol.dart';
import '../app_services.dart';
import 'connection_screen.dart';

/// Ekran Polaczenie z menu glownego: laczenie i kontakt elektrod bez sesji.
class ConnectionCheckScreen extends StatefulWidget {
  const ConnectionCheckScreen({super.key, required this.protocol});

  final TrainingProtocol protocol;

  @override
  State<ConnectionCheckScreen> createState() => _ConnectionCheckScreenState();
}

class _ConnectionCheckScreenState extends State<ConnectionCheckScreen> {
  ConnectionMonitor? _monitor;
  StreamSubscription<MonitorState>? _sub;
  MonitorState _state = const MonitorState(MonitorStatus.connecting);
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
    final monitor = _monitor = ConnectionMonitor(services.sourceFactory);
    _sub = monitor.states.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    unawaited(monitor.start());
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    await _monitor?.stop();
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }

  Future<void> _retry() async {
    await _stop();
    if (!mounted) return;
    setState(() => _state = const MonitorState(MonitorStatus.connecting));
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final snapshot = SessionSnapshot(
      phase: switch (s.status) {
        MonitorStatus.connecting => SessionPhase.connecting,
        MonitorStatus.connected => SessionPhase.contactCheck,
        MonitorStatus.lost => SessionPhase.connectionLost,
        MonitorStatus.failed => SessionPhase.deviceSelection,
      },
      phaseElapsedS: 0,
      attempt: s.attempt,
      contact: s.contact,
    );
    return ConnectionScreen(
      snapshot: snapshot,
      trainingChannels: widget.protocol.channels,
      maxAttempts: 3,
      onFinish: () => Navigator.of(context).pop(),
      onRetry: s.status == MonitorStatus.lost || s.status == MonitorStatus.failed ? _retry : null,
    );
  }
}
