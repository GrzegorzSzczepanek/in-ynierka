import 'package:flutter/widgets.dart';

import '../core/db/session_repository.dart';
import '../core/session/session_controller.dart';
import '../core/session/session_models.dart';

/// Zaleznosci aplikacji: baza, zrodlo EEG i konfiguracja sesji.
class AppServices {
  AppServices({
    required this.repository,
    required this.sourceFactory,
    required this.rawDir,
    this.sourceType = 'mock',
    this.deviceIdentifier,
    this.deviceModel = 'MAXI',
    this.appVersion = '0.1.0',
    this.trainingChannels = const ['O1', 'O2'],
    this.configOverride,
    this.sourceLabel = 'Demo',
  });

  final SessionRepository repository;
  final SourceFactory sourceFactory;
  final String rawDir;
  final String sourceType;
  final String? deviceIdentifier;
  final String deviceModel;
  final String appVersion;
  final String sourceLabel;
  final List<String> trainingChannels;
  final SessionConfig? configOverride;

  SessionConfig get sessionConfig =>
      configOverride ??
      repository.sessionConfig(SessionConfig(trainingChannels: trainingChannels));
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServicesScope>()!.services;

  @override
  bool updateShouldNotify(ServicesScope old) => services != old.services;
}
