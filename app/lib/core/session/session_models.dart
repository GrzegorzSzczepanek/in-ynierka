import '../dsp/alpha_pipeline.dart';
import '../dsp/calibration.dart';
import '../dsp/processing_config.dart';
import 'training_protocol.dart';

enum SessionPhase {
  connecting,
  deviceSelection,
  contactCheck,
  calibrating,
  calibratingClosed,
  calibrationResult,
  training,
  breakBetweenBlocks,
  reconnecting,
  connectionLost,
  summary,
  completed,
  interrupted,
}

/// Odpowiada polu sessions.status ('completed', 'interrupted', 'connection_lost').
enum SessionStatus { completed, interrupted, connectionLost }

class SessionConfig {
  const SessionConfig({
    this.processing = const ProcessingConfig(),
    this.protocol = TrainingProtocol.relaks,
    List<String>? trainingChannels,
    this.calibrationS = 60,
    this.blocks = 3,
    this.blockS = 180,
    this.breakS = 30,
    this.contactSettleS = 5,
    this.contactStableS = 2,
    this.connectAttempts = 3,
    this.reconnectAttempts = 3,
    this.reconnectIntervalS = 15,
    this.calibrationClosedS = 30,
    this.calibrationResultS = 4,
    this.alphaReactivityMin = 1.2,
    this.maxClosedRepeats = 2,
    this.calibrationOnly = false,
  }) : _channels = trainingChannels;

  final ProcessingConfig processing;
  final TrainingProtocol protocol;
  final List<String>? _channels;

  /// Domyslnie kanaly protokolu.
  List<String> get trainingChannels => _channels ?? protocol.channels;

  /// Jawnie ustawione kanaly (null: kanaly protokolu).
  List<String>? get channelsOverride => _channels;
  final double calibrationS;
  final int blocks;
  final double blockS;
  final double breakS;

  /// Kontakt zgloszony w pierwszych sekundach strumienia nie jest wiarygodny.
  final double contactSettleS;
  final double contactStableS;
  final int connectAttempts;
  final int reconnectAttempts;
  final double reconnectIntervalS;

  /// Krok oczy zamkniete (reaktywnosc alfa), tylko dla treningu alfa.
  final double calibrationClosedS;
  final double calibrationResultS;

  /// Stosunek mocy alfa oczy zamkniete / otwarte, ponizej ktorego krok sie powtarza.
  final double alphaReactivityMin;
  final int maxClosedRepeats;

  /// Sesja konczy sie po kalibracji, bez blokow treningowych.
  final bool calibrationOnly;

  bool get closedStep =>
      protocol.kind == FeatureKind.alphaPower && calibrationClosedS > 0;

  double get stepS => processing.stepSamples / 250;

  /// Zaplanowany czas sesji bez ponownych polaczen.
  int get plannedDurationS =>
      (calibrationS + blocks * blockS + (blocks - 1) * breakS).round();
}

class InvalidInterval {
  const InvalidInterval(this.startMs, this.endMs, this.reason);

  final int startMs;
  final int endMs;
  final InvalidReason reason;
}

class BlockEvent {
  const BlockEvent(this.atMs, this.type);

  final int atMs;
  final String type;
}

class CalibrationRecord {
  const CalibrationRecord(
    this.attempt,
    this.durationS,
    this.result, {
    this.validSignalS = 0,
    this.alphaRatio,
    this.alphaPeakHz,
    this.reused = false,
  });

  CalibrationRecord withAlpha(double? ratio, double? peakHz) => CalibrationRecord(
        attempt,
        durationS,
        result,
        validSignalS: validSignalS,
        alphaRatio: ratio,
        alphaPeakHz: peakHz,
        reused: reused,
      );

  final int attempt;
  final double durationS;
  final CalibrationResult result;
  final double validSignalS;
  final double? alphaRatio;
  final double? alphaPeakHz;

  /// Baseline i prog wziete z poprzedniej kalibracji (pominieto kalibracje).
  final bool reused;

