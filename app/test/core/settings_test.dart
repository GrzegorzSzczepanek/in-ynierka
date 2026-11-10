import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/db/app_database.dart';
import 'package:neurotchi/core/db/session_repository.dart';
import 'package:neurotchi/core/eeg/brainaccess/channel_map.dart';
import 'package:neurotchi/core/eeg/brainaccess/lib_locator.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';
import 'package:neurotchi/core/eeg/unavailable_source.dart';
import 'package:neurotchi/core/session/session_controller.dart';
import 'package:neurotchi/core/session/session_models.dart';
import 'package:neurotchi/core/session/training_protocol.dart';
import 'package:neurotchi/core/settings/app_settings.dart';
import 'package:neurotchi/ui/app_services.dart';

void main() {
  late AppDatabase db;
  late SessionRepository repo;
  setUp(() {
    db = AppDatabase.inMemory();
    repo = SessionRepository(db);
  });
  tearDown(() => db.close());

  test('model czepka z nazwy urzadzenia i kanaly dla MIDI', () {
    expect(deviceModelOf('BA MAXI 012'), 'MAXI');
    expect(deviceModelOf('BA MIDI 0417'), 'MIDI');
    expect(deviceModelOf('BA-MINI-3'), 'MINI');
    expect(deviceModelOf('nieznany'), 'MAXI');

    final midi = AppSettings(source: SourceKind.device, deviceName: 'BA MIDI 0417');
    expect(midi.deviceModel, 'MIDI');
    expect(midi.effectiveNaming, ChannelNaming.numbered);
    expect(midi.channelNames, [for (var i = 1; i <= 16; i++) 'ch$i']);
    expect(midi.trainingChannelsFor(TrainingProtocol.alfa), ['ch1', 'ch2', 'ch3', 'ch4']);
    expect(midi.biasIndicesFor(TrainingProtocol.alfa), [0, 1]);

    midi.training['alfa'] = ['ch12', 'ch30', 'O1'];
    expect(midi.trainingChannelsFor(TrainingProtocol.alfa), ['ch12']);

    final mini = AppSettings(source: SourceKind.device, deviceName: 'BA MINI 7');
    expect(mini.channelNames.length, 8);

    final maxi = AppSettings(source: SourceKind.device, deviceName: 'BA MAXI 012');
    expect(maxi.channelNames.length, 32);
    expect(maxi.trainingChannelsFor(TrainingProtocol.alfa), ['O1', 'O2']);
  });

  test('sesja z MIDI zapisuje model czepka w bazie', () {
    AppSettings(source: SourceKind.device, deviceName: 'BA MIDI 0417').save(repo);
    final services = AppServices(repository: repo, rawDir: '/tmp');
    expect(services.deviceModel, 'MIDI');
    final id = repo.ensureDevice(identifier: 'BA MIDI 0417', model: services.deviceModel);
    final model = db.db
        .select('SELECT dm.name n, dm.channel_count c FROM devices d JOIN device_models dm ON dm.id = d.model_id WHERE d.id = ?', [id])
        .single;
    expect(model['n'], 'MIDI');
    expect(model['c'], 16);
  });

  test('ustawienia: wartosci domyslne i zapis w bazie', () {
    final d = AppSettings.load(repo);
    expect(d.source, SourceKind.demo);
    expect(d.deviceName, '');
    expect(d.trainingChannelsFor(TrainingProtocol.alfa), ['O1', 'O2']);

    final s = AppSettings(source: SourceKind.device, deviceName: 'BA MAXI 012', naming: ChannelNaming.numbered)
      ..training['alfa'] = ['ch2', 'ch10'];
    s.save(repo);
    final back = AppSettings.load(repo);
    expect(back.source, SourceKind.device);
    expect(back.deviceName, 'BA MAXI 012');
    expect(back.naming, ChannelNaming.numbered);
    expect(back.trainingChannelsFor(TrainingProtocol.alfa), ['ch2', 'ch10']);
    expect(back.trainingChannelsFor(TrainingProtocol.skupienie),
        ['ch11', 'ch6', 'ch14', 'ch4']); // F3 F4 C3 C4: zlacza 10, 5, 13, 3 plus 1
  });

  test('nazwy kanalow z tabeli producenta i indeksy BIAS', () {
    expect(maxiManufacturerNames.length, 32);
    expect(maxiManufacturerNames[11], 'O1');
    expect(maxiManufacturerNames[1], 'O2');
    final s = AppSettings(source: SourceKind.device, deviceName: 'x')..training['alfa'] = ['O2', 'Pz', 'O1'];
    expect(s.biasIndicesFor(TrainingProtocol.alfa), [1, 9]);
    expect(AppSettings(source: SourceKind.device, naming: ChannelNaming.numbered).channelNames.first, 'ch1');
  });

  test('zrodlo Demo zawsze uzywa nazw 10-20, nawet gdy wybrano numery', () {
    final s = AppSettings(naming: ChannelNaming.numbered);
    expect(s.effectiveNaming, ChannelNaming.manufacturer);
    expect(s.trainingChannelsFor(TrainingProtocol.alfa), ['O1', 'O2']);
  });

  test('lokalizator libbacore: sciezka reczna, bundle i vendor w drzewie', () {
    final tmp = Directory.systemTemp.createTempSync('lib');
    final manual = File('${tmp.path}/moja.dylib')..createSync();
    expect(findBacoreLib(override: manual.path, environment: {}, executable: '/x/y', cwd: '/nie/ma'), manual.path);
    expect(findBacoreLib(override: '/nie/ma.dylib', environment: {}, executable: '/x/y', cwd: '/nie/ma'), isNull);

    final app = Directory('${tmp.path}/App.app/Contents/MacOS')..createSync(recursive: true);
    Directory('${tmp.path}/App.app/Contents/Frameworks').createSync();
    final bundled = File('${tmp.path}/App.app/Contents/Frameworks/libbacore.dylib')..createSync();
    expect(findBacoreLib(environment: {}, executable: '${app.path}/neurotchi', cwd: '/nie/ma'), bundled.path);

    final repoRoot = Directory('${tmp.path}/repo')..createSync();
    final vendor = File('${repoRoot.path}/vendor/mac_os_testing/BrainAccessCore-4.0.0-macos/lib/libbacore.dylib')
      ..createSync(recursive: true);
    final deep = Directory('${repoRoot.path}/app/build/x')..createSync(recursive: true);
    expect(findBacoreLib(environment: {}, executable: '/x/y', cwd: deep.path), vendor.path);
  });

  test('AppServices wybiera zrodlo wg ustawien', () async {
    final services = AppServices(repository: repo, rawDir: '/tmp');
    final p = TrainingProtocol.alfa;
    expect(services.sourceFactoryFor(p)(), isA<MockSource>());
    expect(services.sourceLabel, 'DEMO');
    expect(services.sourceType, 'mock');

    AppSettings(source: SourceKind.device).save(repo);
    expect(services.sourceLabel, 'CZEPEK, nie wybrano');
    expect(services.sourceType, 'device');
    expect(services.sourceFactoryFor(p)(), isA<UnavailableSource>()); // brak nazwy czepka

    AppSettings(source: SourceKind.device, deviceName: 'BA MAXI 012', libPath: '/nie/ma.dylib').save(repo);
    final src = services.sourceFactoryFor(p)();
    // Biblioteka moze byc w drzewie projektu; wazne, ze nie rzuca i jest zrodlem.
    expect(src, isNotNull);
    expect(services.sessionConfigFor(p).trainingChannels, ['O1', 'O2']);
  });

  test('niedostepne zrodlo konczy laczenie wyborem urzadzenia', () async {
    final c = SessionController(
      sourceFactory: () => UnavailableSource('brak'),
      config: const SessionConfig(),
      delay: (_) async {},
    );
    final phases = <SessionPhase>[];
    c.snapshots.listen((s) => phases.add(s.phase));
    final r = await c.run();
    expect(phases.last, SessionPhase.deviceSelection);
    expect(r.status, SessionStatus.connectionLost);
    final first = await UnavailableSource('x').let((s) async {
      await s.start();
      return s.items.first;
    });
    expect(first, isA<DisconnectedEvent>());
  });

  test('wybor kanalow z kontaktem: tyl glowy, a bez niego pierwsze z kontaktem', () {
    final posterior = [
      const ChannelContact('F3', true),
      const ChannelContact('O2', true),
      const ChannelContact('O1', false),
      const ChannelContact('Pz', true),
    ];
    expect(AppSettings.channelsWithContact(posterior), ['O2', 'Pz']);
    final front = [
      for (final n in ['F3', 'F4', 'C3', 'C4', 'Cz', 'Fz']) ChannelContact(n, true),
      const ChannelContact('T7', false),
    ];
    expect(AppSettings.channelsWithContact(front), ['F3', 'F4', 'C3', 'C4']);
    expect(AppSettings.channelsWithContact([const ChannelContact('O1', false)]), isEmpty);
  });

  test('instrukcja przed treningiem: domyslnie wlaczona i zapisywana', () {
    final db = AppDatabase.inMemory();
    final repo = SessionRepository(db);
    expect(AppSettings.load(repo).showInstruction, isTrue);
    AppSettings(showInstruction: false).save(repo);
    expect(AppSettings.load(repo).showInstruction, isFalse);
    db.close();
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
