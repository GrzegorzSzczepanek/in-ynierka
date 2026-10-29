import 'package:flutter/material.dart';

import '../../core/session/session_models.dart';
import '../format.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';

class CalibrationScreen extends StatelessWidget {
  const CalibrationScreen({super.key, required this.snapshot, required this.onFinish});

  final SessionSnapshot snapshot;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final total = snapshot.phaseDurationS ?? 60;
    final left = (total - snapshot.phaseElapsedS).clamp(0, total).toDouble();
    final retry = snapshot.attempt > 1;
    return ScreenFrame(
      bottom: PixelButton(label: 'Zakończ', primary: false, onPressed: onFinish),
      child: ListView(
        children: [
          Text('Kalibracja', style: Px.h1),
          const SizedBox(height: 4),
          Text('pomiar punktu odniesienia, oczy otwarte', style: Px.secondary),
          const SizedBox(height: 16),
          PixelCard(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Neuronek(mood: Mood.focused, height: 110),
              const SizedBox(height: 12),
              Text(mSs(left), style: Px.hero),
              const SizedBox(height: 12),
              PixelBar(
                value: snapshot.phaseElapsedS / total,
                segments: 20,
                height: 20,
              ),
              const SizedBox(height: 12),
              Text(
                'Usiądź spokojnie, patrz przed siebie. Nie zaciskaj szczęki ani powiek.',
                textAlign: TextAlign.center,
                style: Px.secondary.copyWith(color: Px.ink),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          Text('Przebieg', style: Px.h2),
          const SizedBox(height: 8),
          _Row('Próba', '${snapshot.attempt}'),
          _Row('Jakość sygnału', qualityLabel(snapshot.signalQuality)),
          if (retry)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Poprzednia próba odrzucona: zbyt wiele nieważnych fragmentów. Powtarzamy pomiar.',
                style: Px.caption,
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Px.soft)),
        ),
        child: Row(children: [
          Expanded(child: Text(label, style: Px.body)),
          Text(value, style: Px.text(16, weight: 500)),
        ]),
      );
}
