import 'package:flutter/material.dart';

import '../../core/session/session_models.dart';
import '../../core/session/training_protocol.dart';
import '../format.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';

/// Ekran Kalibracja z menu glownego: ostatni wynik i uruchomienie kalibracji.
class CalibrationHubScreen extends StatelessWidget {
  const CalibrationHubScreen({
    super.key,
    required this.protocol,
    required this.stored,
    required this.onCalibrate,
    required this.onBack,
  });

  final TrainingProtocol protocol;
  final StoredCalibration? stored;
  final VoidCallback onCalibrate;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final s = stored;
    final d = s?.createdAt?.toLocal();
    return ScreenFrame(
      footer: true,
      bottom: PkAction(label: 'KALIBRUJ TERAZ', onTap: onCalibrate),
      child: ListView(
        children: [
          Row(
            children: [
              PkBack(onPressed: onBack),
              const SizedBox(width: 12),
              Text('KALIBRACJA', style: Px.t(20, height: 1.3, shadow: true)),
            ],
          ),
          const SizedBox(height: 12),
          PkWindow(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Neuronek(
                  mood: s == null ? Mood.confused : Mood.happy,
                  height: 80,
                  shadow: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s == null
                        ? 'Nie ma jeszcze kalibracji.'
                        : 'Ostatnia kalibracja: ${d!.day}.${d.month.toString().padLeft(2, '0')}.${d.year}.',
                    style: Px.t(10, height: 1.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${protocol.title.toUpperCase()}: OSTATNI WYNIK',
            style: Px.t(10),
          ),
          const SizedBox(height: 6),
          PkLeader(
            'Poziom bazowy',
            s == null ? '---' : decimal(s.baseline.median),
          ),
          PkLeader(
            'Rozrzut (MAD)',
            s == null ? '---' : decimal(s.baseline.scale),
          ),
          PkLeader('Próg startowy', s == null ? '---' : decimal(s.thresholdY)),
          if (protocol.kind == FeatureKind.alphaPower) ...[
            PkLeader(
              'Indywidualna alfa',
              s?.alphaPeakHz == null
                  ? '---'
                  : '${decimal(s!.alphaPeakHz!, 1)} Hz',
            ),
            PkLeader(
              'Oczy zamk./otw.',
              s?.alphaRatio == null ? '---' : 'x${decimal(s!.alphaRatio!, 1)}',
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Kalibracja trwa ok. ${protocol.kind == FeatureKind.alphaPower ? 'półtorej minuty' : 'minutę'}. '
            'Podczas treningu możesz ją pominąć i użyć tej.',
            style: Px.tiny,
          ),
        ],
      ),
    );
  }
}
