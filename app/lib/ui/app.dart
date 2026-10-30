import 'package:flutter/material.dart';

import '../core/session/training_protocol.dart';
import '../core/update/update_checker.dart';
import 'app_services.dart';
import 'screens/calibration_hub_screen.dart';
import 'screens/connection_check_screen.dart';
import 'screens/home_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/research_screen.dart';
import 'screens/session_flow_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/update_dialog.dart';
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
  TrainingProtocol _selected = TrainingProtocol.alfa;
  bool _updateChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_updateChecked) return;
    _updateChecked = true;
    final services = ServicesScope.of(context);
    if (services.updatesAvailable && services.settings.checkUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
    }
  }

  /// Po cichu sprawdza GitHub; blad sieci nie przeszkadza w pracy z aplikacja.
  Future<void> _checkUpdate() async {
    final services = ServicesScope.of(context);
    final info = await services.checkForUpdate().then<UpdateInfo?>((v) => v).catchError((_) => null);
    if (!mounted || info == null || info.version == services.settings.skippedVersion) return;
    final choice = await showUpdateDialog(context, info, services.appVersion);
    switch (choice) {
      case UpdateChoice.download:
        await services.openUrl?.call(info.assetUrl ?? info.pageUrl);
      case UpdateChoice.skip:
        final s = services.settings..skippedVersion = info.version;
        s.save(services.repository);
      case UpdateChoice.later:
        break;
    }
  }

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
      onConnection: () => _open(ConnectionCheckScreen(protocol: _selected)),
      onCalibration: () => _open(_CalibrationRoute(protocol: _selected)),
      onResearch: () => _open(ResearchScreen(protocol: _selected)),
      onSettings: () => _open(const SettingsScreen()),
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

/// Kalibracja z menu: ostatni wynik, a przycisk uruchamia sama kalibracje.
class _CalibrationRoute extends StatefulWidget {
  const _CalibrationRoute({required this.protocol});

  final TrainingProtocol protocol;

  @override
  State<_CalibrationRoute> createState() => _CalibrationRouteState();
}

class _CalibrationRouteState extends State<_CalibrationRoute> {
  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);
    return CalibrationHubScreen(
      protocol: widget.protocol,
      stored: services.repository.lastCalibration(widget.protocol),
      onBack: () => Navigator.of(context).pop(),
      onCalibrate: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SessionFlowScreen(protocol: widget.protocol, calibrationOnly: true),
        ));
        if (mounted) setState(() {});
      },
    );
  }
}
