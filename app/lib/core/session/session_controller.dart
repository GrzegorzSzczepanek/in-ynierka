import 'dart:async';
import 'dart:math' as math;

import '../dsp/alpha_pipeline.dart';
import '../dsp/calibration.dart';
import '../eeg/eeg_source.dart';
import '../eeg/stream_item.dart';
import 'session_models.dart';

typedef SourceFactory = EegSource Function();

enum _End { completed, disconnected, finished }

/// Sesja treningowa wg diagramow stanow: laczenie, kontrola kontaktu,
/// kalibracja, bloki z przerwami, ponowne laczenie. Czas biegnie z numerow
/// probek, wiec Mock i Replay moga dzialac szybciej niz w czasie rzeczywistym.
class SessionController {
  SessionController({
    required this.sourceFactory,
    this.config = const SessionConfig(),
    this.onItem,
    this.stored,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? ((d) => Future<void>.delayed(d)) {
    _pipeline = AlphaPipeline(
      config.processing,
      trainingChannels: config.trainingChannels,
      kind: config.protocol.kind,
    );
  }

  final SourceFactory sourceFactory;
  final SessionConfig config;

  /// Kalibracja z poprzedniej sesji; umozliwia [skipCalibration].
  final StoredCalibration? stored;

  /// Kazdy element strumienia, np. do zapisu surowego EEG.
  final void Function(StreamItem)? onItem;
  final Future<void> Function(Duration) _delay;
  late final AlphaPipeline _pipeline;

  final _snapshots = StreamController<SessionSnapshot>.broadcast();
  Stream<SessionSnapshot> get snapshots => _snapshots.stream;
  SessionSnapshot? _last;
  SessionSnapshot? get current => _last;

  SessionPhase _phase = SessionPhase.connecting;
  SessionPhase get phase => _phase;
  EegSource? _source;
  Completer<void>? _retry;
  bool _finished = false;
  bool _finishedWhileLost = false;
  bool _done = false;

  int _attempt = 0;
  int _fs = 250;
  List<int> _trainIdx = const [];
  List<String> _channelNames = const [];
  List<bool>? _contactNow;
  final _recentValid = <bool>[];
  int _segSamples = 0;
  double _tOffset = 0;
  double _nowT = 0;
  double _phaseStart = 0;
  int _okRun = 0;

  final _calibrations = <CalibrationRecord>[];
  final _blocks = <BlockResult>[];
  List<WindowResult> _calibWindows = [];
  int _calibAttempt = 0;
  Baseline? _baseline;
  double? _threshold;

  var _closedFeatures = <double>[];
  var _closedPeaks = <double>[];
  int _closedRepeats = 0;
  String? _connectError;
  double? _alphaRatio;
  double? _alphaPeakHz;

  bool _paused = false;
  double _pauseStartT = 0;
  final _controlRatings = <int, int>{};
  var _trace = <double>[];
  double _binSum = 0;
  int _binN = 0;
  double _ySum = 0;
  int _yN = 0;
  int _winTotal = 0;
  int _winInvalid = 0;

  int _blockNo = 0;
  double _blockStart = 0;
  FeedbackMapper? _mapper;
  RewardDetector? _detector;
  FeedbackSample? _feedback;
  double _validS = 0;
  double _aboveS = 0;
  int _rewards = 0;
  var _events = <BlockEvent>[];
  var _invalid = <InvalidInterval>[];
  int? _invStartMs;
  InvalidReason? _invReason;
  InvalidReason? _lastInvalid;

  /// Konczy sesje na zadanie uzytkownika. Niepelny blok sie nie liczy.
  void finish() {
    if (_finished) return;
    _finished = true;
    _finishedWhileLost = _phase == SessionPhase.connectionLost;
    _retry?.complete();
    unawaited(_source?.stop());
  }

  /// Ponawia laczenie po [SessionPhase.connectionLost].
  void retry() => _retry?.complete();

  bool get canSkipCalibration =>
      stored != null &&
      (_phase == SessionPhase.calibrating ||
          _phase == SessionPhase.calibratingClosed ||
          _phase == SessionPhase.calibrationResult);

  /// Pomija kalibracje: baseline i prog z poprzedniej kalibracji.
  void skipCalibration() {
    final s = stored;
    if (s == null || !canSkipCalibration) return;
    _calibAttempt++;
    _calibrations.add(
      CalibrationRecord(
        _calibAttempt,
        0,
        CalibrationResult(
          accepted: true,
          validRatio: 1,
          baseline: s.baseline,
          thresholdY: s.thresholdY,
        ),
        alphaRatio: s.alphaRatio,
        alphaPeakHz: s.alphaPeakHz,
        reused: true,
      ),
    );
    _baseline = s.baseline;
    _threshold = s.thresholdY;
    _alphaRatio = s.alphaRatio;
    _alphaPeakHz = s.alphaPeakHz;
    _blockNo = 0;
    _afterCalibration(_nowT);
  }

  /// Wstrzymuje trening: czas bloku, wynik i nagrody stoja, strumien plynie dalej.
  void pause() {
    if (_phase != SessionPhase.training || _paused) return;
    _paused = true;
    _pauseStartT = _nowT;
    _emit();
  }

  void resume() {
    if (!_paused) return;
    final gap = _nowT - _pauseStartT;
    _blockStart += gap;
    _phaseStart += gap;
    _mapper = FeedbackMapper(config.processing, _baseline!);
    _detector = RewardDetector(
      threshold: _threshold!,
      holdS: config.processing.holdTimeS,
      stepS: config.stepS,
    );
    _feedback = null;
    _paused = false;
    _emit();
  }

  /// Ocena poczucia kontroli 1..5 dla ukonczonego bloku.
  void rateBlock(int blockNo, int rating) {
    if (rating < 1 || rating > 5) return;
    _controlRatings[blockNo] = rating;
    _emit();
  }

  Future<SessionResult> run() async {
    _setPhase(SessionPhase.connecting);
    final first = await _connect(config.connectAttempts, 0);
    if (first == null) {
      return _end(
        _finished ? SessionStatus.interrupted : SessionStatus.connectionLost,
        _finished ? SessionPhase.interrupted : SessionPhase.deviceSelection,
      );
    }
    var it = first;
    _setPhase(SessionPhase.contactCheck);
    while (true) {
      final end = await _consume(it);
      if (end == _End.completed) {
        _setPhase(SessionPhase.summary);
        return _end(SessionStatus.completed, SessionPhase.completed);
      }
      if (end == _End.finished) {
        return _end(
          _finishedWhileLost
              ? SessionStatus.connectionLost
              : SessionStatus.interrupted,
          SessionPhase.interrupted,
        );
      }
      _tOffset = _nowT;
      final next = await _reconnect();
      if (next == null) {
        return _end(
          _finishedWhileLost
              ? SessionStatus.connectionLost
              : SessionStatus.interrupted,
          SessionPhase.interrupted,
        );
      }
      it = next;
      _startCalibration();
    }
  }

  Future<SessionResult> _end(SessionStatus status, SessionPhase phase) async {
    _setPhase(phase);
    await _snapshots.close();
    return SessionResult(
      status: status,
      calibrations: List.unmodifiable(_calibrations),
      blocks: List.unmodifiable(_blocks),
      controlRatings: Map.of(_controlRatings),
    );
  }

  Future<StreamIterator<StreamItem>?> _connect(
    int attempts,
    double waitS,
  ) async {
    for (var a = 1; a <= attempts && !_finished; a++) {
      _attempt = a;
      _emit();
      if (waitS > 0)
        await _delay(Duration(milliseconds: (waitS * 1000).round()));
      if (_finished) return null;
      final src = _source = sourceFactory();
      await src.start();
      final it = StreamIterator(src.items);
      if (await it.moveNext() && it.current is SegmentStart) {
        _connectError = null;
        onItem?.call(it.current);
        _segmentStart(it.current as SegmentStart);
        return it;
      }
      final failed = it.current;
      if (failed is DisconnectedEvent) _connectError = failed.reason;
      await it.cancel();
    }
    return null;
  }

  Future<StreamIterator<StreamItem>?> _reconnect() async {
    while (!_finished) {
      _setPhase(SessionPhase.reconnecting);
      final it = await _connect(
        config.reconnectAttempts,
        config.reconnectIntervalS,
      );
      if (it != null) return it;
      if (_finished) return null;
      _setPhase(SessionPhase.connectionLost);
      _retry = Completer<void>();
      await _retry!.future;
    }
    return null;
  }

  void _segmentStart(SegmentStart s) {
    _fs = s.info.fs;
    _trainIdx = [
      for (final n in config.trainingChannels) s.info.channelIndex(n),
    ];
    _channelNames = [for (final c in s.info.channels) c.name];
    _recentValid.clear();
    _segSamples = 0;
    _okRun = 0;
    _pipeline.push(s);
  }

  Future<_End> _consume(StreamIterator<StreamItem> it) async {
    while (await it.moveNext()) {
      final item = it.current;
      onItem?.call(item);
      switch (item) {
        case DisconnectedEvent():
          await it.cancel();
          return _finished ? _End.finished : _End.disconnected;
        case EegPacket():
          _onPacket(item);
        case GapEvent():
          _pipeline.push(item);
        case SegmentStart():
          _pipeline.push(item);
      }
      if (_done) {
        await _source?.stop();
        await it.cancel();
        return _End.completed;
      }
    }
    return _finished ? _End.finished : _End.disconnected;
  }

  void _onPacket(EegPacket p) {
    _segSamples += p.length;
    _nowT = _tOffset + _segSamples / _fs;
    final ct = p.contact;
    _contactNow = ct == null
        ? null
        : [for (final ch in ct) ch.isNotEmpty && ch.last];
    if (_phase == SessionPhase.contactCheck) _checkContact(p);
    for (final w in _pipeline.push(p)) {
      _onWindow(w);
    }
    _emit();
  }

  void _checkContact(EegPacket p) {
    if (_segSamples < config.contactSettleS * _fs) return;
    final c = p.contact;
    for (var i = 0; i < p.length; i++) {
      final ok = c == null || _trainIdx.every((ch) => c[ch][i]);
      _okRun = ok ? _okRun + 1 : 0;
    }
    if (_okRun >= config.contactStableS * _fs) _startCalibration();
  }

  void _startCalibration() {
    _calibWindows = [];
    _calibAttempt++;
    _closedRepeats = 0;
    _alphaRatio = null;
    _alphaPeakHz = null;
    _blockNo = 0;
    _setPhase(SessionPhase.calibrating);
  }

  void _onWindow(WindowResult w) {
    final t = _tOffset + w.tSec;
    if (!w.valid) _lastInvalid = w.reason;
    _recentValid.add(w.valid);
    if (_recentValid.length > 20) _recentValid.removeAt(0);
    switch (_phase) {
      case SessionPhase.calibrating:
        _calibWindows.add(
          WindowResult(
            sampleEnd: w.sampleEnd,
            tSec: t - _phaseStart,
            valid: w.valid,
            reason: w.reason,
            feature: w.feature,
            peakHz: w.peakHz,
          ),
        );
        final elapsed = t - _phaseStart;
        final enough = _calibValidS >= _calibNeededS;
        if ((elapsed >= config.calibrationS && enough) ||
            elapsed >= config.calibrationMaxS) {
          _finishCalibration(t);
        }
      case SessionPhase.calibratingClosed:
        if (w.valid && w.feature != null) {
          _closedFeatures.add(w.feature!);
          if (w.peakHz != null) _closedPeaks.add(w.peakHz!);
        }
        if (t - _phaseStart >= config.calibrationClosedS) _finishClosed(t);
      case SessionPhase.calibrationResult:
        if (t - _phaseStart >= config.calibrationResultS) _afterCalibration(t);
      case SessionPhase.training:
        _trainingWindow(w, t);
      case SessionPhase.breakBetweenBlocks:
        if (t - _phaseStart >= config.breakS) _startBlock(t);
      default:
        break;
    }
  }

  /// Wymagany czas wiarygodnego sygnalu: ulamek czasu kroku po odjeciu rozgrzewki.
  double get _calibNeededS {
    final cfg = config.processing;
    return cfg.calibMinValidRatio *
        (config.calibrationS - cfg.windowS - cfg.warmupSkipS);
  }

  /// Czas wiarygodnego sygnalu zebrany w kroku kalibracji (bez rozgrzewki).
  double get _calibValidS {
    final cfg = config.processing;
    final n = _calibWindows
        .where((w) => w.valid && w.tSec - cfg.windowS >= cfg.warmupSkipS)
        .length;
    return n * config.stepS;
  }

  void _finishCalibration(double t) {
    final enough = _calibValidS >= _calibNeededS;
    final windows = enough
        ? [
            for (final w in _calibWindows)
              if (w.valid) w,
          ]
        : _calibWindows;
    final result = calibrate(windows, config.processing);
    _calibrations.add(
      CalibrationRecord(
        _calibAttempt,
        config.calibrationS,
        result,
        validSignalS: _calibWindows.where((w) => w.valid).length * config.stepS,
      ),
    );
    if (!result.accepted) {
      _startCalibration();
      return;
    }
    _baseline = result.baseline;
    _threshold = result.thresholdY;
    _blockNo = 0;
    if (config.closedStep) {
      _startClosed(t);
    } else {
      _afterCalibration(t);
    }
  }

  void _afterCalibration(double t) {
    if (config.calibrationOnly) {
      _done = true;
    } else {
      _startBlock(t);
    }
  }

  void _startClosed(double t) {
    _closedFeatures = [];
    _closedPeaks = [];
    _setPhase(SessionPhase.calibratingClosed, at: t);
  }

  void _finishClosed(double t) {
    double? ratio;
    double? peak;
    if (_closedFeatures.isNotEmpty) {
      ratio = math.exp(median(_closedFeatures) - _baseline!.median);
      if (_closedPeaks.isNotEmpty) peak = median(_closedPeaks);
    }
    _alphaRatio = ratio;
    _alphaPeakHz = peak;
    final last = _calibrations.length - 1;
    _calibrations[last] = _calibrations[last].withAlpha(ratio, peak);
    if (ratio != null &&
        ratio < config.alphaReactivityMin &&
        _closedRepeats < config.maxClosedRepeats) {
      _closedRepeats++;
      _startClosed(t);
    } else {
      _setPhase(SessionPhase.calibrationResult, at: t);
    }
  }

  void _startBlock(double t) {
    _blockNo++;
    _blockStart = t;
    _mapper = FeedbackMapper(config.processing, _baseline!);
    _detector = RewardDetector(
      threshold: _threshold!,
      holdS: config.processing.holdTimeS,
      stepS: config.stepS,
    );
    _feedback = null;
    _validS = 0;
    _aboveS = 0;
    _rewards = 0;
    _events = [];
    _invalid = [];
    _invStartMs = null;
    _invReason = null;
    _paused = false;
    _trace = [];
    _binSum = 0;
    _binN = 0;
    _ySum = 0;
    _yN = 0;
    _winTotal = 0;
    _winInvalid = 0;
    _setPhase(SessionPhase.training, at: t);
  }

  void _trainingWindow(WindowResult w, double t) {
    if (_paused) return;
    final s = _feedback = _mapper!.push(w);
    _winTotal++;
    if (!w.valid) _winInvalid++;
    if (w.valid) {
      _ySum += s.y;
      _yN++;
      _binSum += s.y;
      _binN++;
    }
    while (t - _blockStart >= (_trace.length + 1) * 30) {
      _trace.add(_binN > 0 ? _binSum / _binN : 0.5);
      _binSum = 0;
      _binN = 0;
    }
    final ms = ((t - _blockStart) * 1000).round();
    if (w.valid) {
      _closeInvalid(ms);
      _validS += config.stepS;
      if (s.y > _threshold!) _aboveS += config.stepS;
    } else if (_invReason != w.reason) {
      _closeInvalid(ms);
      _invStartMs = ms;
      _invReason = w.reason;
    }
    if (_detector!.push(s)) {
      _rewards++;
      _events.add(BlockEvent(ms, 'reward'));
    }
    if (t - _blockStart >= config.blockS) _endBlock(t);
  }

  void _closeInvalid(int ms) {
    if (_invReason != null) {
      _invalid.add(InvalidInterval(_invStartMs!, ms, _invReason!));
      _invReason = null;
      _invStartMs = null;
    }
  }

  void _endBlock(double t) {
    _closeInvalid(((t - _blockStart) * 1000).round());
    _blocks.add(
      BlockResult(
        blockNo: _blockNo,
        calibrationAttempt: _calibAttempt,
        plannedS: config.blockS,
        actualS: t - _blockStart,
        threshold: _threshold!,
        validSignalS: _validS,
        timeAboveThresholdS: _aboveS,
        rewardCount: _rewards,
        events: _events,
        invalid: _invalid,
        meanY: _yN > 0 ? _ySum / _yN : 0.5,
        yTrace: [..._trace, if (_binN > 0) _binSum / _binN],
        windowsTotal: _winTotal,
        windowsInvalid: _winInvalid,
      ),
    );
    if (_blockNo >= config.blocks) {
      _done = true;
    } else {
      _feedback = null;
      _setPhase(SessionPhase.breakBetweenBlocks, at: t);
    }
  }

  void _setPhase(SessionPhase p, {double? at}) {
    _phase = p;
    _phaseStart = at ?? _nowT;
    _emit();
  }

  /// Postep kroku; w kalibracji liczy sie tylko wiarygodny sygnal, wiec
  /// pasek zwalnia, gdy sygnal jest zly.
  double get _phaseProgressS {
    final elapsed = ((_paused ? _pauseStartT : _nowT) - _phaseStart)
        .clamp(0, double.infinity)
        .toDouble();
    if (_phase != SessionPhase.calibrating) return elapsed;
    final scaled = _calibValidS / _calibNeededS * config.calibrationS;
    return elapsed < scaled ? elapsed : scaled;
  }

  void _emit() {
    if (_snapshots.isClosed) return;
    final duration = switch (_phase) {
      SessionPhase.calibrating => config.calibrationS,
      SessionPhase.calibratingClosed => config.calibrationClosedS,
      SessionPhase.calibrationResult => config.calibrationResultS,
      SessionPhase.training => config.blockS,
      SessionPhase.breakBetweenBlocks => config.breakS,
      _ => null,
    };
    _last = SessionSnapshot(
      phase: _phase,
      phaseElapsedS: _phaseProgressS,
      phaseDurationS: duration,
      blockNo: _blockNo,
      blocksTotal: config.blocks,
      feedback: _phase == SessionPhase.training ? _feedback : null,
      threshold: _threshold,
      rewardCount: _rewards,
      validSignalS: _validS,
      attempt: switch (_phase) {
        SessionPhase.calibrating => _calibAttempt,
        _ => _attempt,
      },
      lastInvalid: _lastInvalid,
      contact: _contactNow == null
          ? null
          : [
              for (var i = 0; i < _contactNow!.length; i++)
                ChannelContact(_channelNames[i], _contactNow![i]),
            ],
      signalQuality: _recentValid.isEmpty
          ? null
          : _recentValid.where((v) => v).length / _recentValid.length,
      paused: _paused,
      alphaRatio: _alphaRatio,
      alphaPeakHz: _alphaPeakHz,
      canSkipCalibration: canSkipCalibration,
      error: _connectError,
      controlRating: _controlRatings[_blockNo],
    );
    _snapshots.add(_last!);
  }
}
