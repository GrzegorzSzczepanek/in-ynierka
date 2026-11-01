import 'alpha_pipeline.dart';
import 'processing_config.dart';

double median(List<double> v) => percentile(v, 50);

/// Percentyl z interpolacja liniowa (jak numpy.percentile).
double percentile(List<double> values, double p) {
  final v = [...values]..sort();
  if (v.isEmpty) throw StateError('Pusta lista');
  final pos = (v.length - 1) * p / 100;
  final lo = pos.floor(), hi = pos.ceil();
  return v[lo] + (v[hi] - v[lo]) * (pos - lo);
}

class Baseline {
  const Baseline(this.median, this.scale);

  final double median;
  final double scale;
}

class FeedbackSample {
  const FeedbackSample({required this.valid, required this.y, this.z, this.u});

  final bool valid;
  final double y;
  final double? z;
  final double? u;
}

/// z, u, y: standaryzacja wzgledem kalibracji, przeskalowanie na [0, 1]
/// i wygladzanie wykladnicze. Okno niewazne resetuje y do wartosci neutralnej.
class FeedbackMapper {
  FeedbackMapper(this.config, this.baseline);

  static const neutral = 0.5;

  final ProcessingConfig config;
  final Baseline baseline;
  double _y = neutral;

  FeedbackSample push(WindowResult w) {
    if (!w.valid) {
      _y = neutral;
      return FeedbackSample(valid: false, y: _y);
    }
    final z = (w.feature! - baseline.median) / baseline.scale;
    final u = ((z - config.mapA) / (config.mapB - config.mapA)).clamp(0.0, 1.0);
    _y = config.smoothingLambda * u + (1 - config.smoothingLambda) * _y;
    return FeedbackSample(valid: true, y: _y, z: z, u: u);
  }
}

class CalibrationResult {
  const CalibrationResult({
    required this.accepted,
    required this.validRatio,
    this.baseline,
    this.thresholdY,
  });

  final bool accepted;
  final double validRatio;
  final Baseline? baseline;
  final double? thresholdY;
}

/// Dwa przebiegi na tych samych oknach: (1) mediana i MAD cechy,
/// (2) rozklad y z tymi parametrami, z ktorego bierzemy percentyl progu.
CalibrationResult calibrate(List<WindowResult> windows, ProcessingConfig cfg) {
  final used = [
    for (final w in windows)
      if (w.tSec - cfg.windowS >= cfg.warmupSkipS) w,
  ];
  if (used.isEmpty)
    return const CalibrationResult(accepted: false, validRatio: 0);
  final xs = [
    for (final w in used)
      if (w.valid) w.feature!,
  ];
  final ratio = xs.length / used.length;
  if (xs.isEmpty || ratio < cfg.calibMinValidRatio) {
    return CalibrationResult(accepted: false, validRatio: ratio);
  }
  final m = median(xs);
  final mad = median([for (final x in xs) (x - m).abs()]) * cfg.madScale;
  final baseline = Baseline(m, mad < cfg.sMin ? cfg.sMin : mad);
  final mapper = FeedbackMapper(cfg, baseline);
  final ys = <double>[];
  for (final w in used) {
    final s = mapper.push(w);
    if (s.valid) ys.add(s.y);
  }
  return CalibrationResult(
    accepted: true,
    validRatio: ratio,
    baseline: baseline,
    thresholdY: percentile(ys, cfg.thresholdPercentile),
  );
}

/// Nagroda po utrzymaniu y powyzej progu przez holdTimeS. Po nagrodzie
/// kolejne odliczanie startuje dopiero gdy y spadnie pod prog (histereza).
/// Okno niewazne przerywa odliczanie.
class RewardDetector {
  RewardDetector({
    required this.threshold,
    required this.holdS,
    required this.stepS,
  });

  final double threshold;
  final double holdS;
  final double stepS;
  double _held = 0;
  bool _armed = true;

  bool push(FeedbackSample s) {
    if (!s.valid || s.y <= threshold) {
      _held = 0;
      if (s.valid) _armed = true;
      return false;
    }
    if (!_armed) return false;
    _held += stepS;
    if (_held >= holdS) {
      _held = 0;
      _armed = false;
      return true;
    }
    return false;
  }
}
