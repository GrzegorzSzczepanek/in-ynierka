import 'dart:math';
import 'dart:typed_data';

import '../eeg/stream_item.dart';
import '../session/training_protocol.dart';
import 'biquad.dart';
import 'processing_config.dart';
import 'welch.dart';

/// Czasy etapow potoku w mikrosekundach (opcjonalne, do trybu badacza).
class PipelineTimings {
  final filterUs = <int>[];
  final qualityUs = <int>[];
  final welchUs = <int>[];
  final totalUs = <int>[];

  void clear() {
    filterUs.clear();
    qualityUs.clear();
    welchUs.clear();
    totalUs.clear();
  }
}

enum InvalidReason { gap, saturation, flat, amplitude, jump, muscle }

class WindowResult {
  const WindowResult({
    required this.sampleEnd,
    required this.tSec,
    required this.valid,
    this.reason,
    this.feature,
    this.peakHz,
  });

  final int sampleEnd;
  final double tSec;
  final bool valid;
  final InvalidReason? reason;

  /// x(t): srednia po kanalach z ln((P_alfa + eps) / P0). Tylko dla okien waznych.
  final double? feature;

  /// Czestotliwosc piku widma w 7 do 13 Hz (tylko dla cechy alfa, okna wazne).
  final double? peakHz;
}

/// Potok: filtr przyczynowy, okno przesuwne, kontrola jakosci, moc alfa.
/// Kontrola jakosci zapada przed obliczeniem cechy.
class AlphaPipeline {
  AlphaPipeline(
    this.config, {
    required this.trainingChannels,
    this.saturationUv = 562000.0,
    this.flatRangeUv = 0.5,
    this.kind = FeatureKind.alphaPower,
    this.timings,
  });

  final PipelineTimings? timings;

  final ProcessingConfig config;
  final List<String> trainingChannels;
  final double saturationUv;
  final double flatRangeUv;
  final FeatureKind kind;

  late int _fs;
  late int _windowSamples;
  late Welch _welch;
  late List<int> _idx;
  late List<SosFilter> _filters;
  late List<List<double>> _raw;
  late List<List<double>> _filt;
  var _count = 0;
  var _gapMark = 0;
  var _lastSample = -1;
  var _started = false;

  List<WindowResult> push(StreamItem item) {
    switch (item) {
      case SegmentStart():
        _start(item.info);
        return const [];
      case GapEvent():
        if (_started) {
          for (final f in _filters) {
            f.reset();
          }
          _gapMark = _count + _fs;
        }
        return const [];
      case DisconnectedEvent():
        return const [];
      case EegPacket():
        return _started ? _packet(item) : const [];
    }
  }

  void _start(StreamInfo info) {
    _fs = info.fs;
    _windowSamples = (config.windowS * _fs).round();
    final seg = (config.welchSegmentS * _fs).round();
    var nfft = 1;
    while (nfft < seg) {
      nfft <<= 1;
    }
    _welch = Welch(
      fs: _fs.toDouble(),
      segment: seg,
      overlap: (seg * config.welchOverlap).round(),
      nfft: nfft * 2,
    );
    _idx = [for (final n in trainingChannels) info.channelIndex(n)];
    _filters = [
      for (final _ in _idx)
        SosFilter.bandpass(
          fs: _fs.toDouble(),
          lowHz: config.filterLowHz,
          highHz: config.filterHighHz,
          order: config.filterOrder,
          notchHz: config.notchHz,
        ),
    ];
    _raw = [for (final _ in _idx) <double>[]];
    _filt = [for (final _ in _idx) <double>[]];
    _count = 0;
    _gapMark = 0;
    _started = true;
  }

  final _sw = Stopwatch();
  int _filterAcc = 0;

