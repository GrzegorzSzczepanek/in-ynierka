import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:neurotchi/core/db/app_database.dart';
import 'package:neurotchi/core/db/session_persistence.dart';
import 'package:neurotchi/core/db/session_repository.dart';
import 'package:neurotchi/core/dsp/alpha_pipeline.dart';
import 'package:neurotchi/core/dsp/calibration.dart' as cal;
import 'package:neurotchi/core/dsp/processing_config.dart';
import 'package:neurotchi/core/eeg/eeg_source.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/eeg/stream_item.dart';
import 'package:neurotchi/core/research/latency.dart';
import 'package:neurotchi/core/research/research_monitor.dart';
import 'package:neurotchi/core/session/session_controller.dart' show SourceFactory;
import 'package:neurotchi/core/session/session_models.dart';
import 'package:neurotchi/core/session/training_protocol.dart';
import 'package:neurotchi/core/settings/app_settings.dart';
import 'package:neurotchi/ui/app_services.dart';
import 'package:neurotchi/ui/neuronek/neuronek.dart';
import 'package:neurotchi/ui/screens/research_screen.dart';
import 'package:neurotchi/ui/screens/session_flow_screen.dart';
import 'package:neurotchi/ui/screens/training_screen.dart';
import 'package:neurotchi/ui/theme/pixel_theme.dart';
import 'package:neurotchi/ui/view_data.dart';

const _bench = String.fromEnvironment('BENCH', defaultValue: 'history,dsp,writer');
const _writerMinutes = int.fromEnvironment('WRITER_MIN', defaultValue: 60);
const _writerRealtime = bool.fromEnvironment('REALTIME');
const _writerChannels = int.fromEnvironment('WRITER_CH', defaultValue: 32);
const _trainingSeconds = int.fromEnvironment('TRAIN_S', defaultValue: 190);
const _latencySeconds = int.fromEnvironment('LAT_S', defaultValue: 120);

void _emit(String kind, Map<String, Object?> data) {
  final body = jsonEncode(data, toEncodable: (o) => o is double ? null : o.toString());
  const part = 700;
  final n = (body.length + part - 1) ~/ part;
  for (var i = 0; i < n; i++) {
    // ignore: avoid_print
    print('BENCH|$kind|$i/$n|${body.substring(i * part, min(body.length, (i + 1) * part))}');
  }
  try {
    File('${Directory.systemTemp.path}/bench_$kind.json').writeAsStringSync(
      jsonEncode(data, toEncodable: (o) => o is double ? null : o.toString()),
    );
  } catch (_) {}
}

Map<String, Object?> _stats(List<num> v, {int digits = 3}) {
  if (v.isEmpty) return {'n': 0};
  double r(double x) => double.parse(x.toStringAsFixed(digits));
  final sum = v.fold<double>(0, (a, b) => a + b);
  return {
    'n': v.length,
    'p50': r(percentileOf(v, 50)),
    'p95': r(percentileOf(v, 95)),
    'p99': r(percentileOf(v, 99)),
    'max': r(percentileOf(v, 100)),
    'mean': r(sum / v.length),
  };
}

Map<String, Object?> _env() {
  final d = ui.PlatformDispatcher.instance;
  final view = d.views.isEmpty ? null : d.views.first;
  return {
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'cpus': Platform.numberOfProcessors,
    'mode': const bool.fromEnvironment('dart.vm.product')
        ? 'release'
        : const bool.fromEnvironment('dart.vm.profile')
        ? 'profile'
        : 'debug',
    'refreshHz': view?.display.refreshRate,
    'physicalSize': view == null
        ? null
        : '${view.physicalSize.width.round()}x${view.physicalSize.height.round()}',
    'dpr': view?.devicePixelRatio,
  };
}

