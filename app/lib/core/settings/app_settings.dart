import '../db/session_repository.dart';
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
    Map<String, List<String>>? training,
  }) : training = training ?? {};

  SourceKind source;
  String deviceName;
  ChannelNaming naming;

  /// Reczna sciezka libbacore; puste = wyszukanie automatyczne.
  String libPath;

  /// Id protokolu -> wybrane kanaly treningowe (brak = domyslne protokolu).
  final Map<String, List<String>> training;

  static const _keys = {
    'source': 'source',
    'device': 'device_name',
    'naming': 'channel_names',
    'lib': 'bacore_lib',
  };

  /// Zrodlo Demo zawsze uzywa nazw 10-20.
  ChannelNaming get effectiveNaming => source == SourceKind.demo ? ChannelNaming.manufacturer : naming;

  List<String> get channelNames => effectiveNaming == ChannelNaming.manufacturer
      ? maxiManufacturerNames
      : numberedNames(maxiManufacturerNames.length);

  /// Nazwa kanalu zapisanego w trybie producenta po zmianie nazewnictwa.
  List<String> trainingChannelsFor(TrainingProtocol p) {
    final chosen = training[p.id];
    if (chosen != null && chosen.isNotEmpty) return chosen;
    return effectiveNaming == ChannelNaming.manufacturer
        ? p.channels
        : [for (final n in p.channels) _numberFor(n)];
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

  static AppSettings load(SessionRepository repo) {
    final s = AppSettings(
      source: repo.setting(_keys['source']!) == 'device' ? SourceKind.device : SourceKind.demo,
      deviceName: repo.setting(_keys['device']!) ?? '',
      naming: repo.setting(_keys['naming']!) == 'numbered'
          ? ChannelNaming.numbered
          : ChannelNaming.manufacturer,
      libPath: repo.setting(_keys['lib']!) ?? '',
    );
    for (final p in TrainingProtocol.all) {
      final v = repo.setting('train_${p.id}');
      if (v != null && v.isNotEmpty) s.training[p.id] = v.split(',');
    }
    return s;
  }

  void save(SessionRepository repo) {
    repo.setSetting(_keys['source']!, source == SourceKind.device ? 'device' : 'demo');
    repo.setSetting(_keys['device']!, deviceName);
    repo.setSetting(_keys['naming']!, naming == ChannelNaming.numbered ? 'numbered' : 'manufacturer');
    repo.setSetting(_keys['lib']!, libPath);
    for (final p in TrainingProtocol.all) {
      repo.setSetting('train_${p.id}', (training[p.id] ?? const []).join(','));
    }
  }
}
