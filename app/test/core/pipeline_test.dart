import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/dsp/alpha_pipeline.dart';
import 'package:neurotchi/core/dsp/calibration.dart';
import 'package:neurotchi/core/dsp/processing_config.dart';
import 'package:neurotchi/core/eeg/eeg_source.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';

const cfg = ProcessingConfig();

Future<List<WindowResult>> run(EegSource source) async {
  final pipe = AlphaPipeline(cfg, trainingChannels: ['O1', 'O2']);
  final out = <WindowResult>[];
  final done = source.items.forEach((i) => out.addAll(pipe.push(i)));
  await source.start();
  await done;
  return out;
}

MockSource mock({
  double Function(double)? amp,
  Set<int> drop = const {},
  double noise = 3,
  int seconds = 12,
}) =>
    MockSource(
      duration: Duration(seconds: seconds),
      alphaAmplitudeUv: amp ?? (_) => 20,
      noiseUv: noise,
      dropChunks: drop,
    );

void main() {
  test('moc alfa czystej sinusoidy: x = ln(A^2 / 2)', () async {
    final w = (await run(mock())).where((r) => r.valid).toList();
    expect(w, isNotEmpty);
    for (final r in w.skip(3)) {
      expect(r.feature, closeTo(log(20 * 20 / 2), 0.15));
    }
  });

  test('dwukrotnie wieksza amplituda daje wzrost x o ln 4', () async {
    final a = (await run(mock(amp: (_) => 10))).where((r) => r.valid).last;
    final b = (await run(mock(amp: (_) => 20))).where((r) => r.valid).last;
    expect(b.feature! - a.feature!, closeTo(log(4), 0.1));
  });

  test('amplituda powyzej progu unieważnia okno', () async {
    final w = await run(mock(amp: (_) => 150));
    expect(w, isNotEmpty);
    expect(w.every((r) => !r.valid && r.reason == InvalidReason.amplitude), isTrue);
  });

  test('plaski sygnal jest niewazny', () async {
    final w = await run(mock(amp: (_) => 0, noise: 0));
    expect(w.every((r) => r.reason == InvalidReason.flat), isTrue);
  });

  test('nasycenie przetwornika jest niewazne', () async {
    final pipe = AlphaPipeline(cfg, trainingChannels: ['O1']);
    pipe.push(const SegmentStart(StreamInfo(
        sourceId: 't', fs: 250, channels: [Channel('O1')], chunkSize: 25)));
    final out = <WindowResult>[];
    for (var p = 0; p < 30; p++) {
      out.addAll(pipe.push(EegPacket(
        firstSample: p * 25,
        tRecv: 0,
        samples: [List.filled(25, 562500.0)],
      )));
    }
    expect(out.first.reason, InvalidReason.saturation);
  });

  test('szerokopasmowa aktywnosc 30 do 40 Hz jest oznaczana jako miesniowa', () async {
    final pipe = AlphaPipeline(cfg, trainingChannels: ['O1']);
    pipe.push(const SegmentStart(StreamInfo(
        sourceId: 't', fs: 250, channels: [Channel('O1')], chunkSize: 25)));
    final out = <WindowResult>[];
    for (var p = 0; p < 40; p++) {
      out.addAll(pipe.push(EegPacket(
        firstSample: p * 25,
        tRecv: 0,
        samples: [
          [
            for (var i = 0; i < 25; i++)
              20 * sin(2 * pi * 35 * (p * 25 + i) / 250) +
                  5 * sin(2 * pi * 10 * (p * 25 + i) / 250)
          ]
        ],
      )));
    }
    expect(out.last.reason, InvalidReason.muscle);
  });

  test('luka niewazni okna obejmujace ja i filtr ustala sie po 1 s', () async {
    final w = await run(mock(drop: {20}));
    final reasons = [for (final r in w) r.reason];
    final firstGap = reasons.indexOf(InvalidReason.gap);
    final lastGap = reasons.lastIndexOf(InvalidReason.gap);
    expect(firstGap, greaterThan(0));
    expect(reasons.sublist(firstGap, lastGap + 1).every((r) => r == InvalidReason.gap), isTrue);
    expect(w.last.valid, isTrue);
  });

  test('kalibracja i mapowanie na danych z zmiana amplitudy', () async {
    final w = await run(mock(amp: (t) => t < 20 ? 10 : 30, seconds: 40));
    final calib = calibrate([for (final r in w) if (r.tSec <= 20) r], cfg);
    expect(calib.accepted, isTrue);
    expect(calib.baseline!.median, closeTo(log(10 * 10 / 2), 0.2));
    final mapper = FeedbackMapper(cfg, calib.baseline!);
    final ys = [for (final r in w.where((r) => r.tSec > 30)) mapper.push(r).y];
    expect(ys.last, greaterThan(calib.thresholdY!));
    expect(ys.last, greaterThan(0.9));
  });

  test('kalibracja odrzucona przy zbyt malej liczbie waznych okien', () {
    final ws = [
      for (var i = 0; i < 40; i++)
        WindowResult(
          sampleEnd: 0,
          tSec: 10 + i * 0.256,
          valid: i % 3 != 0,
          feature: 1.0,
          reason: i % 3 == 0 ? InvalidReason.gap : null,
        ),
    ];
    final r = calibrate(ws, cfg);
    expect(r.accepted, isFalse);
    expect(r.validRatio, lessThan(0.9));
  });

  test('wygladzanie wraca do wartosci neutralnej po oknie niewaznym', () {
    final m = FeedbackMapper(cfg, const Baseline(0, 1));
    for (var i = 0; i < 50; i++) {
      m.push(const WindowResult(sampleEnd: 0, tSec: 0, valid: true, feature: 5));
    }
    final high = m.push(const WindowResult(sampleEnd: 0, tSec: 0, valid: true, feature: 5));
    expect(high.y, greaterThan(0.9));
    final bad = m.push(const WindowResult(
        sampleEnd: 0, tSec: 0, valid: false, reason: InvalidReason.gap));
    expect(bad.y, FeedbackMapper.neutral);
  });

  test('nagroda po utrzymaniu celu, histereza i przerwanie przez okno niewazne', () {
    final d = RewardDetector(threshold: 0.6, holdS: 1.5, stepS: 0.256);
    const hi = FeedbackSample(valid: true, y: 0.8);
    const lo = FeedbackSample(valid: true, y: 0.4);
    const bad = FeedbackSample(valid: false, y: 0.5);
    final rewards = <int>[];
    final seq = [
      ...List.filled(5, hi), bad, ...List.filled(5, hi),
      hi, hi, hi, hi, hi, hi,
      lo, ...List.filled(6, hi),
    ];
    for (var i = 0; i < seq.length; i++) {
      if (d.push(seq[i])) rewards.add(i);
    }
    expect(rewards, [11, 23]);
  });
}
