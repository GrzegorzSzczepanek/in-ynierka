import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/eeg/brainaccess/brainaccess_android_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('luki z SDK (dummy) zamieniaja sie w GapEvent, reszta w pakiety', () {
    final items = splitDummy(
      firstSample: 100,
      tRecv: 1,
      flat: Float64List.fromList([1, 2, 3, 4, 10, 20, 30, 40]),
      size: 4,
      channels: 2,
      contact: Uint8List.fromList([1, 0]),
      dummy: Uint8List.fromList([0, 1, 1, 0]),
    );
    expect(items.length, 3);
    final a = items[0] as EegPacket;
    expect(a.firstSample, 100);
    expect(a.samples, [
      [1.0],
      [10.0]
    ]);
    expect(a.contact, [
      [true],
      [false]
    ]);
    final gap = items[1] as GapEvent;
    expect(gap.firstSample, 101);
    expect(gap.count, 2);
    final b = items[2] as EegPacket;
    expect(b.firstSample, 103);
    expect(b.samples, [
      [4.0],
      [40.0]
    ]);
  });

  test('zrodlo: start wysyla parametry, zdarzenia stają sie StreamItem, stop konczy strumien', () async {
    const methods = MethodChannel('test/ba');
    const events = EventChannel('test/ba/stream');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'start') {
        Future(() async {
          for (final m in [
            {'t': 'ready', 'channels': 2, 'fs': 250},
            {
              't': 'chunk',
              'first': 0,
              'size': 2,
              'channels': 2,
              'samples': Float64List.fromList([1, 2, 3, 4]),
              'contact': Uint8List.fromList([1, 1]),
              'dummy': Uint8List.fromList([0, 0]),
            },
            {
              't': 'chunk',
              'first': 6,
              'size': 1,
              'channels': 2,
              'samples': Float64List.fromList([5, 6]),
              'contact': Uint8List.fromList([1, 1]),
              'dummy': Uint8List.fromList([0]),
            },
            {'t': 'disconnected', 'reason': 'oddalil sie'},
          ]) {
            await messenger.handlePlatformMessage(
              events.name,
              const StandardMethodCodec().encodeSuccessEnvelope(m),
              (_) {},
            );
          }
        });
      }
      return null;
    });
    messenger.setMockStreamHandler(events, MockStreamHandler.inline(onListen: (_, __) {}));

    final src = BrainAccessAndroidSource(
      deviceName: 'BA MAXI 012',
      channelNames: const ['O1', 'O2'],
      biasChannels: const [0, 1],
      methods: methods,
      events: events,
    );
    final got = <StreamItem>[];
    final done = src.items.listen(got.add).asFuture<void>();
    await src.start();
    await done.timeout(const Duration(seconds: 5));

    expect(calls.first.arguments, {'device': 'BA MAXI 012', 'channels': 2, 'bias': [0, 1]});
    expect(got[0], isA<SegmentStart>());
    expect((got[0] as SegmentStart).info.channels.map((c) => c.name), ['O1', 'O2']);
    expect(got[1], isA<EegPacket>());
    expect(got[2], isA<GapEvent>());
    expect((got[2] as GapEvent).count, 4);
    expect(got[3], isA<EegPacket>());
    expect((got.last as DisconnectedEvent).reason, 'oddalil sie');
    expect(calls.map((c) => c.method), contains('stop'));
  });
}
