import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/dsp/biquad.dart';
import 'package:neurotchi/core/dsp/welch.dart';

Map<String, dynamic> _load(String f) =>
    jsonDecode(File('test/fixtures/$f').readAsStringSync())
        as Map<String, dynamic>;

List<double> _list(Map<String, dynamic> m, String k) => [
  for (final v in m[k] as List) (v as num).toDouble(),
];

class _Err {
  _Err(this.maxAbs, this.rms, this.peak);

  final double maxAbs;
  final double rms;
  final double peak;

  String get text =>
      'max|d|=${maxAbs.toExponential} rms=${rms.toExponential} '
      'wzgledem szczytu sygnalu=${(maxAbs / peak).toExponential}';
}

extension on double {
  String get toExponential => toStringAsExponential(3);
}

_Err _compare(List<double> a, List<double> b) {
  var m = 0.0, s = 0.0, peak = 0.0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    m = max(m, d);
    s += d * d;
    peak = max(peak, b[i].abs());
  }
  return _Err(m, sqrt(s / a.length), peak);
}

void main() {
  final lines = StringBuffer();

  void check(String file, double lowHz, double totalLo) {
    final ref = _load(file);
    final x = _list(ref, 'x');
    final expected = _list(ref, 'filtered');
    final f = SosFilter.bandpass(
      fs: 250,
      lowHz: lowHz,
      highHz: 40,
      order: 4,
      notchHz: 50,
    );
    final y = [for (final v in x) f.process(v)];
    final fe = _compare(y, expected);
    final w = Welch(fs: 250, segment: 250, overlap: 125, nfft: 512);
    final psd = w.psd(expected.sublist(expected.length - 500));
    final refPsd = _list(ref, 'psd');
    var psdRel = 0.0;
    var psdAbs = 0.0;
    for (var k = 0; k < psd.length; k++) {
      psdAbs = max(psdAbs, (psd[k] - refPsd[k]).abs());
      psdRel = max(psdRel, (psd[k] - refPsd[k]).abs() / max(refPsd[k].abs(), 1e-30));
    }
    final psdMine = w.psd(y.sublist(y.length - 500));
    double rel(double a, double b) => (a - b).abs() / b.abs();
    final alpha = w.bandPower(psd, 8, 12);
    final hf = w.bandPower(psd, 30, 40);
    final total = w.bandPower(psd, totalLo, 40);
    final aRel = rel(alpha, ref['alpha_power'] as double);
    final hRel = rel(hf, ref['hf_power'] as double);
    final tRel = rel(total, ref['total_power'] as double);
    final aChain = rel(w.bandPower(psdMine, 8, 12), ref['alpha_power'] as double);
    lines.writeln(
      '[$file, lowHz=$lowHz]\n'
      '  filtr (Dart vs SciPy sosfilt, ${x.length} probek): ${fe.text}\n'
      '  Welch (PSD z tego samego wejscia): max bezwzgledny=${psdAbs.toExponential}, '
      'max wzgledny po binach=${psdRel.toExponential}\n'
      '  moc alfa 8-12 Hz: wzgledny=${aRel.toExponential}; moc 30-40 Hz: ${hRel.toExponential}; '
      'moc ${totalLo.round()}-40 Hz: ${tRel.toExponential}\n'
      '  moc alfa z calego lancucha (filtr Dart + Welch Dart) vs SciPy: ${aChain.toExponential}',
    );
    expect(fe.maxAbs, lessThan(1e-6));
    expect(psdRel, lessThan(1e-6));
    expect(aRel, lessThan(1e-9));
    expect(hRel, lessThan(1e-9));
    expect(tRel, lessThan(1e-9));
    expect(aChain, lessThan(1e-6));

    if (ref.containsKey('filtered_butter_band')) {
      final yb = _list(ref, 'filtered_butter_band');
      final d = _compare(y, yb);
      final skip = 500;
      final d2 = _compare(y.sublist(skip), yb.sublist(skip));
      final pb = w.psd(yb.sublist(yb.length - 500));
      final aBand = rel(w.bandPower(pb, 8, 12), ref['alpha_power'] as double);
      lines.writeln(
        '  informacyjnie: kaskada HP4+LP4 (jak w aplikacji) vs scipy butter(4,[3,40],"band"):\n'
        '    caly przebieg: ${d.text}\n'
        '    po 2 s: ${d2.text}\n'
        '    moc alfa 8-12 Hz z butter(band) vs kaskada SciPy: ${aBand.toExponential}',
      );
    }
    if (ref.containsKey('feature')) {
      final feat = log(w.bandPower(psdMine, 8, 12) + 1e-6);
      lines.writeln(
        '  cecha ln(P_alfa+eps) Dart=${feat.toStringAsFixed(9)} '
        'SciPy=${(ref['feature'] as double).toStringAsFixed(9)} '
        'roznica=${(feat - (ref['feature'] as double)).abs().toExponential}',
      );
      expect((feat - (ref['feature'] as double)).abs(), lessThan(1e-9));
    }
  }

  test('zgodnosc ze SciPy: fixture lowHz=1 (istniejacy)', () {
    check('dsp_reference.json', 1, 1);
  });

  test('zgodnosc ze SciPy: pasmo 3-40 Hz (domyslna konfiguracja)', () {
    check('dsp_reference_3hz.json', 3, 3);
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('\n=== WN 3.1 / WN 3.2: zgodnosc z SciPy 1.16.3 ===\n$lines');
  });
}
