import 'dart:convert';
import 'dart:io';

import 'replay_source.dart';
import 'stream_item.dart';

/// Zapisuje strumien do pary `<base>.json` + `<base>.csv` (format [Recording]).
/// Jeden segment na plik. Luki w numeracji probek zostaja w pliku jako skok
/// sample_number, bez interpolacji.
class RecordingWriter {
  RecordingWriter(this.basePath);

  final String basePath;
  IOSink? _csv;
  int samples = 0;

  Future<void> add(StreamItem item) async {
    switch (item) {
      case SegmentStart():
        if (_csv != null) throw StateError('Plik zawiera tylko jeden segment');
        final meta = Recording(item.info, const [], const []).metaJson();
        File('$basePath.json').writeAsStringSync(jsonEncode(meta));
        _csv = File('$basePath.csv').openWrite()
          ..writeln(
              'sample_number,${item.info.channels.map((c) => c.name).join(',')}');
      case EegPacket():
        final csv = _csv;
        if (csv == null) throw StateError('Brak SegmentStart');
        for (var i = 0; i < item.length; i++) {
          csv.writeln(
              '${item.firstSample + i},${[for (final ch in item.samples) ch[i]].join(',')}');
        }
        samples += item.length;
      case GapEvent():
      case DisconnectedEvent():
        break;
    }
  }

  Future<void> close() async {
    await _csv?.flush();
    await _csv?.close();
    _csv = null;
  }
}
