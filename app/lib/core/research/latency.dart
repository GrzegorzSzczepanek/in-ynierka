/// Percentyl z interpolacja liniowa; [values] w dowolnych jednostkach.
double percentileOf(List<num> values, double p) {
  if (values.isEmpty) return double.nan;
  final v = [for (final x in values) x.toDouble()]..sort();
  final pos = (v.length - 1) * p / 100;
  final lo = pos.floor(), hi = pos.ceil();
  return v[lo] + (v[hi] - v[lo]) * (pos - lo);
}

class StageStat {
  const StageStat(this.name, this.p50Ms, this.p95Ms, {this.n = 0});

  final String name;
  final double p50Ms;
  final double p95Ms;
  final int n;

  bool get hasData => !p50Ms.isNaN;
}

/// Statystyki opoznien potoku w milisekundach (mediana i p95 na etap).
/// Percentyle poszczegolnych etapow nie sumuja sie; "razem" liczone z sum
/// per okno.
class LatencyReport {
  const LatencyReport(this.stages, this.total, {required this.windows});

  final List<StageStat> stages;
  final StageStat total;
  final int windows;

  static LatencyReport from({
    required List<int> filterUs,
    required List<int> qualityUs,
    required List<int> welchUs,
    required List<int> smoothUs,
    List<int> receiveUs = const [],
    List<int> renderUs = const [],
    required double stepMs,
  }) {
    StageStat s(String name, List<int> us) =>
        StageStat(name, percentileOf(us, 50) / 1000, percentileOf(us, 95) / 1000, n: us.length);
    final n = filterUs.length;
    final totals = <int>[
      for (var i = 0; i < n; i++)
        filterUs[i] + qualityUs[i] + welchUs[i] + (i < smoothUs.length ? smoothUs[i] : 0),
    ];
    return LatencyReport([
      s('Odbiór → bufor', receiveUs),
      s('Filtracja', filterUs),
      StageStat('Okno analizy (krok)', stepMs, stepMs, n: n),
      s('Kontrola jakości', qualityUs),
      s('Welch PSD', welchUs),
      s('Wygładzanie EMA', smoothUs),
      s('Render (Flutter)', renderUs),
    ], s('Razem DSP', totals), windows: n);
  }
}
