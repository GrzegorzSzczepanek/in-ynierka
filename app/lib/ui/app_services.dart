import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../core/db/session_repository.dart';
import '../core/eeg/brainaccess/brainaccess_android_source.dart';
import '../core/eeg/brainaccess/brainaccess_mac_source.dart';
import '../core/eeg/brainaccess/lib_locator.dart';
import '../core/eeg/mock_source.dart';
import '../core/eeg/unavailable_source.dart';
import '../core/session/session_controller.dart';
import '../core/update/update_checker.dart';
import '../core/settings/app_settings.dart';
import '../core/session/session_models.dart';
import '../core/session/training_protocol.dart';

/// Zaleznosci aplikacji: baza, zrodlo EEG (z ustawien) i konfiguracja sesji.
class AppServices {
  AppServices({
    required this.repository,
    required this.rawDir,
    SourceFactory? sourceFactory,
    this.appVersion = '0.1.0',
    this.configOverride,
    this.exportDir = '',
    this.updateFetch,
    this.openUrl,
  }) : _sourceOverride = sourceFactory;

  final SessionRepository repository;
  final String rawDir;
  final String appVersion;
  final SessionConfig? configOverride;

  /// Katalog eksportu sesji (tryb badacza).
  final String exportDir;
  final SourceFactory? _sourceOverride;

  /// Pobieranie danych z GitHuba; null wylacza sprawdzanie aktualizacji (testy).
  final UpdateFetch? updateFetch;

  /// Otwarcie adresu w przegladarce systemu.
  final Future<void> Function(String url)? openUrl;

  bool get updatesAvailable => updateFetch != null;

  Future<UpdateInfo?> checkForUpdate() {
    final fetch = updateFetch;
    if (fetch == null) return Future.value(null);
    return UpdateChecker(
      currentVersion: appVersion,
      fetch: fetch,
      token: settings.updateToken,
    ).check();
  }

  AppSettings get settings => AppSettings.load(repository);

  bool get isDevice =>
      _sourceOverride == null && settings.source == SourceKind.device;
  String get sourceType => isDevice ? 'device' : 'mock';
  String? get deviceIdentifier => isDevice ? settings.deviceName : null;
  String get sourceLabel {
    if (!isDevice) return 'DEMO';
    final name = settings.deviceName;
    return name.isEmpty ? 'CZEPEK, nie wybrano' : 'CZEPEK $name';
  }

  /// Zapisuje wybrane kanaly treningowe protokolu w ustawieniach.
  void useTrainingChannels(TrainingProtocol protocol, List<String> names) {
    final s = settings;
    s.training[protocol.id] = names;
    s.save(repository);
  }

  String get deviceModel => 'MAXI';

  /// Zrodlo EEG dla wybranego treningu wg ustawien (Demo lub czepek BrainAccess).
  SourceFactory sourceFactoryFor(TrainingProtocol protocol) {
    final o = _sourceOverride;
    if (o != null) return o;
    return () {
      final s = settings;
      if (s.source == SourceKind.device) {
        if (s.deviceName.isEmpty)
          return UnavailableSource(
            'Nie wybrano czepka. Wybierz go w ustawieniach.',
          );
        if (Platform.isAndroid) {
          return BrainAccessAndroidSource(
            deviceName: s.deviceName,
            channelNames: s.channelNames,
            biasChannels: s.biasIndicesFor(protocol),
          );
        }
        final lib = findBacoreLib(override: s.libPath);
        if (lib == null)
          return UnavailableSource('Nie znaleziono biblioteki libbacore.');
        return BrainAccessMacSource(
          deviceName: s.deviceName,
          libPath: lib,
          channelNames: s.channelNames,
          biasChannels: s.biasIndicesFor(protocol),
        );
      }
      return MockSource(
        realtime: true,
        alphaAmplitudeUv: (t) => 12 + 10 * (t > 90 ? 1 : 0),
        betaAmplitudeUv: (t) => 4 + 6 * (t > 90 ? 1 : 0),
        contactAt: (t) => t > 3,
      );
    };
  }

  SessionConfig sessionConfigFor(
    TrainingProtocol protocol, {
    bool calibrationOnly = false,
  }) {
    final override = configOverride;
    if (override != null) return override;
    // Tryb testowy (zmiana z pomoca AI, Claude): krotkie kroki, bez powtorzen
    // kroku z zamknietymi oczami. Pomija czasy zapisane w bazie.
    if (settings.quickSession) {
      return SessionConfig(
        protocol: protocol,
        trainingChannels: settings.trainingChannelsFor(protocol),
        calibrationOnly: calibrationOnly,
        calibrationS: 20,
        calibrationMaxS: 40,
        calibrationClosedS: 10,
        calibrationResultS: 2,
        maxClosedRepeats: 0,
        blocks: 2,
        blockS: 30,
        breakS: 5,
      );
    }
    return repository.sessionConfig(
      SessionConfig(
        protocol: protocol,
        trainingChannels: settings.trainingChannelsFor(protocol),
        calibrationOnly: calibrationOnly,
      ),
    );
  }

  SessionConfig get sessionConfig => sessionConfigFor(TrainingProtocol.alfa);
}

class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServicesScope>()!.services;

  @override
  bool updateShouldNotify(ServicesScope old) => services != old.services;
}
