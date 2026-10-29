import 'dart:math';
import 'dart:typed_data';

void fft(Float64List re, Float64List im) {
  final n = re.length;
  var j = 0;
  for (var i = 1; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * pi / len;
    final wr = cos(ang), wi = sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final a = i + k, b = i + k + len ~/ 2;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final t = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = t;
      }
    }
  }
}

/// Estymata Welcha: okno Hanna (periodyczne), odjecie sredniej segmentu,
/// uzupelnienie zerami do [nfft], skalowanie na gestosc mocy (jednostronna).
class Welch {
  Welch({
    required this.fs,
    required this.segment,
    required this.overlap,
    required this.nfft,
  })  : _window = Float64List.fromList([
          for (var i = 0; i < segment; i++)
            0.5 - 0.5 * cos(2 * pi * i / segment),
        ]) {
    if (nfft & (nfft - 1) != 0 || nfft < segment) {
      throw ArgumentError('nfft musi byc potega 2 i >= segment');
    }
    var s = 0.0;
    for (final w in _window) {
      s += w * w;
    }
    _scale = 1 / (fs * s);
  }

  final double fs;
  final int segment;
  final int overlap;
  final int nfft;
  final Float64List _window;
  late final double _scale;

  double get df => fs / nfft;

  Float64List psd(List<double> x) {
    final step = segment - overlap;
    final out = Float64List(nfft ~/ 2 + 1);
    var count = 0;
    for (var start = 0; start + segment <= x.length; start += step) {
      var mean = 0.0;
      for (var i = 0; i < segment; i++) {
        mean += x[start + i];
      }
      mean /= segment;
      final re = Float64List(nfft), im = Float64List(nfft);
      for (var i = 0; i < segment; i++) {
        re[i] = (x[start + i] - mean) * _window[i];
      }
      fft(re, im);
      for (var k = 0; k < out.length; k++) {
        var p = (re[k] * re[k] + im[k] * im[k]) * _scale;
        if (k != 0 && k != nfft ~/ 2) p *= 2;
        out[k] += p;
      }
      count++;
    }
    if (count == 0) throw StateError('Za malo probek na jeden segment');
    for (var k = 0; k < out.length; k++) {
      out[k] /= count;
    }
    return out;
  }

  /// Moc w pasmie [lowHz, highHz] jako suma PSD razy df.
  double bandPower(Float64List psd, double lowHz, double highHz) {
    var s = 0.0;
    for (var k = 0; k < psd.length; k++) {
      final f = k * df;
      if (f >= lowHz && f <= highHz) s += psd[k];
    }
    return s * df;
  }
}
