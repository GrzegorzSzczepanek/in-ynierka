import 'dart:math';

import '../eeg/stream_item.dart';
import 'biquad.dart';
import 'processing_config.dart';
import 'welch.dart';

enum InvalidReason { gap, saturation, flat, amplitude, jump, muscle }

class WindowResult {
  const WindowResult({
    required this.sampleEnd,
    required this.tSec,
    required this.valid,
    this.reason,
    this.feature,
  });

  final int sampleEnd;
  final double tSec;
  final bool valid;
  final InvalidReason? reason;

  /// x(t): srednia po kanalach z ln((P_alfa + eps) / P0). Tylko dla okien waznych.
  final double? feature;
}

/// Potok: filtr przyczynowy, okno przesuwne, kontrola jakosci, moc alfa.
/// Kontrola jakosci zapada przed obliczeniem cechy.
class AlphaPipeline {
  AlphaPipeline(
    this.config, {
    required this.trainingChannels,
    this.saturationUv = 562000.0,
    this.flatRangeUv = 0.5,
  });

  final ProcessingConfig config;
  final List<String> trainingChannels;
  final double saturationUv;
  final double flatRangeUv;

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

  List<WindowResult> _packet(EegPacket p) {
    final out = <WindowResult>[];
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
        out.add(_evaluate());
      }
    }
    return out;
  }

  WindowResult _evaluate() {
    final reason = _checkQuality();
    final end = _lastSample + 1;
    final t = end / _fs;
    if (reason != null) {
      return WindowResult(sampleEnd: end, tSec: t, valid: false, reason: reason);
    }
    var sum = 0.0;
    for (final f in _filt) {
      final psd = _welch.psd(f);
      final p = _welch.bandPower(psd, config.alphaLowHz, config.alphaHighHz);
      sum += log((p + config.eps) / config.p0);
    }
    return WindowResult(
      sampleEnd: end,
      tSec: t,
      valid: true,
      feature: sum / _filt.length,
    );
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
      final total = _welch.bandPower(psd, config.filterLowHz, config.filterHighHz);
      final hf = _welch.bandPower(psd, 30, config.filterHighHz);
      if (total > 0 && hf / total > config.hfRatioThreshold) {
        return InvalidReason.muscle;
      }
    }
    return null;
  }
}
