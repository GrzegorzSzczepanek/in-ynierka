import 'package:flutter/material.dart';

import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';

/// Instrukcja przed treningiem alfa. Pokazywana do czasu wylaczenia w ustawieniach.
class InstructionScreen extends StatelessWidget {
  const InstructionScreen({
    super.key,
    required this.onStart,
    required this.onBack,
    required this.showAgain,
    required this.onShowAgain,
  });

  final VoidCallback onStart;
  final VoidCallback onBack;
  final bool showAgain;
  final ValueChanged<bool> onShowAgain;

  @override
  Widget build(BuildContext context) {
    // Układ desktopowy (neuronek obok tekstu) napisany z pomocą AI (Claude).
    final wide = isWideLayout(context);
    final fs = wide ? 11.0 : 9.0;
    final header = Row(
      children: [
        PkBack(onPressed: onBack),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'JAK TRENOWAĆ',
            style: Px.t(wide ? 24 : 20, height: 1.3, shadow: true),
          ),
        ),
      ],
    );
    final textWindow = PkWindow(
      padding: EdgeInsets.all(wide ? 20 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Usiądź wygodnie i patrz swobodnie na neuronka. Oddychaj naturalnie. '
            'Rozluźnij szczękę, twarz i ramiona.',
            style: Px.t(fs, height: 1.8),
          ),
          const SizedBox(height: 10),
          Text(
            'Spróbuj znaleźć sposób, przy którym neuronek się ożywia, i utrzymać go przez chwilę. '
            'Możesz zacząć od spokojnego obserwowania oddechu albo wyobrażenia sobie spokojnego miejsca.',
            style: Px.t(fs, height: 1.8),
          ),
          const SizedBox(height: 10),
          Text(
            'Nie steruj animacją głową, mięśniami ani zamykaniem oczu. Mrugaj naturalnie. '
            'Jeśli wynik nie rośnie, to nie znaczy, że robisz coś źle.',
            style: Px.t(fs, height: 1.8),
          ),
        ],
      ),
    );
    final note = Text(
      'Wynik pokazuje moc alfa względem Twojej kalibracji, a nie relaks ani koncentrację. '
      'To prototyp edukacyjny, nie terapia.',
      style: Px.tiny,
    );
    return ScreenFrame(
      wide: wide,
      footer: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PkMenu(
            rows: [
              PkMenuRow(
                label: 'POKAZUJ INSTRUKCJĘ',
                trailing: showAgain ? 'TAK' : 'NIE',
                selected: showAgain,
                onTap: () => onShowAgain(!showAgain),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PkAction(label: 'ROZPOCZYNAM', onTap: onStart),
        ],
      ),
      child: wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 16),
                Expanded(
                  child: PkTwoPane(
                    leftFlex: 4,
                    rightFlex: 5,
                    left: [
                      Center(
                        child: Neuronek(
                          mood: Mood.happy,
                          height: 240,
                          shadow: false,
                        ),
                      ),
                    ],
                    right: [textWindow, const SizedBox(height: 10), note],
                  ),
                ),
              ],
            )
          : ListView(
              children: [
                header,
                const SizedBox(height: 12),
                Center(
                  child: Neuronek(mood: Mood.happy, height: 90, shadow: false),
                ),
                const SizedBox(height: 12),
                textWindow,
                const SizedBox(height: 10),
                note,
                const SizedBox(height: 8),
              ],
            ),
    );
  }
}
