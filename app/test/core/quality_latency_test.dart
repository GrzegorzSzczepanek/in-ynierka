import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/dsp/alpha_pipeline.dart';
import 'package:neurotchi/core/dsp/processing_config.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';
import 'package:neurotchi/core/research/latency.dart';
import 'package:neurotchi/ui/format.dart';

const _fs = 250;
const _chunk = 25;
const _warmN = 12 * _fs;

class _Artifact {
  const _Artifact(this.name, this.start, this.end, this.apply);

  final String name;
  final int start;
  final int end;
  final double Function(int n, int ch, double base) apply;
}

class _Outcome {
  _Outcome(this.windows);

  final List<WindowResult> windows;
}

double _evalTimeS(WindowResult w) => ((w.sampleEnd + _chunk - 1) ~/ _chunk) * _chunk / _fs;

_Outcome _simulate(int total, _Artifact? art, {int? gapAtChunk}) {
  final rng = Random(7);
  final pipe = AlphaPipeline(
    const ProcessingConfig(),
    trainingChannels: const ['O1', 'O2'],
  );
  pipe.push(
    const SegmentStart(
      StreamInfo(
        sourceId: 'quality',
        fs: _fs,
        channels: [Channel('O1'), Channel('O2')],
        chunkSize: _chunk,
      ),
    ),
  );
  final out = <WindowResult>[];
  for (var k = 0; k * _chunk < total; k++) {
    if (gapAtChunk != null && k == gapAtChunk) {
      continue;
    }
    if (gapAtChunk != null && k == gapAtChunk + 1) {
      out.addAll(
        pipe.push(GapEvent(firstSample: (k - 1) * _chunk, count: _chunk)),
      );
    }
    final first = k * _chunk;
    final samples = [
      for (var c = 0; c < 2; c++)
        [
          for (var i = 0; i < _chunk; i++)
            () {
              final n = first + i;
              final base =
                  15 * sin(2 * pi * 10 * n / _fs + 0.3 * c) +
                  (rng.nextDouble() * 2 - 1) * 3 * sqrt(3);
              if (art != null && n >= art.start && n < art.end) {
                return art.apply(n, c, base);
              }
              return base;
            }(),
        ],
    ];
    out.addAll(
      pipe.push(
        EegPacket(
          firstSample: first,
          tRecv: first / _fs,
          samples: samples,
        ),
      ),
    );
  }
  return _Outcome(out);
}

class _Stats {
  _Stats(this.name);

  final String name;
  final delay = <double>[];
  final recovery = <double>[];
  final reasons = <String, int>{};
  final labelMid = <double>[];
  final labelBad = <double>[];
  final labelBack = <double>[];
  int runs = 0;
  int undetected = 0;

  String line() {
    String f(List<double> v) => v.isEmpty
        ? 'brak'
        : 'min ${percentileOf(v, 0).toStringAsFixed(3)} '
              'p50 ${percentileOf(v, 50).toStringAsFixed(3)} '
              'p95 ${percentileOf(v, 95).toStringAsFixed(3)} '
              'max ${percentileOf(v, 100).toStringAsFixed(3)}';
    return '$name n=${runs + undetected} niewykryte=$undetected powod=$reasons\n'
        '    wykrycie [s]: ${f(delay)}\n'
        '    powrot do waznych okien po koncu artefaktu [s]: ${f(recovery)}\n'
        '    etykieta UI "srednio" po [s]: ${f(labelMid)}\n'
        '    etykieta UI "slabo" po [s]: ${f(labelBad)}\n'
        '    etykieta UI "dobry" ponownie po [s]: ${f(labelBack)}';
  }
}

_Stats _measure(
  String name,
  int durationSamples,
  double Function(int n, int ch, double base) apply, {
  int runs = 229,
}) {
  final st = _Stats(name);
  for (var i = 0; i < runs; i++) {
    final s0 = _warmN + 640 + i * 7;
    final art = _Artifact(name, s0, s0 + durationSamples, apply);
    final o = _simulate(s0 + durationSamples + 14 * _fs, art);
    final before = o.windows.where((w) => w.sampleEnd <= s0);
    expect(before.every((w) => w.valid || w.sampleEnd < _warmN), isTrue,
        reason: '$name: okno przed artefaktem uznane za niewazne');
    final firstBad = o.windows.firstWhere(
      (w) => !w.valid && w.sampleEnd > s0,
      orElse: () => const WindowResult(sampleEnd: -1, tSec: 0, valid: false),
    );
    if (firstBad.sampleEnd < 0) {
      st.undetected++;
      continue;
    }
    st.runs++;
    st.delay.add(_evalTimeS(firstBad) - s0 / _fs);
    st.reasons[firstBad.reason!.name] =
        (st.reasons[firstBad.reason!.name] ?? 0) + 1;
    final end = s0 + durationSamples;
    final back = o.windows.firstWhere(
      (w) => w.valid && w.sampleEnd > end,
      orElse: () => const WindowResult(sampleEnd: -1, tSec: 0, valid: true),
    );
    if (back.sampleEnd > 0) st.recovery.add(_evalTimeS(back) - end / _fs);

    final recent = <bool>[];
    String? last;
    for (final w in o.windows) {
      recent.add(w.valid);
      if (recent.length > 20) recent.removeAt(0);
      if (w.sampleEnd <= s0) {
        last = qualityLabel(recent.where((v) => v).length / recent.length);
        continue;
      }
      final label = qualityLabel(recent.where((v) => v).length / recent.length);
      final t = _evalTimeS(w) - s0 / _fs;
      if (label != 'dobry' && st.labelMid.length == st.runs - 1) {
        st.labelMid.add(t);
      }
      if (label == 'słaby' && st.labelBad.length == st.runs - 1) {
        st.labelBad.add(t);
      }
      if (label == 'dobry' &&
          st.labelMid.length == st.runs &&
          st.labelBack.length == st.runs - 1) {
        st.labelBack.add(_evalTimeS(w) - end / _fs);
      }
      last = label;
    }
    expect(last, isNotNull);
  }
  return st;
}

