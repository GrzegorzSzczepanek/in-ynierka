import 'dart:async';
import 'dart:typed_data';

import '../dsp/alpha_pipeline.dart';
import '../dsp/biquad.dart';
import '../dsp/calibration.dart';
import '../dsp/processing_config.dart';
import '../eeg/eeg_source.dart';
import '../eeg/mock_source.dart';
import '../eeg/stream_item.dart';
import '../session/session_controller.dart';
import '../session/training_protocol.dart';
import 'latency.dart';

/// Podglad na zywo dla badacza: przefiltrowany sygnal kilku kanalow (okno 10 s),
/// os czasu waznych okien i pomiar czasu etapow potoku.
class ResearchMonitor {
  ResearchMonitor(
    this.sourceFactory, {
    this.config = const ProcessingConfig(),
    this.protocol = TrainingProtocol.alfa,
    this.maxChannels = 8,
    this.seconds = 10,
  });

  final SourceFactory sourceFactory;
  final ProcessingConfig config;
  final TrainingProtocol protocol;
  final int maxChannels;
  final int seconds;

  final _updates = StreamController<void>.broadcast();
  Stream<void> get updates => _updates.stream;

  EegSource? _source;
  bool _stopped = false;
  int _fs = 250;
  List<String> names = const [];
  List<int> _idx = const [];
  List<SosFilter> _filters = const [];
  List<Float64List> _ring = const [];
  int _written = 0;
  late AlphaPipeline _pipeline;
  final timings = PipelineTimings();
  final _smoothUs = <int>[];
  final _receiveUs = <int>[];
  final _renderUs = <int>[];
  FeedbackMapper? _mapper;
  final _validSeconds = <bool>[];
  var _secOk = true;
  int _secSamples = 0;
  final _clock = Stopwatch();
  String sourceLabel = '';

  int get fs => _fs;
  Duration get elapsed => _clock.elapsed;

  /// Ostatnie [seconds] s wybranych kanalow (kolejnosc czasowa, uV).
  List<Float64List> get traces => [
    for (final r in _ring)
      Float64List.fromList([
        for (var i = 0; i < r.length; i++) r[(_written + i) % r.length],
      ]),
  ];

  /// Os czasu waznych okien po 1 s (najstarsze pierwsze).
  List<bool> get validSeconds => List.unmodifiable(_validSeconds);

  LatencyReport get report => LatencyReport.from(
    filterUs: timings.filterUs,
    qualityUs: timings.qualityUs,
    welchUs: timings.welchUs,
    smoothUs: _smoothUs,
    receiveUs: _receiveUs,
    renderUs: _renderUs,
    stepMs: config.stepSamples / _fs * 1000,
  );

  void recordRender(int us) {
    _renderUs.add(us);
    if (_renderUs.length > 600) _renderUs.removeAt(0);
  }

  Future<void> start() async {
    final src = _source = sourceFactory();
    await src.start();
    _clock.start();
    await for (final item in src.items) {
      if (_stopped) break;
      switch (item) {
        case SegmentStart():
          _begin(item);
        case EegPacket():
          _packet(item);
        case GapEvent():
          _pipeline.push(item);
        case DisconnectedEvent():
          _stopped = true;
      }
    }
    _clock.stop();
    _notify();
  }

  void _begin(SegmentStart s) {
    _fs = s.info.fs;
    final all = [for (final c in s.info.channels) c.name];
    final train = protocol.channels.where(all.contains).toList();
    names = [
      ...train,
      ...all.where((n) => !train.contains(n)),
    ].take(maxChannels).toList();
    _idx = [for (final n in names) s.info.channelIndex(n)];
    _filters = [
      for (final _ in names)
        SosFilter.bandpass(
          fs: _fs.toDouble(),
          lowHz: config.filterLowHz,
          highHz: config.filterHighHz,
          order: config.filterOrder,
          notchHz: config.notchHz,
        ),
    ];
    _ring = [for (final _ in names) Float64List(seconds * _fs)];
    _written = 0;
    timings.clear();
    final trainUsed = protocol.channels.where(all.contains).toList();
    _pipeline = AlphaPipeline(
      config,
      trainingChannels: trainUsed.isEmpty ? [all.first] : trainUsed,
      kind: protocol.kind,
      timings: timings,
    );
    _pipeline.push(s);
    _mapper = null;
  }

  void _packet(EegPacket p) {
    final t0 = Stopwatch()..start();
    // Opoznienie odbioru: tylko dla czasu epoch (zrodlo urzadzenia).
    if (p.tRecv > 1e9) {
      final now = DateTime.now().microsecondsSinceEpoch / 1e6;
      _receiveUs.add(((now - p.tRecv) * 1e6).round().clamp(0, 5000000));
      if (_receiveUs.length > 600) _receiveUs.removeAt(0);
    }
    for (var i = 0; i < p.length; i++) {
      for (var c = 0; c < _idx.length; c++) {
        _ring[c][_written % _ring[c].length] = _filters[c].process(
          p.samples[_idx[c]][i],
        );
      }
      _written++;
    }
    for (final w in _pipeline.push(p)) {
      final sw = Stopwatch()..start();
      if (w.valid) {
        _mapper ??= FeedbackMapper(config, Baseline(w.feature!, 1));
        _mapper!.push(w);
      }
      _smoothUs.add(sw.elapsedMicroseconds);
      if (_smoothUs.length > 600) _smoothUs.removeAt(0);
      _secOk = _secOk && w.valid;
    }
    _secSamples += p.length;
    while (_secSamples >= _fs) {
      _secSamples -= _fs;
      _validSeconds.add(_secOk);
      if (_validSeconds.length > 120) _validSeconds.removeAt(0);
      _secOk = true;
    }
    _trim();
    _notify();
    t0.stop();
  }

  void _notify() {
    if (!_updates.isClosed) _updates.add(null);
  }

  void _trim() {
    for (final l in [
      timings.filterUs,
      timings.qualityUs,
      timings.welchUs,
      timings.totalUs,
    ]) {
      if (l.length > 600) l.removeRange(0, l.length - 600);
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _clock.stop();
    await _source?.stop();
    await _updates.close();
  }

  /// Test opoznien: przepuszcza [seconds] s syntetycznego sygnalu przez potok
  /// tak szybko, jak sie da, i podaje czasy etapow DSP.
  static Future<LatencyReport> runTest({
    ProcessingConfig config = const ProcessingConfig(),
    TrainingProtocol protocol = TrainingProtocol.alfa,
    int seconds = 60,
  }) async {
    final src = MockSource(
      channels: [for (final n in protocol.channels) Channel(n)],
      duration: Duration(seconds: seconds),
      alphaAmplitudeUv: (_) => 15,
      betaAmplitudeUv: (_) => 5,
    );
    final timings = PipelineTimings();
    final pipe = AlphaPipeline(
      config,
      trainingChannels: protocol.channels,
      kind: protocol.kind,
      timings: timings,
    );
    final smooth = <int>[];
    FeedbackMapper? mapper;
    final done = src.items.forEach((i) {
      for (final w in pipe.push(i)) {
        final sw = Stopwatch()..start();
        if (w.valid) {
          mapper ??= FeedbackMapper(config, Baseline(w.feature!, 1));
          mapper!.push(w);
        }
        smooth.add(sw.elapsedMicroseconds);
      }
    });
    await src.start();
    await done;
    return LatencyReport.from(
      filterUs: timings.filterUs,
      qualityUs: timings.qualityUs,
      welchUs: timings.welchUs,
      smoothUs: smooth,
      stepMs: config.stepSamples / 250 * 1000,
    );
  }
}