Future<void> _history() async {
  final dir = Directory.systemTemp.createTempSync('bench_hist');
  final database = AppDatabase.open('${dir.path}/bench.db');
  var clock = DateTime.utc(2026, 1, 1, 10);
  final repo = SessionRepository(database, now: () => clock);
  const cfg = SessionConfig();
  final rng = Random(5);
  final gen = Stopwatch()..start();
  const sessions = 200;
  for (var i = 0; i < sessions; i++) {
    clock = DateTime.utc(2026, 1, 1, 10).add(Duration(hours: i * 16));
    final id = repo.startSession(
      protocolId: repo.ensureProtocol(cfg.processing, name: cfg.protocol.dbName),
      sourceType: 'mock',
      plannedDurationS: cfg.plannedDurationS,
      appVersion: 'bench',
      channels: cfg.trainingChannels,
    );
    final blocks = [
      for (var b = 1; b <= 3; b++)
        BlockResult(
          blockNo: b,
          calibrationAttempt: 1,
          plannedS: 180,
          actualS: 180,
          threshold: 0.55,
          validSignalS: 140 + rng.nextInt(40).toDouble(),
          timeAboveThresholdS: 40 + rng.nextInt(60).toDouble(),
          rewardCount: 8 + rng.nextInt(10),
          events: [
            for (var e = 0; e < 12; e++) BlockEvent(5000 + e * 13000, 'reward'),
          ],
          invalid: [
            for (var k = 0; k < 6; k++)
              InvalidInterval(
                10000 + k * 25000,
                10000 + k * 25000 + 1500,
                InvalidReason.values[k % InvalidReason.values.length],
              ),
          ],
        ),
    ];
    repo.finishSession(
      id,
      SessionResult(
        status: SessionStatus.completed,
        calibrations: const [
          CalibrationRecord(
            1,
            60,
            cal.CalibrationResult(
              accepted: true,
              validRatio: 0.95,
              baseline: cal.Baseline(-1.0, 0.8),
              thresholdY: 0.55,
            ),
            validSignalS: 55,
            alphaRatio: 1.5,
            alphaPeakHz: 10.2,
          ),
        ],
        blocks: blocks,
        controlRatings: const {1: 3, 2: 4, 3: 4},
      ),
      actualDurationS: 700,
    );
  }
  final genMs = gen.elapsedMilliseconds;
  int count(String t) =>
      repo.db.select('SELECT COUNT(*) c FROM $t').first['c'] as int;
  final rows = {
    for (final t in [
      'sessions',
      'blocks',
      'block_events',
      'invalid_intervals',
      'session_stats',
      'calibrations',
    ])
      t: count(t),
  };
  final now = clock.add(const Duration(hours: 1));
  final measures = <String, void Function()>{
    'history()': () => repo.history(),
    'dailyStats()': () => repo.dailyStats(),
    'progressData() = dane ekranu Postep (wykresy + lista)': () =>
        progressData(repo, now),
    'homeData()': () => homeData(repo, trainingMinutes: 9, now: now),
    'totalValidMinutes()': () => repo.totalValidMinutes(),
  };
  final out = <String, Object?>{};
  for (final e in measures.entries) {
    final first = Stopwatch()..start();
    e.value();
    final coldMs = first.elapsedMicroseconds / 1000;
    for (var i = 0; i < 30; i++) {
      e.value();
    }
    final us = <int>[];
    for (var i = 0; i < 300; i++) {
      final sw = Stopwatch()..start();
      e.value();
      us.add(sw.elapsedMicroseconds);
    }
    out[e.key] = {
      'cold_ms': double.parse(coldMs.toStringAsFixed(3)),
      'ms': _stats([for (final u in us) u / 1000]),
    };
  }
  final hist = repo.history().length;
  _emit('history', {
    'env': _env(),
    'generateMs': genMs,
    'rows': rows,
    'historyRows': hist,
    'dbBytes': File('${dir.path}/bench.db').lengthSync(),
    'measures': out,
  });
  database.close();
  dir.deleteSync(recursive: true);
}

