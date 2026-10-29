import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotchi/core/db/session_repository.dart';
import 'package:neurotchi/core/dsp/alpha_pipeline.dart';
import 'package:neurotchi/core/dsp/calibration.dart';
import 'package:neurotchi/core/session/session_models.dart';
import 'package:neurotchi/core/session/training_protocol.dart';
import 'package:neurotchi/ui/screens/calibration_screen.dart';
import 'package:neurotchi/ui/screens/connection_screen.dart';
import 'package:neurotchi/ui/screens/home_screen.dart';
import 'package:neurotchi/ui/screens/progress_screen.dart';
import 'package:neurotchi/ui/screens/summary_screen.dart';
import 'package:neurotchi/ui/screens/training_screen.dart';

import '../support/golden_support.dart';

void noop() {}

void _ignore(TrainingProtocol _) {}

Future<void> golden(WidgetTester t, String name, Widget screen) async {
  await pumpScreen(t, screen);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../goldens/$name.png'));
}

void main() {
  testWidgets('dom', (t) => golden(t, 'dom', const HomeScreen(
        data: HomeData(
          stageNo: 1,
          stageName: 'soma',
          stageProgress: 0.35,
          minutesToNext: 6.5,
          sourceLabel: 'Czepek',
          trainingMinutes: 9,
          channelsLabel: '16/32 kanałów',
        ),
        selected: TrainingProtocol.relaks,
        onSelect: _ignore,
        onStart: noop,
        onProgress: noop,
      )));

  testWidgets('dom: skupienie', (t) => golden(t, 'dom_skupienie', const HomeScreen(
        data: HomeData(
          stageNo: 2,
          stageName: 'neuron',
          stageProgress: 0.5,
          minutesToNext: 10,
          sourceLabel: 'Czepek',
          trainingMinutes: 9,
          channelsLabel: '16/32 kanałów',
        ),
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
      )));

  testWidgets('polaczenie: utracone', (t) => golden(t, 'polaczenie_utracone', ConnectionScreen(
        snapshot: const SessionSnapshot(phase: SessionPhase.connectionLost, phaseElapsedS: 0, attempt: 3),
        trainingChannels: const ['O1', 'O2'],
        maxAttempts: 3,
        onFinish: noop,
        onRetry: noop,
      )));

  testWidgets('kalibracja', (t) => golden(t, 'kalibracja', const CalibrationScreen(
        snapshot: SessionSnapshot(
          phase: SessionPhase.calibrating,
          phaseElapsedS: 18,
          phaseDurationS: 60,
          attempt: 2,
          signalQuality: 0.9,
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
          feedback: FeedbackSample(valid: true, y: 0.72),
          signalQuality: 0.95,
        ),
        history: [0.4, 0.45, 0.5, 0.48, 0.55, 0.6, 0.58, 0.66, 0.7, 0.72],
        log: [
          TrainingLogEntry('01:17', 'Nagroda'),
          TrainingLogEntry('02:41', 'Próg 0,60, sygnał: dobry'),
        ],
        onFinish: noop,
      )));

  testWidgets('trening: artefakt', (t) => golden(t, 'trening_artefakt', const TrainingScreen(
        snapshot: SessionSnapshot(
          phase: SessionPhase.training,
          phaseElapsedS: 90,
          phaseDurationS: 180,
          blockNo: 2,
          blocksTotal: 3,
          threshold: 0.6,
          feedback: FeedbackSample(valid: false, y: 0.5),
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
        ),
        log: [],
        onFinish: noop,
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
          CalibrationRecord(1, 60, CalibrationResult(accepted: true, validRatio: 0.95)),
        ],
        blocks: blocks,
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
}
