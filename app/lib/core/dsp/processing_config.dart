/// Odpowiada tabeli processing_configs w schemacie bazy. Wiersze sa niezmienne.
class ProcessingConfig {
  const ProcessingConfig({
    this.filterType = 'butterworth',
    this.filterOrder = 4,
    this.filterLowHz = 3.0,
    this.filterHighHz = 40.0,
    this.windowS = 2.0,
    this.stepSamples = 64,
    this.eps = 1e-6,
    this.p0 = 1.0,
    this.madScale = 1.4826,
    this.sMin = 0.05,
    this.mapA = -2.0,
    this.mapB = 2.0,
    this.smoothingLambda = 0.1,
    this.notchHz = 50.0,
    this.welchSegmentS = 1.0,
    this.welchOverlap = 0.5,
    this.alphaLowHz = 8.0,
    this.alphaHighHz = 12.0,
    this.ampThresholdUv = 100.0,
    this.hfRatioThreshold = 0.25,
    this.warmupSkipS = 5.0,
    this.calibMinValidRatio = 0.9,
    this.thresholdPercentile = 60.0,
    this.holdTimeS = 1.5,
  });

  final String filterType;
  final int filterOrder;
  final double filterLowHz;
  final double filterHighHz;
  final double windowS;
  final int stepSamples;
  final double eps;
  final double p0;
  final double madScale;
  final double sMin;
  final double mapA;
  final double mapB;
  final double smoothingLambda;
  final double? notchHz;
  final double welchSegmentS;
  final double welchOverlap;
  final double alphaLowHz;
  final double alphaHighHz;
  final double ampThresholdUv;

  /// Udzial mocy 30 do 40 Hz w mocy 1 do 40 Hz.
  final double hfRatioThreshold;
  final double warmupSkipS;
  final double calibMinValidRatio;
  final double thresholdPercentile;
  final double holdTimeS;
}
