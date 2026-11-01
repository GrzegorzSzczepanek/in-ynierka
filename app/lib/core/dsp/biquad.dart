import 'dart:math';

class Biquad {
  Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0, b1, b2, a1, a2;
  double _z1 = 0, _z2 = 0;

  double process(double x) {
    final y = b0 * x + _z1;
    _z1 = b1 * x - a1 * y + _z2;
    _z2 = b2 * x - a2 * y;
    return y;
  }

  void reset() {
    _z1 = 0;
    _z2 = 0;
  }

  factory Biquad.lowpass(double f, double fs, double q) {
    final w = 2 * pi * f / fs;
    final c = cos(w), al = sin(w) / (2 * q);
    final a0 = 1 + al;
    return Biquad(
      (1 - c) / 2 / a0,
      (1 - c) / a0,
      (1 - c) / 2 / a0,
      -2 * c / a0,
      (1 - al) / a0,
    );
  }

  factory Biquad.highpass(double f, double fs, double q) {
    final w = 2 * pi * f / fs;
    final c = cos(w), al = sin(w) / (2 * q);
    final a0 = 1 + al;
    return Biquad(
      (1 + c) / 2 / a0,
      -(1 + c) / a0,
      (1 + c) / 2 / a0,
      -2 * c / a0,
      (1 - al) / a0,
    );
  }

  /// Notch w parametryzacji SciPy (iirnotch): szerokosc pasma = f0 / q.
  factory Biquad.notch(double f, double fs, double q) {
    final w0 = pi * f / (fs / 2);
    final bw = w0 / q;
    final gain = 1 / (1 + tan(bw / 2));
    final c = cos(w0);
    return Biquad(gain, -2 * gain * c, gain, -2 * gain * c, 2 * gain - 1);
  }
}

class SosFilter {
  SosFilter(this.sections);

  final List<Biquad> sections;

  /// Przyczynowy pasmowy Butterworth: kaskada gornoprzepustowego i
  /// dolnoprzepustowego rzedu [order] (parzystego), opcjonalnie z notchem.
  factory SosFilter.bandpass({
    required double fs,
    required double lowHz,
    required double highHz,
    int order = 4,
    double? notchHz,
    double notchQ = 30,
  }) {
    if (order.isOdd) throw ArgumentError('Rzad filtra musi byc parzysty');
    final sections = <Biquad>[];
    for (var k = 1; k <= order ~/ 2; k++) {
      final q = 1 / (2 * cos(pi * (2 * k - 1) / (2 * order)));
      sections.add(Biquad.highpass(lowHz, fs, q));
    }
    for (var k = 1; k <= order ~/ 2; k++) {
      final q = 1 / (2 * cos(pi * (2 * k - 1) / (2 * order)));
      sections.add(Biquad.lowpass(highHz, fs, q));
    }
    if (notchHz != null) sections.add(Biquad.notch(notchHz, fs, notchQ));
    return SosFilter(sections);
  }

  double process(double x) {
    var y = x;
    for (final s in sections) {
      y = s.process(y);
    }
    return y;
  }

  void reset() {
    for (final s in sections) {
      s.reset();
    }
  }
}
