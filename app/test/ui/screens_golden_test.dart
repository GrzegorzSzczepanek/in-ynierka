import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/db/session_repository.dart';
import 'package:neurotchi/core/dsp/alpha_pipeline.dart';
import 'package:neurotchi/core/dsp/calibration.dart' as cal;
import 'package:neurotchi/core/session/session_models.dart';
import 'package:neurotchi/core/session/training_protocol.dart';
import 'package:neurotchi/ui/screens/calibration_hub_screen.dart';
import 'package:neurotchi/ui/screens/calibration_screen.dart';
import 'package:neurotchi/ui/screens/connection_screen.dart';
import 'package:neurotchi/ui/screens/home_screen.dart';
import 'package:neurotchi/ui/screens/progress_screen.dart';
import 'package:neurotchi/ui/screens/summary_screen.dart';
import 'package:neurotchi/ui/screens/training_screen.dart';

import 'package:neurotchi/core/db/app_database.dart';
import 'package:neurotchi/core/eeg/mock_source.dart';
import 'package:neurotchi/core/research/latency.dart';
import 'package:neurotchi/core/research/research_monitor.dart';
import 'package:neurotchi/ui/app_services.dart';
import 'package:neurotchi/core/settings/app_settings.dart';
import 'package:neurotchi/ui/screens/research_screen.dart';
import 'package:neurotchi/ui/screens/settings_screen.dart';

import '../support/golden_support.dart';

void noop() {}

void _ignore(TrainingProtocol _) {}

void _rate(int _) {}

Future<void> golden(WidgetTester t, String name, Widget screen) async {
  await pumpScreen(t, screen);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../goldens/$name.png'));
}

