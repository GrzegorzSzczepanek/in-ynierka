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

  final source = BrainAccessMacSource(
      deviceName: device, libPath: lib, biasChannels: _bias(args, 2));
  var packets = 0, samples = 0, gaps = 0;
  var first = true;
  List<int>? contactTrue;
  final sw = Stopwatch()..start();
  final done = source.items.forEach((i) {
    switch (i) {
      case SegmentStart():
        stdout.writeln('segment: fs=${i.info.fs} kanaly=${i.info.channels.length} chunk=${i.info.chunkSize}');
      case EegPacket():
        packets++;
        samples += i.length;
        final ct = i.contact;
        if (ct != null) {
          final acc = contactTrue ??= List.filled(ct.length, 0);
          for (var c = 0; c < ct.length; c++) {
            acc[c] += ct[c].where((v) => v).length;
          }
        }
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
  final acc = contactTrue;
  if (acc != null && samples > 0) {
    final withContact = [
      for (var c = 0; c < acc.length; c++)
        if (acc[c] / samples > 0.9) 'ch${c + 1}'
    ];
    stdout.writeln('kontakt (>90% czasu): ${withContact.isEmpty ? 'zaden kanal' : withContact.join(', ')}');
  }
  stdout.writeln('paczki=$packets probki=$samples luki=$gaps czas=${sw.elapsed.inSeconds} s');
}

/// Opcjonalny argument: indeksy kanalow BIAS od 0, np. 1,9.
List<int> _bias(List<String> args, int at) => args.length > at && args[at].isNotEmpty
    ? args[at].split(',').map(int.parse).toList()
    : const [];