Future<void> _dsp() async {
  final results = <String, Object?>{};
  for (final channels in [
    ['O1', 'O2'],
    ['O1', 'O2', 'Oz', 'POz'],
  ]) {
    const seconds = 120;
    final src = MockSource(
      channels: [for (final n in channels) Channel(n)],
      duration: const Duration(seconds: seconds),
      alphaAmplitudeUv: (_) => 15,
      betaAmplitudeUv: (_) => 5,
    );
    final timings = PipelineTimings();
    final pipe = AlphaPipeline(
      const ProcessingConfig(),
      trainingChannels: channels,
      timings: timings,
    );
    final smooth = <int>[];
    cal.FeedbackMapper? mapper;
    var packetUs = <int>[];
    final done = src.items.forEach((i) {
      final sw = Stopwatch()..start();
      for (final w in pipe.push(i)) {
        final s2 = Stopwatch()..start();
        if (w.valid) {
          mapper ??= cal.FeedbackMapper(const ProcessingConfig(), cal.Baseline(w.feature!, 1));
          mapper!.push(w);
        }
        smooth.add(s2.elapsedMicroseconds);
      }
      if (i is EegPacket) packetUs.add(sw.elapsedMicroseconds);
    });
    await src.start();
    await done;
    final n = timings.filterUs.length;
    final totals = <int>[
      for (var i = 0; i < n; i++)
        timings.filterUs[i] +
            timings.qualityUs[i] +
            timings.welchUs[i] +
            (i < smooth.length ? smooth[i] : 0),
    ];
    List<double> ms(List<int> v) => [for (final u in v) u / 1000];
    results['${channels.length}ch'] = {
      'channels': channels,
      'windows': n,
      'filter_ms': _stats(ms(timings.filterUs)),
      'quality_ms': _stats(ms(timings.qualityUs)),
      'welch_ms': _stats(ms(timings.welchUs)),
      'smooth_ms': _stats(ms(smooth)),
      'total_dsp_ms': _stats(ms(totals)),
      'per_packet_ms': _stats(ms(packetUs)),
    };
  }
  final app = await ResearchMonitor.runTest(seconds: 30);
  results['runTest_30s_app'] = {
    'windows': app.windows,
    'stages': [
      for (final s in app.stages)
        {'name': s.name, 'p50_ms': s.p50Ms, 'p95_ms': s.p95Ms, 'n': s.n},
    ],
    'total': {'p50_ms': app.total.p50Ms, 'p95_ms': app.total.p95Ms},
  };
  _emit('dsp', {'env': _env(), 'results': results});
}

