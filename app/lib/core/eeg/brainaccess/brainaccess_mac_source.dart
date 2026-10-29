import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import '../eeg_source.dart';
import '../stream_item.dart';
import 'bacore.dart';

const _fs = 250;
const _chunkSize = 25;

class _WorkerInit {
  const _WorkerInit(
      this.out, this.libPath, this.device, this.channelCount, this.bias);

  final SendPort out;
  final String libPath;
  final String device;
  final int? channelCount;
  final List<int> bias;
}

/// Callback paczek wolany z watku BLE. Przechwytuje tylko zmienne `final`.
NativeCallable<BaChunkCallback> createChunkCallback(SendPort port, int snIdx,
    int firstChannelIdx, int channels, int firstContactIdx) {
  final out = port;
  final sn0 = snIdx;
  final ch0 = firstChannelIdx;
  final n = channels;
  final ct0 = firstContactIdx;
  return NativeCallable<BaChunkCallback>.isolateGroupBound(
      (Pointer<Pointer<Void>> data, int size, Pointer<Void> user) {
    final sn = data[sn0].cast<Uint64>().asTypedList(size);
    final flat = Float64List(n * size);
    for (var c = 0; c < n; c++) {
      flat.setRange(c * size, (c + 1) * size,
          data[ch0 + c].cast<Double>().asTypedList(size));
    }
    Uint8List? contact;
    if (ct0 >= 0) {
      contact = Uint8List(n * size);
      for (var c = 0; c < n; c++) {
        contact.setRange(c * size, (c + 1) * size,
            data[ct0 + c].cast<Uint8>().asTypedList(size));
      }
    }
    out.send([
      'chunk',
      sn.first,
      DateTime.now().microsecondsSinceEpoch / 1e6,
      size,
      flat,
      contact,
    ]);
  });
}

NativeCallable<BaVoidCallback> createDisconnectCallback(SendPort port) {
  final out = port;
  return NativeCallable<BaVoidCallback>.isolateGroupBound(
      (Pointer<Void> user) {
    out.send(['disconnected', DateTime.now().microsecondsSinceEpoch / 1e6]);
  });
}

/// Watek z blokujacymi wywolaniami SDK. Callback paczek jest wolany przez
/// watek BLE biblioteki, kopiuje dane do wiadomosci i od razu wraca.
void _worker(_WorkerInit init) {
  final out = init.out;
  final cmd = ReceivePort();
  BaCore? core;
  Pointer<Void>? mgr;
  NativeCallable<BaChunkCallback>? chunkCb;
  NativeCallable<BaVoidCallback>? discCb;
  var streaming = false;
  var closed = false;

  void shutdown() {
    if (closed) return;
    closed = true;
    if (core != null && mgr != null) {
      if (streaming) core.stopStream(mgr, nullptr, nullptr);
      core.setCallbackChunk(mgr, nullptr, nullptr);
      core.setCallbackDisconnect(mgr, nullptr, nullptr);
      core.disconnect(mgr);
      core.managerFree(mgr);
      core.coreClose();
    }
    chunkCb?.close();
    discCb?.close();
    cmd.close();
    out.send(['closed']);
  }

  try {
    core = BaCore.open(init.libPath);
    core.coreInit();
    mgr = core.managerNew();
    final err = core.connect(mgr, init.device);
    if (err != 0) {
      out.send(['error', 'connect_failed:$err']);
      shutdown();
      return;
    }
    final info = core.deviceInfo(mgr);
    final electrodes = core.electrodeCount(info);
    final n = init.channelCount ?? electrodes;
    if (n > electrodes) {
      out.send(['error', 'channels:$n>$electrodes']);
      shutdown();
      return;
    }
    core.setDataStreamRate(mgr, baStreamRate250Hz);
    core.setChannelEnabled(mgr, baChannelSampleNumber, true);
    for (var c = 0; c < n; c++) {
      core.setChannelEnabled(mgr, baChannelMeasurement + c, true);
      core.setChannelEnabled(mgr, baChannelContact + c, true);
    }
    for (final b in init.bias) {
      core.setChannelBiasFeedback(mgr, baChannelMeasurement + b);
    }
    final cfgErr = core.loadConfig(mgr, nullptr, nullptr);
    if (cfgErr != 0) {
      out.send(['error', 'load_config:$cfgErr']);
      shutdown();
      return;
    }
    final snIdx = core.channelIndex(mgr, baChannelSampleNumber);
    final m0 = core.channelIndex(mgr, baChannelMeasurement);
    for (var c = 0; c < n; c++) {
      if (core.channelIndex(mgr, baChannelMeasurement + c) != m0 + c) {
        out.send(['error', 'noncontiguous_channels']);
        shutdown();
        return;
      }
    }
    final c0 = core.channelIndex(mgr, baChannelContact);
    for (var c = 0; c < n; c++) {
      if (core.channelIndex(mgr, baChannelContact + c) != c0 + c) {
        out.send(['error', 'noncontiguous_contact']);
        shutdown();
        return;
      }
    }
    chunkCb = createChunkCallback(out, snIdx, m0, n, c0);
    discCb = createDisconnectCallback(out);
    core.setCallbackChunk(mgr, chunkCb.nativeFunction.cast(), nullptr);
    core.setCallbackDisconnect(mgr, discCb.nativeFunction.cast(), nullptr);

    cmd.listen((m) {
      if (m == 'stop') shutdown();
    });
    out.send(['ready', cmd.sendPort, n]);
    final startErr = core.startStream(mgr, nullptr, nullptr);
    if (startErr != 0) {
      out.send(['error', 'start_stream:$startErr']);
      shutdown();
      return;
    }
    streaming = true;
  } catch (e) {
    out.send(['error', 'exception:$e']);
    shutdown();
  }
}

