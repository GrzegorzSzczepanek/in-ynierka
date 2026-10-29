import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/dsp/biquad.dart';
import 'package:neurotchi/core/dsp/welch.dart';

void main() {
  final ref = jsonDecode(File('test/fixtures/dsp_reference.json').readAsStringSync())
      as Map<String, dynamic>;
  List<double> list(String k) => [for (final v in ref[k] as List) (v as num).toDouble()];
  final x = list('x');
  final expected = list('filtered');

  test('filtr zgodny z SciPy (sosfilt)', () {
    final f = SosFilter.bandpass(
        fs: 250, lowHz: 1, highHz: 40, order: 4, notchHz: 50);
    var worst = 0.0;
    for (var i = 0; i < x.length; i++) {
      final d = (f.process(x[i]) - expected[i]).abs();
      if (d > worst) worst = d;
    }
    expect(worst, lessThan(1e-6));
  });

  test('Welch i moc w pasmach zgodne z SciPy', () {
    final w = Welch(fs: 250, segment: 250, overlap: 125, nfft: 512);
    final psd = w.psd(expected.sublist(expected.length - 500));
    final refPsd = list('psd');
    for (var k = 0; k < psd.length; k++) {
      expect(psd[k], closeTo(refPsd[k], 1e-9 + refPsd[k].abs() * 1e-9));
    }
    expect(w.bandPower(psd, 8, 12), closeTo(ref['alpha_power'] as double, 1e-9));
    expect(w.bandPower(psd, 30, 40), closeTo(ref['hf_power'] as double, 1e-9));
    expect(w.bandPower(psd, 1, 40), closeTo(ref['total_power'] as double, 1e-9));
  });
}
