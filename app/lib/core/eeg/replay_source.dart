import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'eeg_source.dart';
import 'stream_item.dart';

/// Nagranie: `<nazwa>.json` (metadane strumienia) i `<nazwa>.csv`
/// (naglowek `sample_number,<kanaly>`, jedna probka na wiersz, uV).
class Recording {
  Recording(this.info, this.sampleNumbers, this.data);

  final StreamInfo info;
  final List<int> sampleNumbers;

  /// [kanal][probka]
  final List<List<double>> data;

  static Future<Recording> load(String basePath) async {
    final meta = jsonDecode(
      await File('$basePath.json').readAsString(),
    ) as Map<String, dynamic>;
    final lines = await File('$basePath.csv').readAsLines();
    final info = StreamInfo(
      contract: meta['contract'] as int,
      sourceId: meta['sourceId'] as String,
      fs: meta['fs'] as int,
      chunkSize: meta['chunkSize'] as int,
      channels: [
        for (final c in meta['channels'] as List)
          Channel(c['name'] as String, unit: c['unit'] as String),
      ],
    );
    return parse(info, lines);
  }

  static Recording parse(StreamInfo info, List<String> lines) {
    final sn = <int>[];
    final data = [for (final _ in info.channels) <double>[]];
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(',');
      sn.add(int.parse(parts[0]));
      for (var c = 0; c < data.length; c++) {
        data[c].add(double.parse(parts[c + 1]));
      }
    }
    return Recording(info, sn, data);
  }

  Map<String, dynamic> metaJson() => {
    'contract': info.contract,
    'sourceId': info.sourceId,
    'fs': info.fs,
    'chunkSize': info.chunkSize,
    'channels': [
      for (final c in info.channels) {'name': c.name, 'unit': c.unit},
    ],
  };

  List<String> csvLines() => [
    'sample_number,${info.channels.map((c) => c.name).join(',')}',
    for (var i = 0; i < sampleNumbers.length; i++)
      '${sampleNumbers[i]},${[for (final ch in data) ch[i]].join(',')}',
  ];

  Future<void> save(String basePath) async {
    await File('$basePath.json').writeAsString(jsonEncode(metaJson()));
    await File('$basePath.csv').writeAsString('${csvLines().join('\n')}\n');
  }
}

class ReplaySource implements EegSource {
  ReplaySource(this.recording, {this.realtime = false});

  final Recording recording;
  final bool realtime;

  final _controller = StreamController<StreamItem>();
  bool _running = false;

  @override
  Stream<StreamItem> get items => _controller.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    unawaited(_run());
  }

  @override
  Future<void> stop() async {
    _running = false;
  }

  Future<void> _run() async {
    final info = recording.info;
    final sn = recording.sampleNumbers;
    _controller.add(SegmentStart(info));
    final period = Duration(
      microseconds: (info.chunkSize * 1e6 / info.fs).round(),
    );
    var i = 0;
    var sent = 0;
    while (_running && i < sn.length) {
      var end = i + 1;
      while (end < sn.length &&
          end - i < info.chunkSize &&
          sn[end] == sn[end - 1] + 1) {
        end++;
      }
      if (i > 0 && sn[i] != sn[i - 1] + 1) {
        _controller.add(
          GapEvent(firstSample: sn[i - 1] + 1, count: sn[i] - sn[i - 1] - 1),
        );
      }
      _controller.add(
        EegPacket(
          firstSample: sn[i],
          tRecv: sn[i] / info.fs,
          samples: [for (final ch in recording.data) ch.sublist(i, end)],
        ),
      );
      i = end;
      sent++;
      if (realtime) {
        await Future<void>.delayed(period);
      } else if (sent % 50 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    await _controller.close();
  }
}