/// Sklada paczki z numerow probek i wykrywa luki.
class ChunkAssembler {
  int? _next;

  List<StreamItem> chunk({
    required int firstSample,
    required double tRecv,
    required Float64List flat,
    required int size,
    required int channels,
    Uint8List? contact,
  }) {
    final out = <StreamItem>[];
    final expected = _next;
    if (expected != null && firstSample != expected) {
      out.add(GapEvent(firstSample: expected, count: firstSample - expected));
    }
    out.add(EegPacket(
      firstSample: firstSample,
      tRecv: tRecv,
      samples: [
        for (var c = 0; c < channels; c++)
          flat.sublist(c * size, (c + 1) * size),
      ],
      contact: contact == null
          ? null
          : [
              for (var c = 0; c < channels; c++)
                [
                  for (var i = 0; i < size; i++) contact[c * size + i] != 0,
                ],
            ],
    ));
    _next = firstSample + size;
    return out;
  }
}

/// Czepek BrainAccess na macOS przez FFI do libbacore (SDK C).
/// Utrata polaczenia konczy strumien po [DisconnectedEvent]; ponowne
/// polaczenie to nowa instancja zrodla.
class BrainAccessMacSource implements EegSource {
  BrainAccessMacSource({
    required this.deviceName,
    required this.libPath,
    this.channelNames,
    this.biasChannels = const [],
  });

  final String deviceName;
  final String libPath;

  /// Nazwy kolejnych kanalow EEG (SDK ich nie podaje). Domyslnie ch1, ch2, ...
  final List<String>? channelNames;

  /// Indeksy kanalow (od 0), z ktorych urzadzenie liczy sygnal BIAS (aktywna
  /// masa). Bez nich SDK nie redukuje szumu wspolnego.
  final List<int> biasChannels;

  final _controller = StreamController<StreamItem>();
  final _assembler = ChunkAssembler();
  final _closed = Completer<void>();
  ReceivePort? _in;
  SendPort? _cmd;
  Isolate? _isolate;
  int _channels = 0;
  bool _stopping = false;
  bool _started = false;

  @override
  Stream<StreamItem> get items => _controller.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final port = _in = ReceivePort();
    port.listen(_onMessage);
    _isolate = await Isolate.spawn(
      _worker,
      _WorkerInit(port.sendPort, libPath, deviceName, channelNames?.length,
          biasChannels),
    );
  }

  void _onMessage(dynamic m) {
    final msg = m as List;
    switch (msg[0] as String) {
      case 'ready':
        _cmd = msg[1] as SendPort;
        if (_stopping) {
          _cmd!.send('stop');
          return;
        }
        _channels = msg[2] as int;
        _controller.add(SegmentStart(StreamInfo(
          sourceId: 'brainaccess',
          fs: _fs,
          chunkSize: _chunkSize,
          channels: [
            for (var c = 0; c < _channels; c++)
              Channel(channelNames?[c] ?? 'ch${c + 1}'),
          ],
        )));
      case 'chunk':
        if (_stopping) return;
        for (final i in _assembler.chunk(
          firstSample: msg[1] as int,
          tRecv: msg[2] as double,
          size: msg[3] as int,
          flat: msg[4] as Float64List,
          contact: msg[5] as Uint8List?,
          channels: _channels,
        )) {
          _controller.add(i);
        }
      case 'disconnected':
        if (_stopping) return;
        _controller.add(DisconnectedEvent(
            reason: 'sdk_disconnect', tRecv: msg[1] as double));
        unawaited(stop());
      case 'error':
        if (_stopping) return;
        _controller.add(DisconnectedEvent(
            reason: msg[1] as String,
            tRecv: DateTime.now().microsecondsSinceEpoch / 1e6));
        if (_cmd == null) {
          unawaited(_finish());
        } else {
          unawaited(stop());
        }
      case 'closed':
        unawaited(_finish());
    }
  }

  @override
  Future<void> stop() async {
    if (_stopping) return _closed.future;
    _stopping = true;
    final cmd = _cmd;
    if (cmd == null) {
      if (_isolate == null) {
        await _finish();
      }
    } else {
      cmd.send('stop');
    }
    return _closed.future;
  }

  Future<void> _finish() async {
    if (_closed.isCompleted) return;
    _in?.close();
    _isolate?.kill();
    if (!_controller.isClosed) await _controller.close();
    _closed.complete();
  }
}
