import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/db/app_database.dart';
import 'core/db/session_repository.dart';
import 'core/eeg/brainaccess/brainaccess_mac_source.dart';
import 'core/eeg/eeg_source.dart';
import 'core/eeg/mock_source.dart';
import 'ui/app.dart';
import 'ui/app_services.dart';
import 'ui/neuronek/neuronek.dart';

/// Zrodlo wybierane przez --dart-define:
///   SOURCE=mock (domyslnie) | brainaccess
///   DEVICE="BA MAXI 012", BACORE_LIB=sciezka/do/libbacore.dylib
///   TRAINING_CHANNELS=O1,O2, BIAS=1,9
const _source = String.fromEnvironment('SOURCE', defaultValue: 'mock');
const _device = String.fromEnvironment('DEVICE', defaultValue: 'BA MAXI 012');
const _lib = String.fromEnvironment('BACORE_LIB');
const _channels = String.fromEnvironment('TRAINING_CHANNELS', defaultValue: 'O1,O2');
const _bias = String.fromEnvironment('BIAS');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NeuronekSprites.load();
  final dir = await getApplicationSupportDirectory();
  final database = AppDatabase.open('${dir.path}/neurotchi.db');
  final raw = '${dir.path}/raw';
  Directory(raw).createSync(recursive: true);

  final training = _channels.split(',');
  final real = _source == 'brainaccess';
  EegSource Function() factory = () => MockSource(
        alphaAmplitudeUv: (t) => 12 + 10 * (t > 90 ? 1 : 0),
        realtime: true,
      );
  if (real) {
    final bias = _bias.isEmpty ? <int>[] : _bias.split(',').map(int.parse).toList();
    factory = () => BrainAccessMacSource(deviceName: _device, libPath: _lib, biasChannels: bias);
  }

  runApp(NeurotchiApp(
    services: AppServices(
      repository: SessionRepository(database),
      sourceFactory: factory,
      rawDir: raw,
      sourceType: real ? 'device' : 'mock',
      deviceIdentifier: real ? _device : null,
      sourceLabel: real ? 'Czepek' : 'Demo',
      trainingChannels: training,
    ),
  ));
}