  String? get failureReason => result.accepted
      ? null
      : (result.baseline == null && result.validRatio == 0
          ? 'no_valid_windows'
          : 'valid_ratio_below_threshold');
}

class BlockResult {
  const BlockResult({
    required this.blockNo,
    required this.calibrationAttempt,
    required this.plannedS,
    required this.actualS,
    required this.threshold,
    required this.validSignalS,
    required this.timeAboveThresholdS,
    required this.rewardCount,
    required this.events,
    required this.invalid,
    this.meanY = 0.5,
    this.yTrace = const [],
    this.windowsTotal = 0,
    this.windowsInvalid = 0,
  });

  /// Srednia wygladzonego wyniku z waznych okien.
  final double meanY;

  /// Srednia wyniku w kolejnych 30 s bloku (tylko w pamieci, nie w bazie).
  final List<double> yTrace;
  final int windowsTotal;
  final int windowsInvalid;

  final int blockNo;

  /// Numer proby kalibracji, z ktorej pochodzi baseline i prog bloku.
  final int calibrationAttempt;
  final double plannedS;
  final double actualS;
  final double threshold;
  final double validSignalS;
  final double timeAboveThresholdS;
  final int rewardCount;
  final List<BlockEvent> events;
  final List<InvalidInterval> invalid;
}

/// Kalibracja z poprzedniej sesji, do ponownego uzycia (pominiecie kalibracji).
class StoredCalibration {
  const StoredCalibration({
    required this.baseline,
    required this.thresholdY,
    this.alphaRatio,
    this.alphaPeakHz,
    this.createdAt,
  });

  final Baseline baseline;
  final double thresholdY;
  final double? alphaRatio;
  final double? alphaPeakHz;
  final DateTime? createdAt;
}

class ChannelContact {
  const ChannelContact(this.name, this.contact);

  final String name;
  final bool contact;
}

class SessionSnapshot {
  const SessionSnapshot({
    required this.phase,
    required this.phaseElapsedS,
    this.phaseDurationS,
    this.blockNo = 0,
    this.blocksTotal = 0,
    this.feedback,
    this.threshold,
    this.rewardCount = 0,
    this.validSignalS = 0,
    this.attempt = 0,
    this.lastInvalid,
    this.contact,
    this.signalQuality,
    this.paused = false,
    this.alphaRatio,
    this.alphaPeakHz,
    this.canSkipCalibration = false,
    this.controlRating,
  });

  final SessionPhase phase;
  final double phaseElapsedS;
  final double? phaseDurationS;
  final int blockNo;
  final int blocksTotal;

  /// Tylko w treningu. Okno niewazne: [FeedbackSample.valid] = false.
  final FeedbackSample? feedback;
  final double? threshold;
  final int rewardCount;
  final double validSignalS;

  /// Numer proby kalibracji, laczenia lub ponownego laczenia.
  final int attempt;
  final InvalidReason? lastInvalid;

  /// Ostatni znany kontakt elektrod, gdy zrodlo go podaje.
  final List<ChannelContact>? contact;

  /// Udzial waznych okien w ostatnich ok. 5 s (0..1), po pierwszych oknach.
  final double? signalQuality;
  final bool paused;
  final double? alphaRatio;
  final double? alphaPeakHz;
  final bool canSkipCalibration;

  /// Ocena poczucia kontroli (1..5) ostatniego bloku, jesli podana.
  final int? controlRating;
}

class SessionResult {
  const SessionResult({
    required this.status,
    required this.calibrations,
    required this.blocks,
    this.controlRatings = const {},
  });

  /// Numer bloku -> ocena poczucia kontroli 1..5.
  final Map<int, int> controlRatings;

  final SessionStatus status;
  final List<CalibrationRecord> calibrations;
  final List<BlockResult> blocks;

  double get validSignalS => blocks.fold(0.0, (a, b) => a + b.validSignalS);

  /// Postep naliczamy, gdy ukonczono co najmniej jeden blok.
  bool get countsForProgress => blocks.isNotEmpty;
}
