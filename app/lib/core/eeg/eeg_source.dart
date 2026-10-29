import 'stream_item.dart';

abstract interface class EegSource {
  Stream<StreamItem> get items;

  Future<void> start();

  /// Zatrzymanie przez uzytkownika zamyka strumien. Utrata polaczenia
  /// jest sygnalizowana zdarzeniem [DisconnectedEvent].
  Future<void> stop();
}
