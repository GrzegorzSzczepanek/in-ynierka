import 'dart:io';
import 'dart:math';

import 'package:neurotchi/core/eeg/replay_source.dart';

/// Dla nagrania, w ktorym stukasz kolejno w elektrody, wypisuje w kazdym
/// przedziale czasu kanaly o najwiekszej aktywnosci (std roznic probek).
/// dart run tool/channel_activity.dart nagrania/sesja1 [sekundy_na_przedzial]
Future<void> main(List<String> args) async {
  final rec = await Recording.load(args[0]);
  final bin = (args.length > 1 ? double.parse(args[1]) : 5.0);
  final n = (bin * rec.info.fs).round();
  final total = rec.sampleNumbers.length;
  for (var start = 0; start + n <= total; start += n) {
    final act = <(int, double)>[];
    for (var c = 0; c < rec.data.length; c++) {
      final d = [
        for (var i = start + 1; i < start + n; i++)
          rec.data[c][i] - rec.data[c][i - 1]
      ];
      final m = d.reduce((a, b) => a + b) / d.length;
      final v = d.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / d.length;
      act.add((c, sqrt(v)));
    }
    final sorted = [...act]..sort((a, b) => b.$2.compareTo(a.$2));
    final med = ([...act.map((a) => a.$2)]..sort())[act.length ~/ 2];
    final t0 = (start / rec.info.fs).toStringAsFixed(0);
    final top = sorted
        .take(3)
        .map((a) => '${rec.info.channels[a.$1].name} (x${(a.$2 / med).toStringAsFixed(1)})')
        .join(', ');
    stdout.writeln('t=${t0.padLeft(4)} s: $top');
  }
}
