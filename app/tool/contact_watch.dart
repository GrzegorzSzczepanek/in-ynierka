import 'dart:async';
import 'dart:io';

import 'package:neurotchi/core/eeg/brainaccess/brainaccess_mac_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';

/// Numery zlacz (od 0) wg tabel 2 i 3 instrukcji kabli BrainAccess. To tylko
/// podpowiedz: czy indeks SDK jest numerem zlacza, ustala ten pomiar.
const _manual = [
  'P8', 'O2', 'P4', 'C4', 'F8', 'F4', 'Oz', 'Cz', 'Fz', 'Pz', 'F3', 'O1',
  'P7', 'C3', 'P3', 'F7', 'T8', 'FC6', 'CP6', 'CP2', 'PO4', 'FC2', 'AF4',
  'POz', 'AFz', 'AF3', 'FC1', 'FC5', 'T7', 'CP1', 'CP5', 'PO3',
];

/// Na zywo pokazuje, ktore kanaly zyskuja lub traca kontakt. Dociskaj po
/// jednej elektrodzie i patrz, ktory kanal sie zmienia.
/// dart run tool/contact_watch.dart "BA MAXI 012" 90 1,9
Future<void> main(List<String> args) async {
  final seconds = args.length > 1 ? int.parse(args[1]) : 90;
  final bias = args.length > 2 && args[2].isNotEmpty
      ? args[2].split(',').map(int.parse).toList()
      : const <int>[];
  final lib = Platform.environment['BACORE_LIB'] ??
      '../vendor/mac_os_testing/BrainAccessCore-4.0.0-macos/lib/libbacore.dylib';
  final source = BrainAccessMacSource(
      deviceName: args[0], libPath: lib, biasChannels: bias);

  const window = 5;
  final history = <List<double>>[];
  Set<int> state = {};
  var t = 0.0;
  var first = true;
  final done = source.items.forEach((i) {
    if (i is! EegPacket || i.contact == null) return;
    t = (i.firstSample + i.length) / 250;
    history.add([
      for (final ch in i.contact!) ch.where((v) => v).length / ch.length,
    ]);
    if (history.length > window) history.removeAt(0);
    if (history.length < window) return;
    final now = {
      for (var c = 0; c < i.contact!.length; c++)
        if (history.map((h) => h[c]).reduce((a, b) => a + b) / window > 0.5) c,
    };
    String label(int c) => 'ch${c + 1} (${c < _manual.length ? _manual[c] : '?'})';
    if (first) {
      first = false;
      stdout.writeln('START ${t.toStringAsFixed(1)} s, kontakt: ${(now.toList()..sort()).map(label).join(', ')}');
    } else {
      for (final c in (now.difference(state).toList()..sort())) {
        stdout.writeln('t=${t.toStringAsFixed(1).padLeft(5)} s  + ${label(c)}');
      }
      for (final c in (state.difference(now).toList()..sort())) {
        stdout.writeln('t=${t.toStringAsFixed(1).padLeft(5)} s  - ${label(c)}');
      }
    }
    state = now;
  });
  await source.start();
  await Future<void>.delayed(Duration(seconds: seconds + 9));
  await source.stop();
  await done;
}