void main() {
  testWidgets('dom', (t) => golden(t, 'dom', const HomeScreen(
        data: HomeData(
          stageNo: 3,
          stageName: 'dwa neurony',
          trainingMinutes: 9,
          energy: 0.7,
          focus: 0.48,
          streakDays: 3,
        ),
        selected: TrainingProtocol.alfa,
        onSelect: _ignore,
        onStart: noop,
        onProgress: noop,
        onConnection: noop,
        onCalibration: noop,
        onResearch: noop,
      )));

  testWidgets('dom: desktop', (t) async {
    await pumpScreen(
      t,
      HomeScreen(
        data: const HomeData(
          stageNo: 3,
          stageName: 'dwa neurony',
          trainingMinutes: 9,
          energy: 0.7,
          focus: 0.48,
          streakDays: 3,
        ),
        selected: TrainingProtocol.alfa,
        onSelect: _ignore,
        onStart: noop,
        onProgress: noop,
        onConnection: noop,
        onCalibration: noop,
        onResearch: noop,
        animated: false,
      ),
      size: const Size(1200, 760),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../goldens/dom_desktop.png'));
  });

  testWidgets('dom: skupienie', (t) => golden(t, 'dom_skupienie', const HomeScreen(
        data: HomeData(stageNo: 2, stageName: 'neuron', trainingMinutes: 9),
        selected: TrainingProtocol.skupienie,
        onSelect: _ignore,
        onStart: noop,
        onProgress: noop,
      )));

  testWidgets('polaczenie: kontakt', (t) => golden(t, 'polaczenie', ConnectionScreen(
        snapshot: SessionSnapshot(
          phase: SessionPhase.contactCheck,
          phaseElapsedS: 3,
          contact: [
            for (var i = 1; i <= 32; i++)
              ChannelContact(i == 3 ? 'O1' : i == 4 ? 'O2' : 'ch$i', i != 3 && i % 2 == 0 || i == 4),
          ],
        ),
        trainingChannels: const ['O1', 'O2'],
        maxAttempts: 3,
        onFinish: noop,
        onUseContactChannels: noop,
      )));

  testWidgets('polaczenie: utracone', (t) => golden(t, 'polaczenie_utracone', ConnectionScreen(
        snapshot: const SessionSnapshot(
            phase: SessionPhase.connectionLost, phaseElapsedS: 0, attempt: 3, error: 'Nie znaleziono czepka BA MAXI 012'),
        trainingChannels: const ['O1', 'O2'],
        maxAttempts: 3,
        onFinish: noop,
        onRetry: noop,
      )));

  testWidgets('kalibracja: oczy zamkniete', (t) => golden(t, 'kalibracja', CalibrationScreen(
        snapshot: const SessionSnapshot(
          phase: SessionPhase.calibratingClosed,
          phaseElapsedS: 12,
          phaseDurationS: 30,
          attempt: 1,
          signalQuality: 0.9,
          threshold: 0.6,
          canSkipCalibration: true,
        ),
        onFinish: noop,
        onSkip: noop,
      )));

  testWidgets('kalibracja: wynik', (t) => golden(t, 'kalibracja_wynik', const CalibrationScreen(
        snapshot: SessionSnapshot(
          phase: SessionPhase.calibrationResult,
          phaseElapsedS: 1,
          phaseDurationS: 4,
          attempt: 1,
          signalQuality: 0.9,
          threshold: 0.6,
          alphaRatio: 2.4,
          alphaPeakHz: 10.1,
        ),
        onFinish: noop,
      )));

  testWidgets('trening: w celu', (t) => golden(t, 'trening', const TrainingScreen(
        snapshot: SessionSnapshot(
          phase: SessionPhase.training,
          phaseElapsedS: 68,
          phaseDurationS: 180,
          blockNo: 2,
          blocksTotal: 3,
          threshold: 0.6,
          feedback: cal.FeedbackSample(valid: true, y: 0.72),
          signalQuality: 0.95,
        ),
        history: [0.4, 0.45, 0.5, 0.48, 0.55, 0.6, 0.58, 0.66, 0.7, 0.72],
        log: [
          TrainingLogEntry('01:17', 'Nagroda'),
          TrainingLogEntry('02:41', 'Próg 0,60, sygnał: dobry'),
        ],
        onFinish: noop,
        onPause: noop,
      )));

  testWidgets('trening: pauza', (t) => golden(t, 'trening_pauza', const TrainingScreen(
        snapshot: SessionSnapshot(
          phase: SessionPhase.training,
          phaseElapsedS: 68,
          phaseDurationS: 180,
          blockNo: 2,
          blocksTotal: 3,
          threshold: 0.6,
          paused: true,
          feedback: cal.FeedbackSample(valid: true, y: 0.7),
          signalQuality: 0.95,
        ),
        log: [],
        onFinish: noop,
        onPause: noop,
        onResume: noop,
      )));

  testWidgets('trening: artefakt', (t) => golden(t, 'trening_artefakt', const TrainingScreen(
        snapshot: SessionSnapshot(
          phase: SessionPhase.training,
          phaseElapsedS: 90,
          phaseDurationS: 180,
          blockNo: 2,
          blocksTotal: 3,
          threshold: 0.6,
          feedback: cal.FeedbackSample(valid: false, y: 0.5),
          lastInvalid: InvalidReason.amplitude,
          signalQuality: 0.3,
        ),
        log: [TrainingLogEntry('01:30', 'Artefakt ruchowy')],
        onFinish: noop,
      )));

  testWidgets('trening: przerwa', (t) => golden(t, 'trening_przerwa', const TrainingScreen(
        snapshot: SessionSnapshot(
          phase: SessionPhase.breakBetweenBlocks,
          phaseElapsedS: 8,
          phaseDurationS: 30,
          blockNo: 1,
          blocksTotal: 3,
          threshold: 0.6,
          controlRating: 4,
        ),
        log: [],
        onFinish: noop,
        onRate: _rate,
      )));

  testWidgets('podsumowanie', (t) {
    final blocks = [
      for (var i = 1; i <= 3; i++)
        BlockResult(
          blockNo: i,
          calibrationAttempt: 1,
          plannedS: 180,
          actualS: 180,
          threshold: 0.6,
          validSignalS: 170.0 + i * 2,
          timeAboveThresholdS: 60.0 + i * 12,
          rewardCount: i + 1,
          meanY: 0.35 + i * 0.13,
          yTrace: [for (var k = 0; k < 6; k++) 0.3 + i * 0.1 + k * 0.04],
          windowsTotal: 150,
          windowsInvalid: i == 2 ? 11 : 0,
          events: const [],
          invalid: i == 2
              ? const [
                  InvalidInterval(20000, 24000, InvalidReason.amplitude),
                  InvalidInterval(80000, 83000, InvalidReason.muscle),
                ]
              : const [],
        ),
    ];
    return golden(t, 'podsumowanie', SummaryScreen(
      result: SessionResult(
        status: SessionStatus.completed,
        calibrations: const [
          CalibrationRecord(1, 60, cal.CalibrationResult(accepted: true, validRatio: 0.95)),
        ],
        blocks: blocks,
        controlRatings: const {1: 2, 2: 3, 3: 4},
      ),
      recent: [
        for (var i = 0; i < 5; i++)
          SessionRow(id: i, createdAt: DateTime(2026, 10, 20 + i), status: 'completed', validMinutes: 6.0 + i, blocksTotal: 3),
      ],
      onDone: noop,
    ));
  });

  testWidgets('postep', (t) => golden(t, 'postep', ProgressScreen(
        todayIndex: 3,
        onBack: noop,
        data: ProgressData(
          totalMinutes: 16,
          stages: const [
            AvatarStage('soma', 0, 1),
            AvatarStage('neuron', 10, 2),
            AvatarStage('dwa neurony', 30, 3),
            AvatarStage('mala siec', 60, 4),
          ],
          currentIndex: 1,
          week: const [true, false, true, false, false, false, false],
          recent: [
            for (var i = 0; i < 4; i++)
              SessionRow(id: i, createdAt: DateTime(2026, 10, 27 - i), status: 'completed', validMinutes: 8.5 - i, blocksTotal: 3),
          ],
        ),
      )));

  testWidgets('kalibracja: ostatni wynik', (t) => golden(t, 'kalibracja_hub', CalibrationHubScreen(
        protocol: TrainingProtocol.alfa,
        stored: StoredCalibration(
          baseline: const cal.Baseline(3.1, 0.45),
          thresholdY: 0.58,
          alphaRatio: 2.4,
          alphaPeakHz: 10.1,
          createdAt: DateTime(2026, 10, 27),
        ),
        onCalibrate: noop,
        onBack: noop,
      )));

  for (final (name, size) in [('badacz', const Size(1200, 760)), ('badacz_waski', const Size(390, 1500))]) {
    testWidgets(name, (t) async {
      final m = ResearchMonitor(() => MockSource(
            duration: const Duration(seconds: 14),
            alphaAmplitudeUv: (_) => 15,
            noiseUv: 4,
          ));
      await t.runAsync(() => m.start());
      final db = AppDatabase.inMemory();
      final services = AppServices(
        repository: SessionRepository(db),
        rawDir: '/tmp',
        sourceFactory: () => MockSource(),
      );
      await pumpScreen(
        t,
        ServicesScope(
          services: services,
          child: ResearchScreen(
            monitor: m,
            reportOverride: LatencyReport.from(
              filterUs: [1800, 2000, 2600],
              qualityUs: [900, 1000, 1100],
              welchUs: [3100, 3300, 4400],
              smoothUs: [100, 100, 100],
              receiveUs: [42000, 50000, 88000],
              renderUs: [17000, 20000, 33000],
              stepMs: 256,
            ),
          ),
        ),
        size: size,
      );
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('../goldens/$name.png'));
      await t.pumpWidget(const SizedBox());
      db.close();
    });
  }

  Future<(AppDatabase, SessionRepository)> settingsDb(AppSettings s) async {
    final db = AppDatabase.inMemory();
    final repo = SessionRepository(db);
    s.save(repo);
    return (db, repo);
  }

  testWidgets('ustawienia: demo', (t) async {
    final (db, repo) = await settingsDb(AppSettings());
    await pumpScreen(
      t,
      ServicesScope(
        services: AppServices(repository: repo, rawDir: '/tmp'),
        child: const SettingsScreen(),
      ),
      size: const Size(390, 1250),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../goldens/ustawienia_demo.png'));
    db.close();
  });

  testWidgets('ustawienia: czepek', (t) async {
    final (db, repo) = await settingsDb(AppSettings(
      source: SourceKind.device,
      deviceName: 'BA MAXI 012',
      libPath: '/tmp/libbacore.dylib',
    )..training['alfa'] = ['O2', 'Pz']);
    await pumpScreen(
      t,
      ServicesScope(
        services: AppServices(repository: repo, rawDir: '/tmp'),
        child: SettingsScreen(scan: (_) async => ['BA MAXI 012']),
      ),
      size: const Size(390, 1900),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../goldens/ustawienia_czepek.png'));
    db.close();
  });

  testWidgets('ustawienia: wybor zrodla, skan i kanaly zapisuja sie w bazie', (t) async {
    final (db, repo) = await settingsDb(AppSettings());
    final lib = File('${Directory.systemTemp.createTempSync('lib').path}/libbacore.dylib')..createSync();
    await pumpScreen(
      t,
      ServicesScope(
        services: AppServices(repository: repo, rawDir: '/tmp'),
        child: SettingsScreen(scan: (_) async => ['BA MAXI 012', 'BA MIDI 003']),
      ),
      size: const Size(390, 1900),
    );
    expect(AppSettings.load(repo).source, SourceKind.demo);
    await t.tap(find.text('CZEPEK BRAINACCESS'));
    await t.pump();
    expect(AppSettings.load(repo).source, SourceKind.device);

    await t.enterText(find.byType(TextField).first, lib.path);
    await t.pump();
    expect(AppSettings.load(repo).libPath, lib.path);

    await t.tap(find.text('SZUKAJ CZEPKA'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(find.text('BA MIDI 003'), findsOneWidget);
    await t.tap(find.text('BA MIDI 003'));
    await t.pump();
    expect(AppSettings.load(repo).deviceName, 'BA MIDI 003');
    expect(AppSettings.load(repo).channelNames.length, 16);
    expect(find.text('NUMERY'), findsNothing);
    await t.tap(find.text('BA MAXI 012'));
    await t.pump();
    expect(AppSettings.load(repo).deviceName, 'BA MAXI 012');
    expect(AppSettings.load(repo).channelNames.length, 32);

    // kanaly treningowe: O1 wylaczony, Pz dolozony
    await t.tap(find.text('O1').first);
    await t.pump();
    await t.tap(find.text('Pz').first);
    await t.pump();
    expect(AppSettings.load(repo).trainingChannelsFor(TrainingProtocol.alfa), ['O2', 'Pz']);

    await t.tap(find.text('NUMERY'));
    await t.pump();
    expect(AppSettings.load(repo).naming, ChannelNaming.numbered);
    expect(AppSettings.load(repo).trainingChannelsFor(TrainingProtocol.alfa), ['ch12', 'ch2']);
    db.close();
  });
}