  List<WindowResult> _packet(EegPacket p) {
    final out = <WindowResult>[];
    final t = timings;
    if (t != null)
      _sw
        ..reset()
        ..start();
    for (var i = 0; i < p.length; i++) {
      for (var c = 0; c < _idx.length; c++) {
        final r = p.samples[_idx[c]][i];
        _raw[c].add(r);
        _filt[c].add(_filters[c].process(r));
        if (_raw[c].length > _windowSamples) {
          _raw[c].removeAt(0);
          _filt[c].removeAt(0);
        }
      }
      _count++;
      _lastSample = p.firstSample + i;
      if (_count >= _windowSamples &&
          (_count - _windowSamples) % config.stepSamples == 0) {
        if (t != null) _filterAcc += _sw.elapsedMicroseconds;
        out.add(_evaluate());
        if (t != null)
          _sw
            ..reset()
            ..start();
      }
    }
    if (t != null) _filterAcc += _sw.elapsedMicroseconds;
    return out;
  }

  WindowResult _evaluate() {
    final tm = timings;
    final total = Stopwatch();
    if (tm != null) total.start();
    final reason = _checkQuality();
    final qualityUs = tm == null ? 0 : total.elapsedMicroseconds;
    final end = _lastSample + 1;
    final t = end / _fs;
    if (reason != null) {
      _record(qualityUs, 0, total);
      return WindowResult(
        sampleEnd: end,
        tSec: t,
        valid: false,
        reason: reason,
      );
    }
    final welch0 = total.elapsedMicroseconds;
    var sum = 0.0;
    Float64List? psdSum;
    for (final f in _filt) {
      final psd = _welch.psd(f);
      if (kind == FeatureKind.alphaPower) {
        final acc = psdSum ??= Float64List(psd.length);
        for (var k = 0; k < psd.length; k++) {
          acc[k] += psd[k];
        }
      }
      final alpha = _welch.bandPower(
        psd,
        config.alphaLowHz,
        config.alphaHighHz,
      );
      switch (kind) {
        case FeatureKind.alphaPower:
          sum += log((alpha + config.eps) / config.p0);
        case FeatureKind.betaOverAlphaTheta:
          final theta = _welch.bandPower(psd, 4, config.alphaLowHz);
          final beta = _welch.bandPower(psd, 13, 30);
          sum += log((beta + config.eps) / (alpha + theta + config.eps));
      }
    }
    _record(qualityUs, total.elapsedMicroseconds - welch0, total);
    return WindowResult(
      sampleEnd: end,
      tSec: t,
      valid: true,
      feature: sum / _filt.length,
      peakHz: psdSum == null ? null : _peak(psdSum),
    );
  }

  void _record(int qualityUs, int welchUs, Stopwatch total) {
    final tm = timings;
    if (tm == null) return;
    tm.filterUs.add(_filterAcc);
    tm.qualityUs.add(qualityUs);
    tm.welchUs.add(welchUs);
    tm.totalUs.add(_filterAcc + total.elapsedMicroseconds);
    _filterAcc = 0;
  }

  double? _peak(Float64List psd) {
    var best = -1.0;
    double? hz;
    for (var k = 0; k < psd.length; k++) {
      final f = k * _welch.df;
      if (f >= 7 && f <= 13 && psd[k] > best) {
        best = psd[k];
        hz = f;
      }
    }
    return hz;
  }

  InvalidReason? _checkQuality() {
    if (_count - _windowSamples < _gapMark) return InvalidReason.gap;
    for (final r in _raw) {
      var lo = r.first, hi = r.first;
      for (final v in r) {
        if (v.abs() >= saturationUv) return InvalidReason.saturation;
        lo = min(lo, v);
        hi = max(hi, v);
      }
      if (hi - lo < flatRangeUv) return InvalidReason.flat;
    }
    for (final f in _filt) {
      var peak = 0.0, jump = 0.0;
      for (var i = 0; i < f.length; i++) {
        peak = max(peak, f[i].abs());
        if (i > 0) jump = max(jump, (f[i] - f[i - 1]).abs());
      }
      if (peak > config.ampThresholdUv) return InvalidReason.amplitude;
      if (jump > config.ampThresholdUv) return InvalidReason.jump;
    }
    for (final f in _filt) {
      final psd = _welch.psd(f);
      final total = _welch.bandPower(
        psd,
        config.filterLowHz,
        config.filterHighHz,
      );
      final hf = _welch.bandPower(psd, 30, config.filterHighHz);
      if (total > 0 && hf / total > config.hfRatioThreshold) {
        return InvalidReason.muscle;
      }
    }
    return null;
  }
}
