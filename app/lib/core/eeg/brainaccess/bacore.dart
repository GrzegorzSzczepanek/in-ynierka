import 'dart:convert';
import 'dart:ffi';

const baChannelSampleNumber = 0;
const baChannelMeasurement = 1;
const baChannelContact = 1025;

const baStreamRate250Hz = 6;

final class BaVersion extends Struct {
  @Uint8()
  external int major;
  @Uint8()
  external int minor;
  @Uint8()
  external int patch;

  @override
  String toString() => '$major.$minor.$patch';
}

final class BaDeviceInfo extends Struct {
  @Uint8()
  external int id;
  external BaVersion hardwareVersion;
  external BaVersion firmwareVersion;
  @Size()
  external int serialNumber;
  @Size()
  external int samplePerPacket;
}

final class BaBleDevice extends Struct {
  external Pointer<Uint8> name;
  external Pointer<Uint8> macAddress;
}

String _cString(Pointer<Uint8> p) {
  if (p == nullptr) return '';
  final bytes = <int>[];
  for (var i = 0; p[i] != 0 && i < 256; i++) {
    bytes.add(p[i]);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

typedef BaChunkCallback = Void Function(
  Pointer<Pointer<Void>>,
  Size,
  Pointer<Void>,
);
typedef BaVoidCallback = Void Function(Pointer<Void>);

typedef _MallocN = Pointer<Void> Function(Size);
typedef _Malloc = Pointer<Void> Function(int);
typedef _FreeN = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);

/// Reczne wiazania do libbacore 4.0.0 (macOS), tylko to, czego uzywamy.
class BaCore {
  BaCore._(this._lib);

  factory BaCore.open(String path) => BaCore._(DynamicLibrary.open(path));

  final DynamicLibrary _lib;

  late final int Function() coreInit = _lib
      .lookupFunction<Uint8 Function(), int Function()>('ba_core_init');
  late final int Function() coreClose = _lib
      .lookupFunction<Uint8 Function(), int Function()>('ba_core_close');
  late final Pointer<BaVersion> Function() coreVersion = _lib
      .lookupFunction<
        Pointer<BaVersion> Function(),
        Pointer<BaVersion> Function()
      >('ba_core_get_version');

  late final Pointer<Void> Function() managerNew = _lib
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'ba_eeg_manager_new',
      );
  late final void Function(Pointer<Void>) managerFree = _lib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('ba_eeg_manager_free');
  late final int Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
  )
  _connect = _lib
      .lookupFunction<
        Uint8 Function(
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
        ),
        int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('ba_eeg_manager_connect');
  late final void Function(Pointer<Void>) disconnect = _lib
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('ba_eeg_manager_disconnect');
  late final int Function(Pointer<Void>) _isConnected = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('ba_eeg_manager_is_connected');
  late final int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
  startStream = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('ba_eeg_manager_start_stream');
  late final int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
  stopStream = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('ba_eeg_manager_stop_stream');
  late final int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
  loadConfig = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('ba_eeg_manager_load_config');
  late final void Function(Pointer<Void>, int, bool) setChannelEnabled = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint16, Bool),
        void Function(Pointer<Void>, int, bool)
      >('ba_eeg_manager_set_channel_enabled');
  late final void Function(Pointer<Void>, int) setChannelBiasFeedback = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Uint16),
        void Function(Pointer<Void>, int)
      >('ba_eeg_manager_set_channel_bias_feedback');
  late final int Function(Pointer<Void>, int) setDataStreamRate = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>, Uint8),
        int Function(Pointer<Void>, int)
      >('ba_eeg_manager_set_data_stream_rate');
  late final int Function(Pointer<Void>, int) channelIndex = _lib
      .lookupFunction<
        Size Function(Pointer<Void>, Uint16),
        int Function(Pointer<Void>, int)
      >('ba_eeg_manager_get_channel_index');
  late final Pointer<BaDeviceInfo> Function(Pointer<Void>) deviceInfo = _lib
      .lookupFunction<
        Pointer<BaDeviceInfo> Function(Pointer<Void>),
        Pointer<BaDeviceInfo> Function(Pointer<Void>)
      >('ba_eeg_manager_get_device_info');
  late final void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
  setCallbackChunk = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
        void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('ba_eeg_manager_set_callback_chunk');
  late final void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
  setCallbackDisconnect = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
        void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('ba_eeg_manager_set_callback_disconnect');
  late final Pointer<Void> Function(Pointer<BaDeviceInfo>) _featuresGet = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<BaDeviceInfo>),
        Pointer<Void> Function(Pointer<BaDeviceInfo>)
      >('ba_core_device_features_get');
  late final int Function(Pointer<Void>) _electrodeCount = _lib
      .lookupFunction<
        Uint8 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('ba_core_device_features_electrode_count');

  static final _libc = DynamicLibrary.process();
  static final _malloc = _libc.lookupFunction<_MallocN, _Malloc>('malloc');
  static final _free = _libc.lookupFunction<_FreeN, _Free>('free');

  late final int Function(Pointer<Pointer<BaBleDevice>>, Pointer<Size>) _scan =
      _lib.lookupFunction<
        Uint8 Function(Pointer<Pointer<BaBleDevice>>, Pointer<Size>),
        int Function(Pointer<Pointer<BaBleDevice>>, Pointer<Size>)
      >('ba_core_scan');

  /// Skanuje BLE (ok. 5 s, wymaga uprawnienia Bluetooth) i zwraca nazwy czepkow BrainAccess.
  List<String> scanNames() {
    final devs = _malloc(8).cast<Pointer<BaBleDevice>>();
    final count = _malloc(8).cast<Size>();
    try {
      count.value = 0;
      final err = _scan(devs, count);
      if (err != 0) throw StateError('Skan BLE nie powiodl sie (kod $err)');
      return [
        for (var i = 0; i < count.value; i++)
          _cString((devs.value + i).ref.name),
      ];
    } finally {
      _free(devs.cast());
      _free(count.cast());
    }
  }

  bool isConnected(Pointer<Void> mgr) => _isConnected(mgr) != 0;

  int electrodeCount(Pointer<BaDeviceInfo> info) {
    final f = _featuresGet(info);
    return f == nullptr ? 0 : _electrodeCount(f);
  }

  /// Laczy z czepkiem o podanej nazwie (blokuje do kilkunastu sekund).
  int connect(Pointer<Void> mgr, String name) {
    final bytes = utf8.encode(name);
    final buf = _malloc(bytes.length + 1).cast<Uint8>();
    buf.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    try {
      return _connect(mgr, buf.cast(), nullptr, nullptr);
    } finally {
      _free(buf.cast());
    }
  }
}
