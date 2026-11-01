import 'dart:async';

import '../eeg/eeg_source.dart';
import '../eeg/stream_item.dart';
import 'session_controller.dart';
import 'session_models.dart';

enum MonitorStatus { connecting, connected, lost, failed }

class MonitorState {
  const MonitorState(this.status, {this.contact, this.attempt = 1});

  final MonitorStatus status;
  final List<ChannelContact>? contact;
  final int attempt;
}

/// Podglad polaczenia i kontaktu elektrod bez sesji (ekran Polaczenie).
class ConnectionMonitor {
  ConnectionMonitor(this.sourceFactory, {this.attempts = 3});

  final SourceFactory sourceFactory;
  final int attempts;

  final _states = StreamController<MonitorState>.broadcast();
  Stream<MonitorState> get states => _states.stream;
  EegSource? _source;
  bool _stopped = false;

  Future<void> start() async {
    for (var a = 1; a <= attempts && !_stopped; a++) {
      _emit(MonitorState(MonitorStatus.connecting, attempt: a));
      final src = _source = sourceFactory();
      await src.start();
      final it = StreamIterator(src.items);
      if (!(await it.moveNext()) || it.current is! SegmentStart) {
        await it.cancel();
        continue;
      }
      final names = [
        for (final c in (it.current as SegmentStart).info.channels) c.name,
      ];
      while (await it.moveNext()) {
        final item = it.current;
        if (item is EegPacket) {
          final ct = item.contact;
          _emit(
            MonitorState(
              MonitorStatus.connected,
              contact: ct == null
                  ? [for (final n in names) ChannelContact(n, false)]
                  : [
                      for (var i = 0; i < names.length; i++)
                        ChannelContact(
                          names[i],
                          ct[i].isNotEmpty && ct[i].last,
                        ),
                    ],
            ),
          );
        } else if (item is DisconnectedEvent) {
          if (!_stopped) _emit(const MonitorState(MonitorStatus.lost));
          return;
        }
      }
      return;
    }
    if (!_stopped) _emit(const MonitorState(MonitorStatus.failed));
  }

  void _emit(MonitorState s) {
    if (!_states.isClosed) _states.add(s);
  }

  Future<void> stop() async {
    _stopped = true;
    await _source?.stop();
    await _states.close();
  }
}
