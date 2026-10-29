import '../dsp/alpha_pipeline.dart';
import '../dsp/calibration.dart';
import '../dsp/processing_config.dart';
import 'training_protocol.dart';

enum SessionPhase {
  connecting,
  deviceSelection,
  contactCheck,
  calibrating,
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
  });

  final int attempt;
  final double durationS;
  final CalibrationResult result;
  final double validSignalS;

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
  });

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
}

class SessionResult {
  const SessionResult({
    required this.status,
    required this.calibrations,
    required this.blocks,
  });

  final SessionStatus status;
  final List<CalibrationRecord> calibrations;
  final List<BlockResult> blocks;

  double get validSignalS => blocks.fold(0.0, (a, b) => a + b.validSignalS);

  /// Postep naliczamy, gdy ukonczono co najmniej jeden blok.
  bool get countsForProgress => blocks.isNotEmpty;
}