Future<void> _writer() async {
  final dir = Directory.systemTemp.createTempSync('bench_writer');
  final database = AppDatabase.inMemory();
  final repo = SessionRepository(database);
  final cfg = SessionConfig(trainingChannels: const ['ch1', 'ch2']);
  final p = SessionPersistence.begin(
    repo: repo,
    config: cfg,
    sourceType: 'mock',
    appVersion: 'bench',
    rawDir: dir.path,
  );
  final src = MockSource(
    channels: [for (var i = 1; i <= _writerChannels; i++) Channel('ch$i')],
    duration: Duration(minutes: _writerMinutes),
    realtime: _writerRealtime,
    alphaAmplitudeUv: (_) => 12,
    noiseUv: 3,
  );
  var sent = 0;
  var packets = 0;
  var sumFirst = 0.0;
  var sumLast = 0.0;
  var firstSample = -1;
  var nextExpected = 0;
  var sendDiscontinuities = 0;
  final lateUs = <int>[];
  final rss = <Object?>[];
  var maxRss = ProcessInfo.currentRss;
  final sw = Stopwatch();
  Timer? lag;
  final lagMs = <double>[];
  if (_writerRealtime) {
    final lagSw = Stopwatch()..start();
    var last = 0;
    lag = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final now = lagSw.elapsedMicroseconds;
      lagMs.add((now - last - 20000) / 1000);
      last = now;
    });
  }
  final done = src.items.forEach((item) {
    if (item is EegPacket) {
      if (firstSample < 0) firstSample = item.firstSample;
      if (item.firstSample != nextExpected) sendDiscontinuities++;
      nextExpected = item.firstSample + item.length;
      sent += item.length;
      packets++;
      for (var i = 0; i < item.length; i++) {
        sumFirst += item.samples.first[i];
        sumLast += item.samples.last[i];
      }
      if (_writerRealtime) {
        lateUs.add(sw.elapsedMicroseconds - (item.firstSample * 1000000 ~/ 250));
      }
      if (packets % 1500 == 0) {
        final r = ProcessInfo.currentRss;
        if (r > maxRss) maxRss = r;
        rss.add({'min_signal': packets * 25 ~/ 250 ~/ 60, 'rss_mb': r ~/ (1024 * 1024)});
      }
    }
    p.onItem(item);
  });
  sw.start();
  await src.start();
  await done;
  final streamMs = sw.elapsedMilliseconds;
  await p.finish(
    const SessionResult(
      status: SessionStatus.completed,
      calibrations: [],
      blocks: [],
    ),
  );
  lag?.cancel();
  final totalMs = sw.elapsedMilliseconds;
  final file = File('${dir.path}/session${p.sessionId}_seg1.csv');
  var rows = 0;
  var prev = -1;
  var discontinuities = 0;
  var badCols = 0;
  var first = -1;
  var csumFirst = 0.0;
  var csumLast = 0.0;
  var header = true;
  var headerCols = 0;
  await for (final line
      in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
    if (header) {
      header = false;
      headerCols = line.split(',').length;
      continue;
    }
    final parts = line.split(',');
    if (parts.length != _writerChannels + 1) badCols++;
    final sn = int.parse(parts[0]);
    if (first < 0) first = sn;
    if (prev >= 0 && sn != prev + 1) discontinuities++;
    prev = sn;
    csumFirst += double.parse(parts[1]);
    csumLast += double.parse(parts.last);
    rows++;
  }
  final seg = repo.db.select(
    'SELECT fs_nominal_hz, fs_measured_hz, end_reason, raw_file_path FROM segments',
  );
  _emit('writer', {
    'env': _env(),
    'minutesSignal': _writerMinutes,
    'realtime': _writerRealtime,
    'channels': _writerChannels,
    'fsNominal': 250,
    'packetsSent': packets,
    'samplesSent': sent,
    'rowsInCsv': rows,
    'equal': rows == sent,
    'firstSampleSent': firstSample,
    'firstSampleInFile': first,
    'lastSampleInFile': prev,
    'discontinuitiesSent': sendDiscontinuities,
    'discontinuitiesInFile': discontinuities,
    'rowsWithWrongColumnCount': badCols,
    'headerColumns': headerCols,
    'checksumEqual': sumFirst == csumFirst && sumLast == csumLast,
    'streamMs': streamMs,
    'totalMsWithClose': totalMs,
    'speedup': _writerRealtime ? 1.0 : _writerMinutes * 60000 / totalMs,
    'fileBytes': file.lengthSync(),
    'maxRssMb': maxRss ~/ (1024 * 1024),
    'rssAtEndMb': ProcessInfo.currentRss ~/ (1024 * 1024),
    'rssTimeline': rss.length > 12 ? [for (var i = 0; i < rss.length; i += rss.length ~/ 12) rss[i]] : rss,
    'dbSegment': [
      for (final r in seg)
        {
          'fs_measured_hz': r['fs_measured_hz'],
          'end_reason': r['end_reason'],
        },
    ],
    if (_writerRealtime) 'deliveryLate_ms': _stats([for (final u in lateUs) u / 1000]),
    if (_writerRealtime) 'eventLoopLag20msTimer_ms': _stats(lagMs),
  });
  dir.deleteSync(recursive: true);
}

class _StampingSource implements EegSource {
  _StampingSource(this.inner);

  final EegSource inner;
  static final clock = Stopwatch()..start();
  static int? unseenUs;
  static int packets = 0;

  @override
  Stream<StreamItem> get items => inner.items.map((i) {
    if (i is EegPacket) {
      packets++;
      unseenUs ??= clock.elapsedMicroseconds;
    }
    return i;
  });

  @override
  Future<void> start() => inner.start();

  @override
  Future<void> stop() => inner.stop();
}

class _Spy extends ResearchMonitor {
  _Spy(super.sourceFactory);

  final renders = <int>[];

  @override
  void recordRender(int us) {
    renders.add(us);
    super.recordRender(us);
  }
}

AppServices _services(SourceFactory? factory, SessionConfig? cfg) {
  final database = AppDatabase.inMemory();
  final repo = SessionRepository(database);
  AppSettings(showInstruction: false, checkUpdates: false).save(repo);
  final raw = Directory.systemTemp.createTempSync('bench_raw').path;
  return AppServices(
    repository: repo,
    rawDir: raw,
    sourceFactory: factory,
    configOverride: cfg,
    appVersion: 'bench',
  );
}

