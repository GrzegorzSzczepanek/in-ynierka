import 'package:flutter/material.dart';

import '../../core/session/session_models.dart';
import '../format.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';

/// Kalibracja: oczy otwarte (baseline), oczy zamkniete (reaktywnosc alfa), wynik.
class CalibrationScreen extends StatelessWidget {
  const CalibrationScreen({
    super.key,
    required this.snapshot,
    required this.onFinish,
    this.closedStep = true,
    this.onSkip,
    this.reactivityMin = 1.2,
  });

  final SessionSnapshot snapshot;
  final VoidCallback onFinish;

  /// Czy ten trening ma krok z zamknietymi oczami (tylko alfa).
  final bool closedStep;

  /// Pominiecie kalibracji (tylko gdy jest zapisana poprzednia).
  final VoidCallback? onSkip;
  final double reactivityMin;

  @override
  Widget build(BuildContext context) {
    final phase = snapshot.phase;
    final total = snapshot.phaseDurationS ?? 60;
    final left = (total - snapshot.phaseElapsedS).clamp(0, total).toDouble();
    final step = switch (phase) {
      SessionPhase.calibrating => 1,
      SessionPhase.calibratingClosed => 2,
      _ => 3,
    };
    String state(int n) => n < step
        ? 'gotowe'
        : (n == step && phase != SessionPhase.calibrationResult
              ? 'trwa'
              : (phase == SessionPhase.calibrationResult ? 'gotowe' : 'czeka'));
    final ratio = snapshot.alphaRatio;
    final lowRatio = ratio != null && ratio < reactivityMin;
    final text = switch (phase) {
      SessionPhase.calibratingClosed =>
        'Zamknij oczy i siedź spokojnie. Nie zaciskaj powiek.',
      SessionPhase.calibrationResult =>
        lowRatio
            ? 'Reaktywność alfa jest niska, ale możesz trenować dalej. Wynik bywa słabszy przy suchych elektrodach.'
            : 'Kalibracja gotowa. Za chwilę zaczynamy trening.',
      _ => 'Usiądź spokojnie, patrz przed siebie. Nie zaciskaj szczęki ani powiek.',
    };
    final mood = switch (phase) {
      SessionPhase.calibratingClosed => Mood.sleepy,
      SessionPhase.calibrationResult =>
        lowRatio ? Mood.confused : Mood.delighted,
      _ => Mood.focused,
    };
    final skipLabel = onSkip != null;
    // Układ desktopowy (dwie kolumny od 900 dp) napisany z pomocą AI (Claude).
    final wide = isWideLayout(context);
    final header = Row(
      children: [
        PkBack(onPressed: onFinish),
        const SizedBox(width: 12),
        Text(
          'KALIBRACJA',
          style: Px.t(wide ? 24 : 20, height: 1.3, shadow: true),
        ),
      ],
    );
    final steps = PkWindow(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          PkMenuRow(
            label: '1 OCZY OTWARTE',
            trailing: state(1),
            selected: step == 1,
          ),
          if (closedStep)
            PkMenuRow(
              label: '2 OCZY ZAMKNIĘTE',
              trailing: state(2),
              selected: step == 2,
            ),
          PkMenuRow(
            label: '${closedStep ? 3 : 2} WYNIK',
            trailing: phase == SessionPhase.calibrationResult
                ? 'gotowe'
                : 'czeka',
            selected: phase == SessionPhase.calibrationResult,
          ),
        ],
      ),
    );
    final timer = PkWindow(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          Neuronek(mood: mood, height: wide ? 220 : 100),
          const SizedBox(height: 8),
          Text(
            phase == SessionPhase.calibrationResult ? '✓' : mSs(left),
            style: Px.display,
          ),
          const SizedBox(height: 10),
          PkSegBar(
            value: phase == SessionPhase.calibrationResult
                ? 1
                : snapshot.phaseElapsedS / total,
          ),
        ],
      ),
    );
    final dialog = PkDialog(text: text);
    final results = <Widget>[
      Text('WYNIK', style: Px.t(10)),
      const SizedBox(height: 6),
      PkLeader('Próba', '${snapshot.attempt}'),
      PkLeader('Jakość sygnału', qualityLabel(snapshot.signalQuality)),
      if (closedStep) ...[
        PkLeader(
          'Indywidualna alfa',
          snapshot.alphaPeakHz == null
              ? '---'
              : '${decimal(snapshot.alphaPeakHz!, 1)} Hz',
        ),
        PkLeader(
          'Oczy zamk./otw.',
          ratio == null ? '---' : 'x${decimal(ratio, 1)}',
        ),
      ],
      PkLeader(
        'Próg startowy',
        snapshot.threshold == null ? '---' : decimal(snapshot.threshold!),
      ),
      if (closedStep)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Stosunek poniżej ${decimal(reactivityMin, 1)}: powtórzymy ten krok (najwyżej 2 razy).',
            style: Px.tiny,
          ),
        ),
    ];
    return ScreenFrame(
      wide: wide,
      footer: true,
      bottom: PkAction(
        label: skipLabel ? 'POMIŃ KALIBRACJĘ' : 'ZAKOŃCZ',
        onTap: skipLabel ? onSkip : onFinish,
        primary: skipLabel,
      ),
      child: wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 16),
                Expanded(
                  child: PkTwoPane(
                    left: [timer, const SizedBox(height: 12), dialog],
                    right: [steps, const SizedBox(height: 14), ...results],
                  ),
                ),
              ],
            )
          : ListView(
              children: [
                header,
                const SizedBox(height: 12),
                steps,
                const SizedBox(height: 12),
                timer,
                const SizedBox(height: 12),
                dialog,
                const SizedBox(height: 14),
                ...results,
              ],
            ),
    );
  }
}
