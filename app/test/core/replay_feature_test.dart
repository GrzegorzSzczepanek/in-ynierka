import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/dsp/alpha_pipeline.dart';
import 'package:neurotchi/core/dsp/processing_config.dart';
import 'package:neurotchi/core/eeg/eeg_source.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/eeg/recording_writer.dart';
import 'package:neurotchi/core/eeg/replay_source.dart';
import 'package:neurotchi/core/session/session_controller.dart';
import 'package:neurotchi/core/session/session_models.dart';

Future<List<WindowResult>> _through(EegSource src) async {
  final pipe = AlphaPipeline(
    const ProcessingConfig(),
    trainingChannels: const ['O1', 'O2'],
  );
  final out = <WindowResult>[];
  final done = src.items.forEach((i) => out.addAll(pipe.push(i)));
  await src.start();
  await done;
  return out;
}

void main() {
  test('replay zapisanej sesji daje identyczny przebieg cechy (okna, powody, wartosci)', () async {
    final dir = Directory.systemTemp.createTempSync('replay_feature');
    final base = '${dir.path}/s';
    MockSource mk() => MockSource(
      duration: const Duration(seconds: 120),
      alphaAmplitudeUv: (t) => t > 40 && t < 44 ? 300 : 12 + 8 * (t > 70 ? 1 : 0),
      betaAmplitudeUv: (t) => 4,
      dropChunks: {400, 401, 900},
      noiseUv: 3,
    );

    final writer = RecordingWriter(base);
    final src = mk();
    final live = <WindowResult>[];
    final pipe = AlphaPipeline(
      const ProcessingConfig(),
      trainingChannels: const ['O1', 'O2'],
    );
    final done = src.items.asyncMap((i) async {
      live.addAll(pipe.push(i));
      await writer.add(i);
    }).drain<void>();
    await src.start();
    await done;
    await writer.close();

    final rec = await Recording.load(base);
    final replayed = await _through(ReplaySource(rec));

    expect(replayed.length, live.length);
    var worst = 0.0;
    var nValid = 0;
    var nInvalid = 0;
    for (var i = 0; i < live.length; i++) {
      expect(replayed[i].sampleEnd, live[i].sampleEnd);
      expect(replayed[i].valid, live[i].valid);
      expect(replayed[i].reason, live[i].reason);
      if (live[i].valid) {
        nValid++;
        final d = (replayed[i].feature! - live[i].feature!).abs();
        if (d > worst) worst = d;
        expect(replayed[i].peakHz, live[i].peakHz);
      } else {
        nInvalid++;
      }
    }
    // ignore: avoid_print
    print(
      'WN 3.2 replay: okna=${live.length} (wazne $nValid, niewazne $nInvalid), '
      'max roznica cechy=$worst',
    );
    expect(worst, 0.0);
    expect(nInvalid, greaterThan(0));
  });

  test('replay sesji daje te same wyniki blokow co zrodlo na zywo', () async {
    const cfg = SessionConfig(
      calibrationS: 20,
      blocks: 2,
      blockS: 10,
      breakS: 4,
      contactSettleS: 1,
      contactStableS: 1,
      calibrationClosedS: 0,
    );
    MockSource mk() => MockSource(
      duration: const Duration(seconds: 90),
      alphaAmplitudeUv: (t) => 14 + 6 * ((t * 0.7).floor() % 2),
      noiseUv: 2,
    );
    final dir = Directory.systemTemp.createTempSync('replay_session');
    final base = '${dir.path}/s';
    final writer = RecordingWriter(base);
    final c1 = SessionController(
      sourceFactory: mk,
      config: cfg,
      delay: (_) async {},
      onItem: (i) => writer.add(i),
    );
    final r1 = await c1.run();
    await writer.close();
    final rec = await Recording.load(base);
    final c2 = SessionController(
      sourceFactory: () => ReplaySource(rec),
      config: cfg,
      delay: (_) async {},
    );
    final r2 = await c2.run();
    expect(r2.blocks.length, r1.blocks.length);
    expect(r2.calibrations.length, r1.calibrations.length);
    var worst = 0.0;
    for (var i = 0; i < r1.calibrations.length; i++) {
      final a = r1.calibrations[i].result, b = r2.calibrations[i].result;
      expect(b.accepted, a.accepted);
      worst = [
        worst,
        (a.baseline!.median - b.baseline!.median).abs(),
        (a.baseline!.scale - b.baseline!.scale).abs(),
        (a.thresholdY! - b.thresholdY!).abs(),
      ].reduce((x, y) => x > y ? x : y);
    }
    for (var i = 0; i < r1.blocks.length; i++) {
      final a = r1.blocks[i], b = r2.blocks[i];
      expect(b.rewardCount, a.rewardCount);
      expect(b.validSignalS, a.validSignalS);
      expect(b.timeAboveThresholdS, a.timeAboveThresholdS);
      expect(b.meanY, a.meanY);
      expect(b.yTrace, a.yTrace);
      expect([for (final e in b.events) e.atMs], [for (final e in a.events) e.atMs]);
      worst = worst > (a.meanY - b.meanY).abs() ? worst : (a.meanY - b.meanY).abs();
    }
    // ignore: avoid_print
    print(
      'WN 3.2 replay sesji: bloki=${r1.blocks.length}, nagrody=${[for (final b in r1.blocks) b.rewardCount]}, '
      'max roznica (baseline, prog, meanY)=$worst',
    );
    expect(worst, 0.0);
  });
}
