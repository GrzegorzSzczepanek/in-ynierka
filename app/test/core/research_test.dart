import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/db/app_database.dart';
import 'package:neurotchi/core/db/session_exporter.dart';
import 'package:neurotchi/core/db/session_persistence.dart';
import 'package:neurotchi/core/db/session_repository.dart';
import 'package:neurotchi/core/dsp/alpha_pipeline.dart';
import 'package:neurotchi/core/dsp/processing_config.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/research/latency.dart';
import 'package:neurotchi/core/research/research_monitor.dart';
import 'package:neurotchi/core/session/session_controller.dart';
import 'package:neurotchi/core/session/session_models.dart';

void main() {
  test('percentyle z interpolacja jak numpy', () {
    expect(percentileOf([1, 2, 3, 4], 50), 2.5);
    expect(percentileOf([1, 2, 3, 4, 5], 95), closeTo(4.8, 1e-9));
    expect(percentileOf([], 50).isNaN, isTrue);
  });

  test('raport opoznien sklada etapy i sume na okno', () {
    final r = LatencyReport.from(
      filterUs: [1000, 2000, 3000],
      qualityUs: [100, 100, 100],
      welchUs: [500, 500, 500],
      smoothUs: [10, 10, 10],
      stepMs: 256,
    );
    expect(r.windows, 3);
    expect(r.total.p50Ms, closeTo(2.61, 1e-9));
    expect(r.stages.firstWhere((s) => s.name == 'Filtracja').p50Ms, 2.0);
    expect(r.stages.firstWhere((s) => s.name == 'Okno analizy (krok)').p50Ms, 256);
    expect(r.stages.firstWhere((s) => s.name == 'Odbiór → bufor').hasData, isFalse);
  });

  test('potok zapisuje czasy etapow dla kazdego okna', () async {
    final timings = PipelineTimings();
    final pipe = AlphaPipeline(const ProcessingConfig(),
        trainingChannels: ['O1', 'O2'], timings: timings);
    final src = MockSource(duration: const Duration(seconds: 10));
    var windows = 0;
    final done = src.items.forEach((i) => windows += pipe.push(i).length);
    await src.start();
    await done;
    expect(windows, greaterThan(20));
    expect(timings.totalUs.length, windows);
    expect(timings.filterUs.length, windows);
    expect(timings.welchUs.length, windows);
    expect(timings.totalUs.every((u) => u > 0), isTrue);
  });

  test('monitor badacza: slady kanalow, os artefaktow i raport', () async {
    final m = ResearchMonitor(() => MockSource(
          duration: const Duration(seconds: 14),
          alphaAmplitudeUv: (_) => 15,
        ));
    await m.start();
    expect(m.fs, 250);
    expect(m.names.take(2), ['O1', 'O2']);
    final traces = m.traces;
    expect(traces.length, m.names.length);
    expect(traces.first.length, 10 * 250);
    expect(traces.first.any((v) => v.abs() > 5), isTrue);
    expect(m.validSeconds.length, closeTo(14, 1));
    expect(m.report.windows, greaterThan(30));
    expect(m.report.total.p50Ms, greaterThan(0));
    await m.stop();
  });

  test('test opoznien DSP daje raport bez danych odbioru i renderu', () async {
    final r = await ResearchMonitor.runTest(seconds: 20);
    expect(r.windows, greaterThan(50));
    expect(r.total.p50Ms, lessThan(500));
    expect(r.stages.firstWhere((s) => s.name == 'Welch PSD').hasData, isTrue);
    expect(r.stages.firstWhere((s) => s.name == 'Render (Flutter)').hasData, isFalse);
  });

  test('eksport sesji: TSV ze zdarzeniami i kopie surowych plikow', () async {
    final db = AppDatabase.inMemory();
    final repo = SessionRepository(db);
    final tmp = Directory.systemTemp.createTempSync('exp');
    const cfg = SessionConfig(
      calibrationS: 20,
      blocks: 2,
      blockS: 10,
      breakS: 4,
      contactSettleS: 1,
      contactStableS: 1,
      calibrationClosedS: 0,
    );
    final p = SessionPersistence.begin(
        repo: repo, config: cfg, sourceType: 'mock', appVersion: '0', rawDir: '${tmp.path}/raw');
    final c = SessionController(
      sourceFactory: () => MockSource(
        duration: const Duration(seconds: 120),
        alphaAmplitudeUv: (t) => t < 25 ? 10 : 30,
        noiseUv: 2,
        dropChunks: {400},
      ),
      config: cfg,
      onItem: p.onItem,
      delay: (_) async {},
    );
    await p.finish(await c.run());

    final files = SessionExporter(repo).export(p.sessionId, '${tmp.path}/out');
    final names = files.map((f) => f.path.split('/').last).toList();
    expect(names, containsAll(['S-0001_events.tsv', 'S-0001_seg1_raw.csv', 'S-0001_seg1_raw.json']));
    expect(files.every((f) => f.bytes > 0), isTrue);
    final tsv = File('${tmp.path}/out/S-0001_events.tsv').readAsStringSync();
    expect(tsv, contains('kalibracja\t1'));
    expect(tsv, contains('blok\t1'));
    expect(tsv, contains('blok\t2'));
    expect(tsv, contains('zdarzenie\t1'));
    expect(tsv, contains('luka\t1\t10000'));
    expect(tsv.split('\n').first, startsWith('typ\tnr'));
    expect(repo.exportableSessions().single.id, p.sessionId);
    db.close();
  });

  test('zatrzymanie monitora w trakcie strumienia nie rzuca wyjatku', () async {
    final m = ResearchMonitor(() => MockSource(duration: const Duration(seconds: 200)));
    final running = m.start();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await m.stop();
    await running;
    expect(m.elapsed, isNotNull);
  });
}
