import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../eeg_source.dart';
import '../stream_item.dart';

const brainAccessMethods = MethodChannel('pl.pwr.neurotchi/brainaccess');
const brainAccessEvents = EventChannel('pl.pwr.neurotchi/brainaccess/stream');

/// Dzieli paczke z SDK na pakiety i luki: probki oznaczone jako dummy to
/// uzupelnienie brakow, wiec nie sa danymi.
List<StreamItem> splitDummy({
  required int firstSample,
  required double tRecv,
  required Float64List flat,
  required int size,
  required int channels,
  required Uint8List contact,
  required Uint8List dummy,
}) {
  final out = <StreamItem>[];
  var i = 0;
  while (i < size) {
    final isDummy = dummy[i] != 0;
    var j = i;
    while (j < size && (dummy[j] != 0) == isDummy) {
      j++;
    }
    if (isDummy) {
      out.add(GapEvent(firstSample: firstSample + i, count: j - i));
    } else {
      final len = j - i;
      out.add(EegPacket(
        firstSample: firstSample + i,
        tRecv: tRecv,
        samples: [for (var c = 0; c < channels; c++) flat.sublist(c * size + i, c * size + j)],
        contact: [for (var c = 0; c < channels; c++) List.filled(len, contact[c] != 0)],
      ));
    }
    i = j;
  }
  return out;
}

/// Czepek BrainAccess na Androidzie przez SDK Kotlin (BrainAccessKit) i kanal platformy.
class BrainAccessAndroidSource implements EegSource {
  BrainAccessAndroidSource({
    required this.deviceName,
    this.channelNames,
    this.biasChannels = const [],
    MethodChannel? methods,
    EventChannel? events,
  })  : _methods = methods ?? brainAccessMethods,
        _events = events ?? brainAccessEvents;

  final String deviceName;
  final List<String>? channelNames;
  final List<int> biasChannels;
  final MethodChannel _methods;
  final EventChannel _events;

  final _controller = StreamController<StreamItem>();
  final _closed = Completer<void>();
  StreamSubscription<dynamic>? _sub;
  int _channels = 0;
  int? _next;
  bool _started = false;
  bool _stopping = false;

  @override
  Stream<StreamItem> get items => _controller.stream;

  double get _now => DateTime.now().microsecondsSinceEpoch / 1e6;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = _events.receiveBroadcastStream().listen(_onEvent, onError: (Object e) => _fail('$e'));
    try {
      await _methods.invokeMethod<void>('start', {
        'device': deviceName,
        'channels': channelNames?.length ?? 0,
        'bias': biasChannels,
      });
    } on PlatformException catch (e) {
      _fail(e.message ?? e.code);
    }
  }

  void _onEvent(dynamic event) {
    if (_stopping) return;
    final m = (event as Map).cast<String, dynamic>();
    switch (m['t']) {
      case 'ready':
        _channels = m['channels'] as int;
        _controller.add(SegmentStart(StreamInfo(
          sourceId: 'brainaccess',
          fs: m['fs'] as int,
          chunkSize: 25,
          channels: [for (var c = 0; c < _channels; c++) Channel(channelNames?[c] ?? 'ch${c + 1}')],
        )));
      case 'chunk':
        final first = (m['first'] as num).toInt();
        final size = m['size'] as int;
        final expected = _next;
        if (expected != null && first > expected) {
          _controller.add(GapEvent(firstSample: expected, count: first - expected));
        }
        for (final i in splitDummy(
          firstSample: first,
          tRecv: _now,
          flat: m['samples'] as Float64List,
          size: size,
          channels: m['channels'] as int,
          contact: m['contact'] as Uint8List,
          dummy: m['dummy'] as Uint8List,
        )) {
          _controller.add(i);
        }
        _next = first + size;
      case 'disconnected':
        _fail(m['reason'] as String? ?? 'sdk_disconnect');
    }
  }

  void _fail(String reason) {
    if (_stopping) return;
    if (!_controller.isClosed) _controller.add(DisconnectedEvent(reason: reason, tRecv: _now));
    unawaited(stop());
  }

  @override
  Future<void> stop() async {
    if (_stopping) return _closed.future;
    _stopping = true;
    await _sub?.cancel();
    try {
      await _methods.invokeMethod<void>('stop');
    } on PlatformException {
      // rozlaczenie i tak konczy strumien
    }
    if (!_controller.isClosed) await _controller.close();
    _closed.complete();
    return _closed.future;
  }
}

/// Skan czepkow BrainAccess przez SDK Kotlin (prosi o zgode na Bluetooth).
Future<List<String>> scanAndroid() async {
  final r = await brainAccessMethods.invokeListMethod<String>('scan');
  return r ?? const [];
}
