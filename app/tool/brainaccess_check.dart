import 'dart:io';

import 'package:neurotchi/core/eeg/brainaccess/brainaccess_mac_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';

/// Sprawdzian czepka: laczy sie, strumieniuje [seconds] s i wypisuje podsumowanie.
/// Uruchamiac z Terminal.app (uprawnienie Bluetooth).
Future<void> main(List<String> args) async {
  final device = args.isNotEmpty ? args[0] : 'BA MAXI 012';
  final seconds = args.length > 1 ? int.parse(args[1]) : 15;
  final lib = Platform.environment['BACORE_LIB'] ??
      '../vendor/mac_os_testing/BrainAccessCore-4.0.0-macos/lib/libbacore.dylib';

  final source = BrainAccessMacSource(deviceName: device, libPath: lib);
  var packets = 0, samples = 0, gaps = 0;
  var first = true;
  final sw = Stopwatch()..start();
  final done = source.items.forEach((i) {
    switch (i) {
      case SegmentStart():
        stdout.writeln('segment: fs=${i.info.fs} kanaly=${i.info.channels.length} chunk=${i.info.chunkSize}');
      case EegPacket():
        packets++;
        samples += i.length;
        if (first) {
          first = false;
          stdout.writeln('pierwsza paczka po ${sw.elapsedMilliseconds} ms, probka ${i.firstSample}');
        }
      case GapEvent():
        gaps++;
        stdout.writeln('luka: od ${i.firstSample}, ${i.count} probek');
      case DisconnectedEvent():
        stdout.writeln('rozlaczono: ${i.reason}');
    }
  });
  await source.start();
  await Future<void>.delayed(Duration(seconds: seconds));
  await source.stop();
  await done;
  stdout.writeln('paczki=$packets probki=$samples luki=$gaps czas=${sw.elapsed.inSeconds} s');
}
