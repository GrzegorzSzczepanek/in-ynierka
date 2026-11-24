import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/db/app_database.dart';
import 'package:neurotchi/core/db/schema.dart';
import 'package:neurotchi/core/dsp/alpha_pipeline.dart';
import 'package:neurotchi/core/dsp/biquad.dart';
import 'package:neurotchi/core/dsp/processing_config.dart';
import 'package:neurotchi/core/dsp/welch.dart';
import 'package:neurotchi/core/eeg/eeg_source.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';
import 'package:neurotchi/core/session/session_controller.dart';
import 'package:neurotchi/core/session/session_models.dart';

class _Failing implements EegSource {
  final _c = StreamController<StreamItem>();

  @override
  Stream<StreamItem> get items => _c.stream;

  @override
  Future<void> start() async {
    _c.add(const DisconnectedEvent(reason: 'connect_failed:1', tRecv: 0));
    unawaited(_c.close());
  }

  @override
  Future<void> stop() async {}
}

void main() {
  test('stale potoku DSP z pracy (ProcessingConfig i AlphaPipeline)', () {
    const c = ProcessingConfig();
    expect(c.filterType, 'butterworth');
    expect(c.filterOrder, 4);
    expect(c.filterLowHz, 3.0);
    expect(c.filterHighHz, 40.0);
    expect(c.notchHz, 50.0);
    expect(c.windowS, 2.0);
    expect(c.stepSamples, 64);
    expect(c.welchSegmentS, 1.0);
    expect(c.welchOverlap, 0.5);
    expect(c.alphaLowHz, 8.0);
    expect(c.alphaHighHz, 12.0);
    expect(c.eps, 1e-6);
    expect(c.p0, 1.0);
    expect(c.sMin, 0.05);
    expect(c.madScale, 1.4826);
    expect(c.mapA, -2.0);
    expect(c.mapB, 2.0);
    expect(c.smoothingLambda, 0.1);
    expect(c.thresholdPercentile, 60.0);
    expect(c.holdTimeS, 1.5);
    expect(c.ampThresholdUv, 100.0);
    expect(c.hfRatioThreshold, 0.25);
    expect(c.warmupSkipS, 5.0);
    expect(c.calibMinValidRatio, 0.9);
    final p = AlphaPipeline(c, trainingChannels: const ['O1']);
    expect(p.saturationUv, 562000.0);
    expect(p.flatRangeUv, 0.5);
  });

  test('stale sesji z pracy (SessionConfig)', () {
    const c = SessionConfig();
    expect(c.calibrationS, 60);
    expect(c.calibrationClosedS, 30);
    expect(c.calibrationMaxS, 150);
    expect(c.blocks, 3);
    expect(c.blockS, 180);
    expect(c.breakS, 30);
    expect(c.contactSettleS, 5);
    expect(c.contactStableS, 2);
    expect(c.connectAttempts, 3);
    expect(c.reconnectAttempts, 3);
    expect(c.reconnectIntervalS, 15);
    expect(c.alphaReactivityMin, 1.2);
    expect(c.maxClosedRepeats, 2);
    expect(c.plannedDurationS, 60 + 3 * 180 + 2 * 30);
  });

  test('schemat: wersja, stadia awatara i ustawienia domyslne w nowej bazie', () {
    expect(schemaVersion, 3);
    final db = AppDatabase.inMemory();
    expect(db.db.select('PRAGMA user_version').first.values.first, 3);
    final stages = db.db.select(
      'SELECT name, required_valid_minutes FROM avatar_stages ORDER BY sort_order',
    );
    expect([for (final r in stages) r['required_valid_minutes']], [
      0,
      10,
      30,
      60,
      100,
      150,
    ]);
    final cols = db.db
        .select('PRAGMA table_info(sessions)')
        .map((r) => r['name'])
        .toList();
    expect(cols, isNot(contains('mood_after')));
    final s = {
      for (final r in db.db.select('SELECT key, value FROM settings'))
        r['key']: r['value'],
    };
    expect(s['default_calibration_s'], '60');
    expect(s['default_blocks'], '3');
    expect(s['default_block_s'], '180');
    expect(s['default_break_s'], '30');
    db.close();
  });

  test('potok liczy ceche zgodnie z reczna implementacja: Welch 250/125/512, alfa 8-12 Hz', () {
    final rng = Random(3);
    const fs = 250;
    final filter = SosFilter.bandpass(
      fs: 250,
      lowHz: 3,
      highHz: 40,
      order: 4,
      notchHz: 50,
    );
    final filter2 = SosFilter.bandpass(
      fs: 250,
      lowHz: 3,
      highHz: 40,
      order: 4,
      notchHz: 50,
    );
    final pipe = AlphaPipeline(
      const ProcessingConfig(),
      trainingChannels: const ['A', 'B'],
    );
    pipe.push(
      const SegmentStart(
        StreamInfo(
          sourceId: 't',
          fs: fs,
          channels: [Channel('A'), Channel('B')],
          chunkSize: 25,
        ),
      ),
    );
    final fa = <double>[], fb = <double>[];
    final results = <WindowResult>[];
    for (var k = 0; k < 120; k++) {
      final a = <double>[], b = <double>[];
      for (var i = 0; i < 25; i++) {
        final n = k * 25 + i;
        a.add(12 * sin(2 * pi * 10 * n / fs) + (rng.nextDouble() - 0.5) * 8);
        b.add(9 * sin(2 * pi * 9.5 * n / fs + 1) + (rng.nextDouble() - 0.5) * 8);
      }
      for (final v in a) {
        fa.add(filter.process(v));
      }
      for (final v in b) {
        fb.add(filter2.process(v));
      }
      results.addAll(
        pipe.push(EegPacket(firstSample: k * 25, tRecv: 0, samples: [a, b])),
      );
    }
    final welch = Welch(fs: 250, segment: 250, overlap: 125, nfft: 512);
    expect(results.length, greaterThan(10));
    var worst = 0.0;
    for (var w = 0; w < results.length; w++) {
      if (!results[w].valid) continue;
      double f(List<double> x) {
        final alpha = welch.bandPower(welch.psd(x), 8, 12);
        return log((alpha + 1e-6) / 1.0);
      }
      final end = results[w].sampleEnd;
      final manual =
          (f(fa.sublist(end - 500, end)) + f(fb.sublist(end - 500, end))) / 2;
      worst = max(worst, (manual - results[w].feature!).abs());
    }
    // ignore: avoid_print
    print('cecha potoku vs reczna implementacja: max roznica $worst, okna ${results.length}');
    expect(worst, lessThan(1e-12));
  });

  test('ponowne laczenie: 3 proby, odstep 15 s przed kazda proba, potem reczne ponowienie', () async {
    final delays = <Duration>[];
    var starts = 0;
    late SessionController c;
    c = SessionController(
      sourceFactory: () {
        starts++;
        if (starts == 1) {
          return MockSource(
            duration: const Duration(seconds: 100),
            alphaAmplitudeUv: (_) => 20,
            noiseUv: 2,
            disconnectAfterChunk: 300,
          );
        }
        if (starts <= 4) return _Failing();
        return MockSource(
          duration: const Duration(seconds: 100),
          alphaAmplitudeUv: (_) => 20,
          noiseUv: 2,
        );
      },
      config: const SessionConfig(
        calibrationS: 20,
        blocks: 1,
        blockS: 10,
        breakS: 4,
        contactSettleS: 1,
        contactStableS: 1,
        calibrationClosedS: 0,
      ),
      delay: (d) async => delays.add(d),
    );
    final phases = <SessionPhase>[];
    var retried = false;
    c.snapshots.listen((s) {
      if (phases.isEmpty || phases.last != s.phase) phases.add(s.phase);
      if (s.phase == SessionPhase.connectionLost && !retried) {
        retried = true;
        c.retry();
      }
    });
    final r = await c.run();
    expect(delays, everyElement(const Duration(seconds: 15)));
    expect(delays.length, 3 + 1);
    expect(starts, 5);
    expect(phases, contains(SessionPhase.connectionLost));
    expect(r.status, SessionStatus.completed);
    // ignore: avoid_print
    print(
      'WF-9: odstepy przed probami=${[for (final d in delays) d.inSeconds]}, '
      'fabryka wywolana $starts razy, reczne ponowienie po 3 nieudanych probach',
    );
  });
}
