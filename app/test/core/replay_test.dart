import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/eeg/replay_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';

void main() {
  const info = StreamInfo(
    sourceId: 'replay',
    fs: 250,
    channels: [Channel('O1'), Channel('O2')],
    chunkSize: 25,
  );

  test('odtwarzanie dzieli nagranie na paczki i zglasza luki', () async {
    final sn = [for (var i = 0; i < 50; i++) i, for (var i = 100; i < 150; i++) i];
    final rec = Recording(info, sn, [
      [for (final n in sn) n.toDouble()],
      [for (final n in sn) -n.toDouble()],
    ]);
    final src = ReplaySource(rec);
    final items = <StreamItem>[];
    final done = src.items.forEach(items.add);
    await src.start();
    await done;

    expect(items.first, isA<SegmentStart>());
    final packets = items.whereType<EegPacket>().toList();
    expect([for (final p in packets) p.firstSample], [0, 25, 100, 125]);
    expect(packets.every((p) => p.length == 25), isTrue);
    final gap = items.whereType<GapEvent>().single;
    expect((gap.firstSample, gap.count), (50, 50));
    expect(items.indexOf(gap), 3);
  });

  test('zapis i odczyt nagrania w formacie CSV z metadanymi', () {
    final rec = Recording(info, [0, 1, 2], [
      [1.5, 2.5, 3.5],
      [-1.0, 0.0, 1.0],
    ]);
    final back = Recording.parse(info, rec.csvLines());
    expect(back.sampleNumbers, [0, 1, 2]);
    expect(back.data[0], [1.5, 2.5, 3.5]);
    expect(back.data[1], [-1.0, 0.0, 1.0]);
    expect(rec.metaJson()['fs'], 250);
  });
}