MockSource _demoMock() => MockSource(
  realtime: true,
  alphaAmplitudeUv: (t) => 12 + 10 * (t > 90 ? 1 : 0),
  betaAmplitudeUv: (t) => 4 + 6 * (t > 90 ? 1 : 0),
  contactAt: (t) => t > 3,
);

String lastScreen = '';

bool _trainingVisible() {
  var found = false;
  void visit(Element e) {
    if (found) return;
    final w = e.widget;
    final n = w.runtimeType.toString();
    if (n.endsWith('Screen')) lastScreen = n;
    if (w is TrainingScreen) {
      final s = w.snapshot;
      found = s.phase == SessionPhase.training && !s.paused;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

class _Frame {
  _Frame(this.vsyncUs, this.buildUs, this.rasterUs, this.totalUs);

  final int vsyncUs;
  final int buildUs;
  final int rasterUs;
  final int totalUs;
}

void _fps() {
  final frames = <_Frame>[];
  final e2e = <int>[];
  var training = false;
  var trainingSince = 0;
  var rssStart = 0;
  var rssEnd = 0;
  var finished = false;
  final all = Stopwatch()..start();
  var packetsAtStart = 0;
  var packetsAtEnd = 0;

  SchedulerBinding.instance.addTimingsCallback((timings) {
    if (!training) return;
    for (final t in timings) {
      frames.add(
        _Frame(
          t.timestampInMicroseconds(ui.FramePhase.vsyncStart),
          t.buildDuration.inMicroseconds,
          t.rasterDuration.inMicroseconds,
          t.totalSpan.inMicroseconds,
        ),
      );
    }
  });
  SchedulerBinding.instance.addPersistentFrameCallback((_) {
    if (!training) {
      _StampingSource.unseenUs = null;
      return;
    }
    final u = _StampingSource.unseenUs;
    if (u != null) {
      e2e.add(_StampingSource.clock.elapsedMicroseconds - u);
      _StampingSource.unseenUs = null;
    }
  });

  void finish() {
    if (finished) return;
    finished = true;
    final bucket = frames.length > 20 ? frames.sublist(10, frames.length - 10) : frames;
    final spanS = bucket.length < 2
        ? 0.0
        : (bucket.last.vsyncUs - bucket.first.vsyncUs) / 1e6;
    List<double> ms(Iterable<int> v) => [for (final u in v) u / 1000];
    int over(Iterable<int> v, double limitMs) =>
        v.where((u) => u / 1000 > limitMs).length;
    final build = bucket.map((f) => f.buildUs).toList();
    final raster = bucket.map((f) => f.rasterUs).toList();
    final total = bucket.map((f) => f.totalUs).toList();
    final worst = [
      for (final f in bucket) max(f.buildUs, f.rasterUs),
    ];
    final refresh = ui.PlatformDispatcher.instance.views.first.display.refreshRate;
    final budget = 1000 / refresh;
    _emit('fps', {
      'env': _env(),
      'trainingWindowS': double.parse(spanS.toStringAsFixed(1)),
      'framesInWindow': bucket.length,
      'fps': spanS > 0 ? double.parse((bucket.length / spanS).toStringAsFixed(2)) : null,
      'packetsInWindow': packetsAtEnd - packetsAtStart,
      'build_ms': _stats(ms(build)),
      'raster_ms': _stats(ms(raster)),
      'totalSpan_ms': _stats(ms(total)),
      'pctBuildOver16_7': double.parse((100 * over(build, 16.7) / bucket.length).toStringAsFixed(2)),
      'pctRasterOver16_7': double.parse((100 * over(raster, 16.7) / bucket.length).toStringAsFixed(2)),
      'pctMaxBuildRasterOver16_7': double.parse((100 * over(worst, 16.7) / bucket.length).toStringAsFixed(2)),
      'pctTotalSpanOver16_7': double.parse((100 * over(total, 16.7) / bucket.length).toStringAsFixed(2)),
      'pctTotalSpanOverRefreshBudget': double.parse((100 * over(total, budget) / bucket.length).toStringAsFixed(2)),
      'refreshBudgetMs': double.parse(budget.toStringAsFixed(2)),
      'packetToFrameUi_ms': _stats(ms(e2e)),
      'rssStartMb': rssStart ~/ (1024 * 1024),
      'rssEndMb': rssEnd ~/ (1024 * 1024),
    });
    exit(0);
  }

  Timer.periodic(const Duration(milliseconds: 250), (t) {
    final vis = _trainingVisible();
    if (vis && !training) {
      training = true;
      trainingSince = all.elapsedMilliseconds;
      rssStart = ProcessInfo.currentRss;
      packetsAtStart = _StampingSource.packets;
    }
    if (training && (!vis || all.elapsedMilliseconds - trainingSince > (_trainingSeconds + 5) * 1000)) {
      training = false;
      rssEnd = ProcessInfo.currentRss;
      packetsAtEnd = _StampingSource.packets;
      t.cancel();
      finish();
    }
    if (all.elapsed.inSeconds > _trainingSeconds + 240) {
      _emit('fps', {'error': 'timeout, trening nie zostal wykryty lub nie skonczyl sie'});
      exit(2);
    }
  });
}

Future<void> _latency() async {
  final spy = _Spy(() => _StampingSource(_demoMock()));
  unawaited(spy.start());
  final services = _services(null, null);
  runApp(
    ServicesScope(
      services: services,
      child: MaterialApp(
        theme: Px.theme,
        debugShowCheckedModeBanner: false,
        home: ResearchScreen(monitor: spy),
      ),
    ),
  );
  final frames = <_Frame>[];
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      frames.add(
        _Frame(
          t.timestampInMicroseconds(ui.FramePhase.vsyncStart),
          t.buildDuration.inMicroseconds,
          t.rasterDuration.inMicroseconds,
          t.totalSpan.inMicroseconds,
        ),
      );
    }
  });
  await Future<void>.delayed(const Duration(seconds: _latencySeconds));
  final t = spy.timings;
  final n = t.filterUs.length;
  List<double> ms(Iterable<int> v) => [for (final u in v) u / 1000];
  final report = spy.report;
  final bucket = frames.length > 20 ? frames.sublist(10) : frames;
  await spy.stop();
  _emit('latency', {
    'env': _env(),
    'liveSeconds': _latencySeconds,
    'windows': n,
    'live_filter_ms': _stats(ms(t.filterUs)),
    'live_quality_ms': _stats(ms(t.qualityUs)),
    'live_welch_ms': _stats(ms(t.welchUs)),
    'live_total_dsp_ms': _stats(ms(t.totalUs)),
    'render_setState_to_postFrame_ms': _stats(ms(spy.renders)),
    'frame_build_ms': _stats(ms(bucket.map((f) => f.buildUs))),
    'frame_raster_ms': _stats(ms(bucket.map((f) => f.rasterUs))),
    'appReport': {
      for (final s in report.stages)
        s.name: {'p50_ms': s.p50Ms, 'p95_ms': s.p95Ms, 'n': s.n},
      'Razem DSP': {'p50_ms': report.total.p50Ms, 'p95_ms': report.total.p95Ms, 'n': report.total.n},
    },
  });
  exit(0);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final modes = _bench.split(',');
  final ui_ = modes.contains('fps') || modes.contains('latency');
  if (!ui_) {
    runApp(const SizedBox.shrink());
    for (final m in modes) {
      switch (m) {
        case 'history':
          await _history();
        case 'dsp':
          await _dsp();
        case 'writer':
          await _writer();
      }
    }
    _emit('done', {'modes': modes});
    exit(0);
  }
  await NeuronekSprites.load();
  if (modes.contains('latency')) {
    await _latency();
    return;
  }
  final cfg = SessionConfig(
    calibrationS: 20,
    calibrationMaxS: 40,
    calibrationClosedS: 0,
    contactSettleS: 1,
    contactStableS: 1,
    blocks: 1,
    blockS: _trainingSeconds.toDouble(),
  );
  final services = _services(() => _StampingSource(_demoMock()), cfg);
  runApp(
    ServicesScope(
      services: services,
      child: MaterialApp(
        theme: Px.theme,
        debugShowCheckedModeBanner: false,
        home: const SessionFlowScreen(protocol: TrainingProtocol.alfa),
      ),
    ),
  );
  _fps();
}
