import 'dart:io';
import 'dart:math';

import 'package:neurotchi/core/dsp/biquad.dart';
import 'package:neurotchi/core/eeg/replay_source.dart';

/// Odchylenie standardowe (uV) kazdego kanalu po filtrze 1 do 40 Hz i notchu
/// 50 Hz, bez pierwszych 3 s. Prawdziwe EEG to zwykle dziesiatki uV.
/// dart run tool/signal_stats.dart nagrania/sesja1
Future<void> main(List<String> args) async {
  final rec = await Recording.load(args[0]);
  final fs = rec.info.fs.toDouble();
  final skip = (3 * fs).round();
  final rows = <(String, double)>[];
  for (var c = 0; c < rec.data.length; c++) {
    final f = SosFilter.bandpass(
        fs: fs, lowHz: 1, highHz: 40, order: 4, notchHz: 50);
    final y = [for (final x in rec.data[c]) f.process(x)].sublist(skip);
    final m = y.reduce((a, b) => a + b) / y.length;
    final v = y.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / y.length;
    rows.add((rec.info.channels[c].name, sqrt(v)));
  }
  rows.sort((a, b) => a.$2.compareTo(b.$2));
  for (final r in rows) {
    stdout.writeln('${r.$1.padRight(5)} ${r.$2.toStringAsFixed(1)} uV');
  }
}