void main() {
  const step = 64 / _fs;
  const chunk = _chunk / _fs;
  final report = StringBuffer();

  test('parametry okna: 2 s, krok 64 probki, pakiet 25 probek', () {
    const c = ProcessingConfig();
    expect(c.windowS, 2.0);
    expect(c.stepSamples, 64);
    expect((c.windowS * _fs).round(), 500);
    expect(c.stepSamples / _fs, closeTo(0.256, 1e-12));
  });

  test('skok amplitudy: impuls jednopróbkowy o rosnącej amplitudzie', () {
    for (final a in [300.0, 1000.0, 3000.0, 10000.0]) {
      final s = _measure('impuls_${a.round()}uV', 1, (n, c, b) => b + a, runs: 64);
      report.writeln(s.line());
      if (a >= 10000) {
        expect(s.undetected, 0);
        expect(percentileOf(s.delay, 100), lessThanOrEqualTo(step + chunk + 0.1));
      }
    }
  });

  test('amplituda: seria 10 Hz o amplitudzie 200 uV przez 1 s', () {
    final s = _measure(
      'seria_200uV_1s',
      _fs,
      (n, c, b) => b + 200 * sin(2 * pi * 10 * n / _fs),
    );
    report.writeln(s.line());
    expect(s.undetected, 0);
    expect(percentileOf(s.delay, 100), lessThanOrEqualTo(step + chunk + 0.1));
  });

  test('nasycenie: szyna 562500 uV przez 0,4 s', () {
    final s = _measure('nasycenie_0_4s', 100, (n, c, b) => c == 0 ? 562500 : b);
    report.writeln(s.line());
    expect(s.reasons.keys.single, 'saturation');
    expect(s.undetected, 0);
    expect(percentileOf(s.delay, 100), lessThanOrEqualTo(step + chunk + 1e-9));
  });

  test('plaska linia: stala wartosc na jednym kanale', () {
    final s = _measure('plaska_linia_5s', 5 * _fs, (n, c, b) => c == 0 ? 0 : b);
    report.writeln(s.line());
    expect(s.reasons.keys.single, 'flat');
    expect(s.undetected, 0);
    expect(percentileOf(s.delay, 0), greaterThanOrEqualTo(2.0 - 1e-9));
  });

  test('aktywnosc miesniowa: 35 Hz o amplitudzie 25 uV', () {
    final s = _measure(
      'miesnie_35Hz_25uV_5s',
      5 * _fs,
      (n, c, b) => b + 25 * sin(2 * pi * 35 * n / _fs),
    );
    report.writeln(s.line());
    expect(s.reasons.keys, contains('muscle'));
  });

  test('luka w numeracji probek (utrata jednej paczki)', () {
    final recov = <double>[];
    final delay = <double>[];
    for (var i = 0; i < 64; i++) {
      final gapChunk = 12 * _fs ~/ _chunk + 30 + i % 3;
      final o = _simulate(40 * _fs, null, gapAtChunk: gapChunk);
      final gapAt = gapChunk * _chunk;
      final bad = o.windows.firstWhere((w) => !w.valid && w.sampleEnd > gapAt);
      delay.add(_evalTimeS(bad) - gapAt / _fs);
      final ok = o.windows.firstWhere((w) => w.valid && w.sampleEnd > gapAt);
      recov.add(_evalTimeS(ok) - gapAt / _fs);
      expect(bad.reason, InvalidReason.gap);
    }
    expect(percentileOf(recov, 100), lessThanOrEqualTo(3.0 + 2 * chunk + step));
    report.writeln(
      'luka_1_paczki n=${delay.length}: wykrycie [s] p50 '
      '${percentileOf(delay, 50).toStringAsFixed(3)} max '
      '${percentileOf(delay, 100).toStringAsFixed(3)}; powrot do waznych okien '
      'od luki [s] p50 ${percentileOf(recov, 50).toStringAsFixed(3)} max '
      '${percentileOf(recov, 100).toStringAsFixed(3)}',
    );
    expect(percentileOf(delay, 100), lessThanOrEqualTo(step + 2 * chunk + 1e-9));
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('\n=== WF-3: czas zmiany stanu jakosci (czas probek, 250 Hz) ===\n$report');
  });
}
