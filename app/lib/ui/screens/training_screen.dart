import 'package:flutter/material.dart';

import '../../core/session/session_models.dart';
import '../format.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';
import 'target_dial.dart';

class TrainingLogEntry {
  const TrainingLogEntry(this.time, this.text);

  final String time;
  final String text;
}

/// Trening (jeden obiekt feedbacku) oraz przerwa miedzy blokami.
class TrainingScreen extends StatelessWidget {
  const TrainingScreen({
    super.key,
    required this.snapshot,
    required this.log,
    required this.onFinish,
  });

  final SessionSnapshot snapshot;
  final List<TrainingLogEntry> log;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final inBreak = snapshot.phase == SessionPhase.breakBetweenBlocks;
    final total = snapshot.phaseDurationS ?? 0;
    final left = (total - snapshot.phaseElapsedS).clamp(0, total).toDouble();
    final fb = snapshot.feedback;
    final paused = !inBreak && fb != null && !fb.valid;
    final threshold = snapshot.threshold ?? 0.5;
    final inTarget = fb != null && fb.valid && fb.y > threshold;

    final Mood mood = inBreak
        ? Mood.sleepy
        : paused
            ? Mood.worried
            : inTarget
                ? Mood.delighted
                : Mood.focused;

    return ScreenFrame(
      bottom: PixelButton(label: 'Zakończ', primary: false, onPressed: onFinish),
      child: ListView(
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inBreak ? 'Przerwa' : 'Trening alfa', style: Px.h1),
                Text('alfa 8–12 Hz, O1 O2', style: Px.caption),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(mmss(left), style: Px.text(32)),
              Text(
                inBreak
                    ? 'następny: blok ${snapshot.blockNo + 1} z ${snapshot.blocksTotal}'
                    : 'blok ${snapshot.blockNo} z ${snapshot.blocksTotal}',
                style: Px.caption,
              ),
            ]),
          ]),
          const SizedBox(height: 8),
          TargetDial(
            value: paused || inBreak ? 0 : (fb?.y ?? 0.5),
            threshold: threshold,
            active: !paused && !inBreak,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (inBreak || paused)
                Text('—', style: Px.text(72, color: Px.ink2))
              else
                Text(decimal(fb?.y ?? 0.5), style: Px.text(72, height: 1)),
              Text(
                inBreak
                    ? 'odpoczynek'
                    : paused
                        ? 'wstrzymano'
                        : inTarget
                            ? 'w celu'
                            : 'poniżej celu',
                style: Px.text(20),
              ),
              const SizedBox(height: 8),
              Neuronek(mood: mood, height: 64, shadow: false),
            ]),
          ),
          Center(
            child: Text(
              inBreak
                  ? 'Oczy możesz zamknąć, bez ruchu'
                  : 'Pasmo celu od ${decimal(threshold)}, sygnał: ${qualityLabel(snapshot.signalQuality)}',
              style: Px.caption,
            ),
          ),
          const SizedBox(height: 12),
          if (paused)
            PixelCard(
              color: Px.warnBg,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  snapshot.lastInvalid == null
                      ? 'Sygnał niewiarygodny'
                      : reasonTitle(snapshot.lastInvalid!),
                  style: Px.text(18, weight: 500),
                ),
                const SizedBox(height: 4),
                Text(
                  'Feedback wstrzymany. Wynik nie jest liczony, dopóki sygnał nie wróci do normy. '
                  '${snapshot.lastInvalid == null ? '' : reasonHint(snapshot.lastInvalid!)}',
                  style: Px.secondary.copyWith(color: Px.ink),
                ),
              ]),
            )
          else if (!inBreak)
            PixelCard(
              child: Text(
                inTarget
                    ? 'Jesteś w celu. Cokolwiek robisz, rób to dalej.'
                    : 'Zostań spokojny i patrz przed siebie. Nie szukam niczego na siłę.',
                style: Px.body,
              ),
            ),
          const SizedBox(height: 8),
          for (final e in log.reversed.take(3))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Px.soft))),
              child: Row(children: [
                SizedBox(width: 56, child: Text(e.time, style: Px.text(14, weight: 500))),
                Expanded(child: Text(e.text, style: Px.secondary)),
              ]),
            ),
        ],
      ),
    );
  }
}
