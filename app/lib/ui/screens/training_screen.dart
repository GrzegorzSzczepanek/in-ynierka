import 'package:flutter/material.dart';

import '../../core/session/session_models.dart';
import '../../core/session/training_protocol.dart';
import '../format.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';
import '../widgets/pk_widgets.dart';

class TrainingLogEntry {
  const TrainingLogEntry(this.time, this.text);

  final String time;
  final String text;
}

/// Trening (neuronek, wynik, pasmo celu, sygnal) oraz przerwa miedzy blokami.
class TrainingScreen extends StatelessWidget {
  const TrainingScreen({
    super.key,
    required this.snapshot,
    required this.log,
    required this.onFinish,
    this.history = const [],
    this.protocol = TrainingProtocol.relaks,
  });

  final TrainingProtocol protocol;
  final SessionSnapshot snapshot;
  final List<TrainingLogEntry> log;
  final List<double> history;
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
    final quality = snapshot.signalQuality;

    final Mood mood = inBreak
        ? Mood.sleepy
        : paused
            ? Mood.worried
            : inTarget
                ? Mood.delighted
                : Mood.focused;

    return ScreenFrame(
      footer: true,
      bottom: PkAction(label: 'ZAKOŃCZ', onTap: onFinish, primary: false),
      child: ListView(
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(inBreak ? 'PRZERWA' : protocol.title.toUpperCase(),
                  style: Px.t(20, height: 1.3, shadow: true)),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(mmss(left), style: Px.t(14, height: 1.3)),
              Text(
                inBreak
                    ? 'następny ${snapshot.blockNo + 1}/${snapshot.blocksTotal}'
                    : 'blok ${snapshot.blockNo}/${snapshot.blocksTotal}',
                style: Px.tiny,
              ),
            ]),
          ]),
          Text(protocol.subtitle, style: Px.tiny),
          const SizedBox(height: 10),
          SpriteWindow(
            mood: mood,
            height: 160,
            top: paused
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(height: 8, margin: const EdgeInsets.symmetric(horizontal: 12), color: Px.soft),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          if (paused)
            PkWindow(
              color: Px.warnBg,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  snapshot.lastInvalid == null
                      ? 'SYGNAŁ NIEWIARYGODNY'
                      : reasonTitle(snapshot.lastInvalid!).toUpperCase(),
                  style: Px.t(11),
                ),
                const SizedBox(height: 6),
                Text(
                  'Feedback wstrzymany. Wynik nie jest liczony, dopóki sygnał nie wróci do normy. '
                  '${snapshot.lastInvalid == null ? '' : reasonHint(snapshot.lastInvalid!)}',
                  style: Px.t(9, height: 1.7),
                ),
              ]),
            )
          else
            PkWindow(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(inBreak ? 'ODPOCZYNEK' : 'WYNIK', style: Px.t(9, color: Px.ink2))),
                  Text(inBreak ? '--' : '${((fb?.y ?? 0.5) * 100).round()}',
                      style: Px.t(30, height: 1.1, shadow: true)),
                ]),
                const SizedBox(height: 8),
                PkBar(value: inBreak ? 0 : (fb?.y ?? 0.5), marker: threshold, height: 18),
                const SizedBox(height: 8),
                Text(
                  inBreak
                      ? 'Oczy możesz zamknąć, bez ruchu.'
                      : 'Cel: moc pasma powyżej progu ${decimal(threshold)}',
                  style: Px.tiny,
                ),
              ]),
            ),
          const SizedBox(height: 12),
          if (!inBreak && !paused)
            PkWindow(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('PASMO CELU', style: Px.t(9, color: Px.ink2))),
                  Text('ostatnie 30 s', style: Px.tiny),
                ]),
                const SizedBox(height: 6),
                PkChart(values: history, threshold: threshold, height: 56),
              ]),
            ),
          if (!inBreak) ...[
            const SizedBox(height: 12),
            Row(children: [
              Text('SYGNAŁ', style: Px.t(8, height: 1)),
              const SizedBox(width: 10),
              Expanded(child: _SignalBars(quality: quality, weak: paused)),
              const SizedBox(width: 10),
              Text(qualityLabel(quality).toUpperCase(), style: Px.t(8, height: 1)),
            ]),
          ],
          const SizedBox(height: 12),
          if (log.isNotEmpty)
            PkWindow(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(children: [
                for (final e in log.reversed.take(3)) PkLeader(e.time, e.text),
              ]),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.quality, required this.weak});

  final double? quality;
  final bool weak;

  @override
  Widget build(BuildContext context) {
    final filled = quality == null ? 0 : (quality! * 5).round().clamp(0, 5);
    return Container(
      height: 20,
      decoration: BoxDecoration(color: Px.panel, border: Border.all(color: Px.ink, width: 2)),
      child: Row(children: [
        for (var i = 0; i < 5; i++)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: i < filled ? (weak || filled <= 2 ? Px.danger : Px.accent) : Px.panel,
                border: i == 4 ? null : const Border(right: BorderSide(color: Px.ink, width: 1)),
              ),
            ),
          ),
      ]),
    );
  }
}
