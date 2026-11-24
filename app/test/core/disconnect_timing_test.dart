import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/eeg/brainaccess/brainaccess_mac_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';

void main() {
  test(
    'macOS: 3 s ciszy w strumieniu konczy sie DisconnectedEvent(data_timeout)',
    () async {
      final dir = Directory.systemTemp.createTempSync('fake_bacore_full');
      final so = '${dir.path}/libfake_full.dylib';
      final cc = Process.runSync('clang', [
        '-dynamiclib',
        '-o',
        so,
        'test/fixtures/fake_bacore_full.c',
      ]);
      if (cc.exitCode != 0) {
        markTestSkipped('brak clang: ${cc.stderr}');
        return;
      }
      final src = BrainAccessMacSource(
        deviceName: 'FAKE',
        libPath: so,
        channelNames: const ['O1', 'O2', 'F3', 'F4'],
      );
      final sw = Stopwatch()..start();
      var samples = 0;
      int? lastPacketMs;
      int? disconnectMs;
      String? reason;
      await src.start();
      await for (final item in src.items) {
        switch (item) {
          case SegmentStart():
            break;
          case EegPacket():
            samples += item.length;
            lastPacketMs = sw.elapsedMilliseconds;
          case GapEvent():
            break;
          case DisconnectedEvent():
            disconnectMs = sw.elapsedMilliseconds;
            reason = item.reason;
        }
        if (disconnectMs != null) break;
      }
      await src.stop();
      final silence = (disconnectMs! - lastPacketMs!) / 1000;
      // ignore: avoid_print
      print(
        'WF-9: odebrane probki=$samples, powod=$reason, '
        'cisza do zdarzenia=${silence.toStringAsFixed(3)} s',
      );
      expect(reason, 'data_timeout');
      expect(samples, 250);
      expect(silence, greaterThanOrEqualTo(3.0 - 0.05));
      expect(silence, lessThanOrEqualTo(3.0 + 0.5 + 0.2));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
