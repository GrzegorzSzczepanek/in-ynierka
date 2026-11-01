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
    this.protocol = TrainingProtocol.alfa,
    this.onPause,
    this.onResume,
    this.onRate,
  });

  final VoidCallback? onPause;
  final VoidCallback? onResume;

  /// Ocena poczucia kontroli 1..5 po bloku (w przerwie).
  final ValueChanged<int>? onRate;

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
    final userPaused = !inBreak && snapshot.paused;
    final paused = !inBreak && !userPaused && fb != null && !fb.valid;
    final threshold = snapshot.threshold ?? 0.5;
    final inTarget = fb != null && fb.valid && fb.y > threshold;
    final quality = snapshot.signalQuality;

    final Mood mood = inBreak
        ? Mood.sleepy
        : userPaused
        ? Mood.sleepy
        : paused
        ? Mood.worried
        : inTarget
        ? Mood.delighted
        : Mood.focused;

    // Układ desktopowy (dwie kolumny od 900 dp) napisany z pomocą AI (Claude).
    final wide = isWideLayout(context);

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            inBreak ? 'PRZERWA' : protocol.title.toUpperCase(),
            style: Px.t(wide ? 24 : 20, height: 1.3, shadow: true),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(mmss(left), style: Px.t(wide ? 18 : 14, height: 1.3)),
            Text(
              inBreak
                  ? 'następny ${snapshot.blockNo + 1}/${snapshot.blocksTotal}'
                  : 'blok ${snapshot.blockNo}/${snapshot.blocksTotal}',
              style: Px.tiny,
            ),
          ],
        ),
      ],
    );
    final subtitle = Text(protocol.subtitle, style: Px.tiny);

    final sprite = SpriteWindow(
      mood: mood,
      height: wide ? 300 : 160,
      top: paused
          ? Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: Px.soft,
              ),
            )
          : null,
    );

    final Widget status = userPaused
        ? const PkDialog(
            text: 'WSTRZYMANO\nCzas i wynik stoją. Wznów, gdy będziesz gotowy.',
            more: false,
          )
        : paused
        ? PkWindow(
            color: Px.warnBg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
              ],
            ),
          )
        : PkWindow(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        inBreak ? 'ODPOCZYNEK' : 'WYNIK',
                        style: Px.t(9, color: Px.ink2),
                      ),
                    ),
                    Text(
                      inBreak ? '--' : '${((fb?.y ?? 0.5) * 100).round()}',
                      style: Px.t(30, height: 1.1, shadow: true),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PkBar(
                  value: inBreak ? 0 : (fb?.y ?? 0.5),
                  marker: threshold,
                  height: 18,
                ),
                const SizedBox(height: 8),
                Text(
                  inBreak
                      ? 'Oczy możesz zamknąć, bez ruchu.'
                      : 'Cel: moc pasma powyżej progu ${decimal(threshold)}',
                  style: Px.tiny,
                ),
              ],
            ),
          );

    final Widget? rating = inBreak && onRate != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'POCZUCIE KONTROLI W BLOKU ${snapshot.blockNo}',
                style: Px.t(9),
              ),
              Text('1 brak kontroli, 5 pełna kontrola', style: Px.tiny),
              const SizedBox(height: 6),
              PkRating(
                value: snapshot.controlRating,
                onChanged: onRate!,
                label: 'Kontrola',
              ),
            ],
          )
        : null;

    final Widget? chart = !inBreak && !paused && !userPaused
        ? PkWindow(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('PASMO CELU', style: Px.t(9, color: Px.ink2)),
                    ),
                    Text('ostatnie 30 s', style: Px.tiny),
                  ],
                ),
                const SizedBox(height: 6),
                PkChart(
                  values: history,
                  threshold: threshold,
                  height: wide ? 110 : 56,
                ),
              ],
            ),
          )
        : null;

    final Widget? signal = !inBreak
        ? Row(
            children: [
              Text('SYGNAŁ', style: Px.t(8, height: 1)),
              const SizedBox(width: 10),
              Expanded(
                child: _SignalBars(quality: quality, weak: paused),
              ),
              const SizedBox(width: 10),
              Text(
                qualityLabel(quality).toUpperCase(),
                style: Px.t(8, height: 1),
              ),
            ],
          )
        : null;

    final Widget? logBox = log.isNotEmpty
        ? PkWindow(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                for (final e in log.reversed.take(3)) PkLeader(e.time, e.text),
              ],
            ),
          )
        : null;

    return ScreenFrame(
      wide: wide,
      footer: true,
      bottom: PkMenu(
        rows: [
          if (!inBreak && onPause != null)
            PkMenuRow(
              label: userPaused ? 'WZNÓW' : 'PAUZA',
              selected: true,
              onTap: userPaused ? onResume : onPause,
            ),
          PkMenuRow(
            label: 'ZAKOŃCZ',
            selected: inBreak || onPause == null,
            onTap: onFinish,
          ),
        ],
      ),
      child: wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                subtitle,
                const SizedBox(height: 16),
                Expanded(
                  child: PkTwoPane(
                    leftFlex: 5,
                    rightFlex: 4,
                    left: [sprite],
                    right: [
                      status,
                      if (rating != null) ...[
                        const SizedBox(height: 12),
                        rating,
                      ],
                      const SizedBox(height: 12),
                      ?chart,
                      if (signal != null) ...[
                        const SizedBox(height: 12),
                        signal,
                      ],
                      const SizedBox(height: 12),
                      ?logBox,
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              children: [
                header,
                subtitle,
                const SizedBox(height: 10),
                sprite,
                const SizedBox(height: 12),
                status,
                if (rating != null) ...[const SizedBox(height: 12), rating],
                const SizedBox(height: 12),
                ?chart,
                if (signal != null) ...[const SizedBox(height: 12), signal],
                const SizedBox(height: 12),
                ?logBox,
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
      decoration: BoxDecoration(
        color: Px.panel,
        border: Border.all(color: Px.ink, width: 2),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: i < filled
                      ? (weak || filled <= 2 ? Px.danger : Px.accent)
                      : Px.panel,
                  border: i == 4
                      ? null
                      : const Border(
                          right: BorderSide(color: Px.ink, width: 1),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
