import 'dart:io';

import 'package:neurotchi/core/dsp/alpha_pipeline.dart';
import 'package:neurotchi/core/dsp/processing_config.dart';
import 'package:neurotchi/core/eeg/replay_source.dart';

/// Przepuszcza nagranie przez potok alfa i podaje, ile okien jest waznych.
/// dart run tool/pipeline_report.dart nagrania/bias ch1,ch5 [lowHz] [ampUv]
Future<void> main(List<String> args) async {
  final channels = args[1].split(',');
  final low = args.length > 2 ? double.parse(args[2]) : 1.0;
  final amp = args.length > 3 ? double.parse(args[3]) : 100.0;
  final rec = await Recording.load(args[0]);
  final cfg = ProcessingConfig(filterLowHz: low, ampThresholdUv: amp);
  final pipe = AlphaPipeline(cfg, trainingChannels: channels);
  final out = <WindowResult>[];
  final src = ReplaySource(rec);
  final done = src.items.forEach((i) => out.addAll(pipe.push(i)));
  await src.start();
  await done;
  final reasons = <String, int>{};
  for (final w in out.where((w) => !w.valid)) {
    reasons[w.reason!.name] = (reasons[w.reason!.name] ?? 0) + 1;
  }
  final xs = [for (final w in out) if (w.valid) w.feature!];
  stdout.writeln('kanaly=$channels filtr=${low}Hz-40Hz amp=${amp}uV');
  stdout.writeln('okna=${out.length} wazne=${xs.length} niewazne=$reasons');
  if (xs.isNotEmpty) {
    stdout.writeln('x: min=${xs.reduce((a, b) => a < b ? a : b).toStringAsFixed(2)} '
        'max=${xs.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)}');
  }
}
