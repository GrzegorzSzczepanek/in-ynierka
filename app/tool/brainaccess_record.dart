import 'dart:async';
import 'dart:io';

import 'package:neurotchi/core/eeg/brainaccess/brainaccess_mac_source.dart';
import 'package:neurotchi/core/eeg/recording_writer.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';

/// Nagrywa czepek do formatu Replay. Uruchamiac z Terminal.app.
/// dart run tool/brainaccess_record.dart "BA MAXI 012" 60 nagrania/sesja1
Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('uzycie: brainaccess_record <urzadzenie> <sekundy> <sciezka_bez_rozszerzenia>');
    exit(64);
  }
  final seconds = int.parse(args[1]);
  final lib = Platform.environment['BACORE_LIB'] ??
      '../vendor/mac_os_testing/BrainAccessCore-4.0.0-macos/lib/libbacore.dylib';
  Directory(File(args[2]).parent.path).createSync(recursive: true);

  final source = BrainAccessMacSource(
      deviceName: args[0], libPath: lib, biasChannels: _bias(args, 3));
  final writer = RecordingWriter(args[2]);
  var gaps = 0;
  final first = Completer<void>();
  String? disconnected;
  final done = source.items.asyncMap((i) async {
    await writer.add(i);
    if (i is GapEvent) gaps++;
    if (i is EegPacket && !first.isCompleted) first.complete();
    if (i is DisconnectedEvent) disconnected = i.reason;
  }).drain<void>();
  await source.start();
  await first.future.timeout(const Duration(seconds: 40), onTimeout: () {});
  stdout.writeln('START: nagrywam $seconds s od teraz');
  await Future<void>.delayed(Duration(seconds: seconds));
  await source.stop();
  await done;
  await writer.close();
  stdout.writeln('zapisano ${args[2]}.csv: probki=${writer.samples} '
      'czas=${(writer.samples / 250).toStringAsFixed(1)} s luki=$gaps '
      'rozlaczenie=${disconnected ?? 'brak'}');
}

/// Opcjonalny argument: indeksy kanalow BIAS od 0, np. 1,9.
List<int> _bias(List<String> args, int at) => args.length > at && args[at].isNotEmpty
    ? args[at].split(',').map(int.parse).toList()
    : const [];
