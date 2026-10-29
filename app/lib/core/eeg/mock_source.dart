import 'dart:async';
import 'dart:math';

import 'eeg_source.dart';
import 'stream_item.dart';

class MockSource implements EegSource {
  MockSource({
    this.fs = 250,
    this.chunkSize = 25,
    this.channels = const [Channel('O1'), Channel('O2')],
    this.duration,
    this.realtime = false,
    this.alphaAmplitudeUv = _defaultAmplitude,
    this.alphaHz = 10.0,
    this.noiseUv = 3.0,
    this.dropChunks = const {},
    this.disconnectAfterChunk,
    this.contactAt,
    this.seed = 1,
  });

  static double _defaultAmplitude(double t) => 10.0;

  final int fs;
  final int chunkSize;
  final List<Channel> channels;
  final Duration? duration;
  final bool realtime;
  final double Function(double t) alphaAmplitudeUv;
  final double alphaHz;
  final double noiseUv;

  /// Numery paczek (od 0), ktore zrodlo pomija, tworzac luke w numeracji.
  final Set<int> dropChunks;

  /// Po tej paczce zrodlo wysyla [DisconnectedEvent] i zamyka strumien.
  final int? disconnectAfterChunk;

  /// Kontakt elektrod w czasie t. Gdy brak, paczki nie niosa kontaktu.
  final bool Function(double t)? contactAt;
  final int seed;

  final _controller = StreamController<StreamItem>();
  bool _running = false;

  @override
  Stream<StreamItem> get items => _controller.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    _running = true;
    unawaited(_run());
  }

  @override
  Future<void> stop() async {
    _running = false;
  }

  Future<void> _run() async {
    final rng = Random(seed);
    final total = duration == null
        ? null
        : (duration!.inMicroseconds * fs / 1e6 / chunkSize).round();
    _controller.add(SegmentStart(StreamInfo(
      sourceId: 'mock',
      fs: fs,
      channels: channels,
      chunkSize: chunkSize,
    )));
    final period = Duration(microseconds: (chunkSize * 1e6 / fs).round());
    final clock = Stopwatch()..start();
    var n = 0;
    var lastDropped = false;
    while (_running && (total == null || n < total)) {
      if (disconnectAfterChunk != null && n >= disconnectAfterChunk!) {
        _controller.add(DisconnectedEvent(reason: 'mock', tRecv: n * chunkSize / fs));
        break;
      }
      final first = n * chunkSize;
      if (dropChunks.contains(n)) {
        lastDropped = true;
      } else {
        if (lastDropped) {
          _controller.add(GapEvent(firstSample: first - chunkSize, count: chunkSize));
          lastDropped = false;
        }
        _controller.add(EegPacket(
          firstSample: first,
          tRecv: first / fs,
          contact: contactAt == null
              ? null
              : [
                  for (var c = 0; c < channels.length; c++)
                    [
                      for (var i = 0; i < chunkSize; i++)
                        contactAt!((first + i) / fs),
                    ],
                ],
          samples: [
            for (var c = 0; c < channels.length; c++)
              [
                for (var i = 0; i < chunkSize; i++)
                  _sample((first + i) / fs, c, rng),
              ],
          ],
        ));
      }
      n++;
      if (realtime) {
        final wait = period * n - clock.elapsed;
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      } else if (n % 50 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    await _controller.close();
  }

  double _sample(double t, int channel, Random rng) {
    final a = alphaAmplitudeUv(t);
    final noise = (rng.nextDouble() * 2 - 1) * noiseUv * sqrt(3);
    return a * sin(2 * pi * alphaHz * t + channel * 0.3) + noise;
  }
}
