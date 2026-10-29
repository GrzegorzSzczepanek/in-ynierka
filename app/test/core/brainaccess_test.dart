import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/eeg/brainaccess/bacore.dart';
import 'package:neurotchi/core/eeg/brainaccess/brainaccess_mac_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';

const _lib =
    '../vendor/mac_os_testing/BrainAccessCore-4.0.0-macos/lib/libbacore.dylib';

void main() {
  fakeLibTests();
  test('uklad struktury ba_device_info zgodny z naglowkiem C', () {
    expect(sizeOf<BaDeviceInfo>(), 24);
    expect(sizeOf<BaVersion>(), 3);
  });

  test('ChunkAssembler wykrywa luke w numeracji probek', () {
    final a = ChunkAssembler();
    Float64List flat(int n) => Float64List(2 * n);
    final first = a.chunk(
        firstSample: 0, tRecv: 0, flat: flat(25), size: 25, channels: 2);
    expect(first.single, isA<EegPacket>());
    final next = a.chunk(
        firstSample: 25, tRecv: 0, flat: flat(25), size: 25, channels: 2);
    expect(next.single, isA<EegPacket>());
    final after = a.chunk(
        firstSample: 100, tRecv: 0, flat: flat(25), size: 25, channels: 2);
    expect(after.first, isA<GapEvent>());
    final gap = after.first as GapEvent;
    expect((gap.firstSample, gap.count), (50, 50));
    expect((after.last as EegPacket).samples.length, 2);
  });

  test('ChunkAssembler przekazuje kontakt elektrod na kanal i probke', () {
    final contact = Uint8List.fromList([1, 1, 0, 0, 0, 1]);
    final out = ChunkAssembler().chunk(
        firstSample: 0,
        tRecv: 0,
        flat: Float64List(6),
        size: 3,
        channels: 2,
        contact: contact);
    final p = out.single as EegPacket;
    expect(p.contact, [
      [true, true, false],
      [false, false, true],
    ]);
  });

  test('biblioteka libbacore laduje sie, init i wersja 4.0.0', () {
    if (!File(_lib).existsSync()) {
      markTestSkipped('brak libbacore w vendor/');
      return;
    }
    final core = BaCore.open(_lib);
    expect(core.coreVersion().ref.toString(), '4.0.0');
    final init = core.coreInit();
    expect(init, anyOf(0, 7));
    expect(core.coreClose(), anyOf(0, 9));
  });
}

typedef _FireNative = Void Function(Pointer<NativeFunction<BaChunkCallback>>);
typedef _Fire = void Function(Pointer<NativeFunction<BaChunkCallback>>);

Future<void> _fakeWorker(List<Object> args) async {
  final out = args[0] as SendPort;
  final lib = DynamicLibrary.open(args[1] as String);
  final fire = lib.lookupFunction<_FireNative, _Fire>('fire');
  final cb = createChunkCallback(out, 0, 1, 1, -1);
  fire(cb.nativeFunction);
  await Future<void>.delayed(const Duration(milliseconds: 500));
  cb.close();
  out.send(['end']);
}

void fakeLibTests() {
  test('callback paczek z natywnego watku kopiuje dane (atrapa w C)', () async {
    final dir = Directory.systemTemp.createTempSync('fake_bacore');
    final so = '${dir.path}/libfake.dylib';
    final cc = Process.runSync(
        'clang', ['-dynamiclib', '-o', so, 'test/fixtures/fake_bacore.c']);
    if (cc.exitCode != 0) {
      markTestSkipped('brak clang');
      return;
    }
    final rp = ReceivePort();
    await Isolate.spawn(_fakeWorker, [rp.sendPort, so]);
    final chunks = <List>[];
    await for (final m in rp) {
      final l = m as List;
      if (l[0] == 'end') break;
      chunks.add(l);
    }
    rp.close();
    expect(chunks.length, 5);
    expect([for (final c in chunks) c[1]], [0, 25, 50, 75, 100]);
    final last = chunks.last[4] as Float64List;
    expect(last.length, 25);
    expect(last[0], 4.0);
    expect(last[24], closeTo(4.24, 1e-9));
  });
}
