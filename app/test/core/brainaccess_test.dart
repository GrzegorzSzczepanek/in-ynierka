import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/eeg/brainaccess/bacore.dart';
import 'package:neurotchi/core/eeg/brainaccess/brainaccess_mac_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';

const _lib =
    '../vendor/mac_os_testing/BrainAccessCore-4.0.0-macos/lib/libbacore.dylib';

void main() {
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
