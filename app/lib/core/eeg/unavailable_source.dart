import 'dart:async';

import 'eeg_source.dart';
import 'stream_item.dart';

/// Zrodlo, ktorego nie da sie uruchomic (brak biblioteki lub nazwy czepka):
/// od razu zglasza utrate polaczenia z powodem, wiec UI pokazuje blad laczenia.
class UnavailableSource implements EegSource {
  UnavailableSource(this.reason);

  final String reason;
  final _c = StreamController<StreamItem>();

  @override
  Stream<StreamItem> get items => _c.stream;

  @override
  Future<void> start() async {
    _c.add(DisconnectedEvent(reason: reason, tRecv: 0));
    unawaited(_c.close());
  }

  @override
  Future<void> stop() async {}
}
