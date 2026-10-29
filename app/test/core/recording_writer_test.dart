import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/eeg/recording_writer.dart';
import 'package:neurotchi/core/eeg/replay_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';

void main() {
  test('nagranie zapisane z zrodla wraca przez Replay z lukami', () async {
    final dir = Directory.systemTemp.createTempSync('rec');
    final base = '${dir.path}/s';
    final mock = MockSource(duration: const Duration(seconds: 3), dropChunks: {10});
    final original = <StreamItem>[];
    final writer = RecordingWriter(base);
    final done = mock.items.asyncMap((i) async {
      original.add(i);
      await writer.add(i);
    }).drain<void>();
    await mock.start();
    await done;
    await writer.close();

    final rec = await Recording.load(base);
    expect(rec.info.fs, 250);
    expect([for (final c in rec.info.channels) c.name], ['O1', 'O2']);
    expect(rec.sampleNumbers.length, writer.samples);

    final replay = ReplaySource(rec);
    final back = <StreamItem>[];
    final d2 = replay.items.forEach(back.add);
    await replay.start();
    await d2;

    final a = original.whereType<EegPacket>().toList();
    final b = back.whereType<EegPacket>().toList();
    expect(b.length, a.length);
    for (var i = 0; i < a.length; i++) {
      expect(b[i].firstSample, a[i].firstSample);
      expect(b[i].samples, a[i].samples);
    }
    expect(back.whereType<GapEvent>().single.count, 25);
  });
}
