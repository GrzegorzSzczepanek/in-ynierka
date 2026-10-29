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
      footer: true,
      bottom: PkAction(label: 'ZAKOŃCZ', onTap: onFinish, primary: false),
      child: ListView(
        children: [
          Row(children: [
            PkBack(onPressed: onFinish),
            const SizedBox(width: 12),
            Text('KALIBRACJA', style: Px.t(20, height: 1.3, shadow: true)),
          ]),
          const SizedBox(height: 12),
          PkWindow(
            padding: const EdgeInsets.all(6),
            child: Column(children: [
              PkMenuRow(label: '1 OCZY OTWARTE', trailing: 'trwa', selected: true),
              const PkMenuRow(label: '2 WYNIK', trailing: 'czeka'),
            ]),
          ),
          const SizedBox(height: 12),
          PkWindow(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(children: [
              const Neuronek(mood: Mood.focused, height: 100),
              const SizedBox(height: 8),
              Text(mSs(left), style: Px.display),
              const SizedBox(height: 10),
              PkSegBar(value: snapshot.phaseElapsedS / total),
            ]),
          ),
          const SizedBox(height: 12),
          const PkDialog(text: 'Usiądź spokojnie, patrz przed siebie. Nie zaciskaj szczęki ani powiek.'),
          const SizedBox(height: 14),
          Text('WYNIK', style: Px.t(10)),
          const SizedBox(height: 6),
          PkLeader('Próba', '${snapshot.attempt}'),
          PkLeader('Jakość sygnału', qualityLabel(snapshot.signalQuality)),
          if (retry)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Poprzednia próba odrzucona: za dużo nieważnych fragmentów. Powtarzamy.',
                  style: Px.tiny),
            ),
        ],
      ),
    );
  }
}
