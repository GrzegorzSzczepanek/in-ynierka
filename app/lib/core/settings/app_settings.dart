import '../db/session_repository.dart';
import '../session/session_models.dart';
import '../eeg/brainaccess/channel_map.dart';
import '../session/training_protocol.dart';

enum SourceKind { demo, device }

enum ChannelNaming { manufacturer, numbered }

/// Ustawienia aplikacji zapisane w tabeli settings.
class AppSettings {
  AppSettings({
    this.source = SourceKind.demo,
    this.deviceName = '',
    this.naming = ChannelNaming.manufacturer,
    this.libPath = '',
    this.showInstruction = true,
    this.checkUpdates = true,
    this.quickSession = false,
    this.updateToken = '',
    this.skippedVersion = '',
    Map<String, List<String>>? training,
  }) : training = training ?? {};

  SourceKind source;
  String deviceName;
  ChannelNaming naming;

  /// Reczna sciezka libbacore; puste = wyszukanie automatyczne.
  String libPath;

  /// Instrukcja przed treningiem.
  bool showInstruction;

  /// Sprawdzanie nowych wydan na GitHubie przy starcie.
  bool checkUpdates;

  /// Krotka sesja do testow (zmiana z pomoca AI, Claude): okolo 2 minut
  /// zamiast okolo 12. Takie sesje licza sie do historii jak zwykle.
  bool quickSession;

  /// Token GitHub z prawem odczytu, tylko dla prywatnego repozytorium.
  String updateToken;

  /// Wersja, o ktorej uzytkownik kazal nie przypominac.
  String skippedVersion;

  /// Id protokolu -> wybrane kanaly treningowe (brak = domyslne protokolu).
  final Map<String, List<String>> training;

  static const _keys = {
    'source': 'source',
    'device': 'device_name',
    'naming': 'channel_names',
    'lib': 'bacore_lib',
    'instruction': 'show_instruction',
    'updates': 'check_updates',
    'quick': 'quick_session',
    'token': 'update_token',
    'skipped': 'update_skipped',
  };

  /// Zrodlo Demo zawsze uzywa nazw 10-20.
  String get deviceModel =>
      source == SourceKind.device ? deviceModelOf(deviceName) : 'MAXI';

  ChannelNaming get effectiveNaming {
    if (source == SourceKind.demo) return ChannelNaming.manufacturer;
    if (deviceModel != 'MAXI') return ChannelNaming.numbered;
    return naming;
  }

  List<String> get channelNames => effectiveNaming == ChannelNaming.manufacturer
      ? maxiManufacturerNames
      : numberedNames(deviceModelChannels[deviceModel]!);

  /// Nazwa kanalu zapisanego w trybie producenta po zmianie nazewnictwa.
  List<String> trainingChannelsFor(TrainingProtocol p) {
    final names = channelNames;
    final chosen = [
      for (final n in training[p.id] ?? const <String>[])
        if (names.contains(n)) n,
    ];
    if (chosen.isNotEmpty) return chosen;
    if (effectiveNaming == ChannelNaming.manufacturer) return p.channels;
    if (deviceModel == 'MAXI') {
      return [for (final n in p.channels) _numberFor(n)];
    }
    return names.take(4).toList();
  }

  String _numberFor(String name) {
    final i = maxiManufacturerNames.indexOf(name);
    return i < 0 ? name : 'ch${i + 1}';
  }

  /// Indeksy kanalow (od 0) dla aktywnej masy: do dwoch pierwszych kanalow treningowych.
  List<int> biasIndicesFor(TrainingProtocol p) {
    final names = channelNames;
    return [
      for (final n in trainingChannelsFor(p))
        if (names.contains(n)) names.indexOf(n),
    ].take(2).toList();
  }

  static const _posterior = [
    'O1',
    'O2',
    'Oz',
    'POz',
    'PO3',
    'PO4',
    'Pz',
    'P3',
    'P4',
    'P7',
    'P8',
  ];

  /// Kanaly treningowe z tych, ktore maja kontakt: najpierw tyl glowy (alfa),
  /// w razie braku pierwsze z kontaktem, do czterech.
  static List<String> channelsWithContact(List<ChannelContact> contacts) {
    final ok = [
      for (final c in contacts)
        if (c.contact) c.name,
    ];
    final back = [
      for (final n in _posterior)
        if (ok.contains(n)) n,
    ];
    return (back.isNotEmpty ? back : ok).take(4).toList();
  }

  static AppSettings load(SessionRepository repo) {
    final s = AppSettings(
      source: repo.setting(_keys['source']!) == 'device'
          ? SourceKind.device
          : SourceKind.demo,
      deviceName: repo.setting(_keys['device']!) ?? '',
      naming: repo.setting(_keys['naming']!) == 'numbered'
          ? ChannelNaming.numbered
          : ChannelNaming.manufacturer,
      libPath: repo.setting(_keys['lib']!) ?? '',
      showInstruction: repo.setting(_keys['instruction']!) != 'off',
      checkUpdates: repo.setting(_keys['updates']!) != 'off',
      quickSession: repo.setting(_keys['quick']!) == 'on',
      updateToken: repo.setting(_keys['token']!) ?? '',
      skippedVersion: repo.setting(_keys['skipped']!) ?? '',
    );
    for (final p in TrainingProtocol.all) {
      final v = repo.setting('train_${p.id}');
      if (v != null && v.isNotEmpty) s.training[p.id] = v.split(',');
    }
    return s;
  }

  void save(SessionRepository repo) {
    repo.setSetting(
      _keys['source']!,
      source == SourceKind.device ? 'device' : 'demo',
    );
    repo.setSetting(_keys['device']!, deviceName);
    repo.setSetting(
      _keys['naming']!,
      naming == ChannelNaming.numbered ? 'numbered' : 'manufacturer',
    );
    repo.setSetting(_keys['lib']!, libPath);
    repo.setSetting(_keys['instruction']!, showInstruction ? 'on' : 'off');
    repo.setSetting(_keys['updates']!, checkUpdates ? 'on' : 'off');
    repo.setSetting(_keys['quick']!, quickSession ? 'on' : 'off');
    repo.setSetting(_keys['token']!, updateToken);
    repo.setSetting(_keys['skipped']!, skippedVersion);
    for (final p in TrainingProtocol.all) {
      repo.setSetting('train_${p.id}', (training[p.id] ?? const []).join(','));
    }
  }
}
