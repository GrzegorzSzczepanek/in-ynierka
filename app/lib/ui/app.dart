import 'package:flutter/material.dart';

import '../core/session/training_protocol.dart';
import 'app_services.dart';
import 'screens/home_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/session_flow_screen.dart';
import 'theme/pixel_theme.dart';
import 'view_data.dart';

class NeurotchiApp extends StatelessWidget {
  const NeurotchiApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) => ServicesScope(
        services: services,
        child: MaterialApp(
          title: 'NEUROtchi',
          debugShowCheckedModeBanner: false,
          theme: Px.theme,
          home: const _HomeRoute(),
        ),
      );
}

class _HomeRoute extends StatefulWidget {
  const _HomeRoute();

  @override
  State<_HomeRoute> createState() => _HomeRouteState();
}

class _HomeRouteState extends State<_HomeRoute> {
  TrainingProtocol _selected = TrainingProtocol.relaks;

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    final config = services.sessionConfigFor(_selected);
    return HomeScreen(
      data: homeData(
        services.repository,
        trainingMinutes: (config.blocks * config.blockS / 60).round(),
        sourceLabel: services.sourceLabel,
      ),
      selected: _selected,
      onSelect: (p) => setState(() => _selected = p),
      onStart: () => _open(SessionFlowScreen(protocol: _selected)),
      onProgress: () => _open(Builder(
        builder: (ctx) => ProgressScreen(
          data: progressData(services.repository, DateTime.now()),
          todayIndex: DateTime.now().weekday - 1,
          onBack: () => Navigator.of(ctx).pop(),
        ),
      )),
    );
  }
}
