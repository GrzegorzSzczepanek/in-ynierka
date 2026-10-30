import 'package:flutter/material.dart';

import '../../core/db/session_repository.dart';
import '../../core/dsp/alpha_pipeline.dart';
import '../../core/session/session_models.dart';
import '../../core/session/training_protocol.dart';
import '../format.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';
import '../widgets/pk_widgets.dart';

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({
    super.key,
    required this.result,
    required this.recent,
    required this.onDone,
    this.protocol = TrainingProtocol.alfa,
    this.mood,
    this.onMood,
  });

  /// Ocena samopoczucia 1..5 (opcjonalna), zapisywana przy "Zapisz i wroc".
  final int? mood;
  final ValueChanged<int>? onMood;

  final TrainingProtocol protocol;
  final SessionResult result;

  /// Ostatnie sesje (najnowsza pierwsza), bez biezacej.
  final List<SessionRow> recent;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final blocks = result.blocks;
    final valid = result.validSignalS;
    final above = blocks.fold(0.0, (a, b) => a + b.timeAboveThresholdS);
    final share = valid > 0 ? above / valid : 0.0;
    final intervals = [for (final b in blocks) ...b.invalid];
    final invalidMs = intervals.fold(0, (a, i) => a + (i.endMs - i.startMs));
    final reasons = <InvalidReason, int>{};
    for (final i in intervals) {
      reasons[i.reason] = (reasons[i.reason] ?? 0) + 1;
    }
    final done = result.status == SessionStatus.completed;
    return ScreenFrame(
      footer: true,
      bottom: PkAction(label: 'ZAPISZ I WRÓĆ', onTap: onDone),
      child: ListView(
        children: [
          Row(children: [
            Expanded(child: Text(protocol.title.toUpperCase(), style: Px.small)),
            Text('${result.calibrations.length} kal.', style: Px.tiny),
          ]),
          Text(done ? 'SESJA ZAKOŃCZONA!' : 'SESJA PRZERWANA', style: Px.t(17, height: 1.4, shadow: true)),
          const SizedBox(height: 10),
          PkWindow(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Neuronek(mood: blocks.isEmpty ? Mood.sleepy : Mood.happy, height: 80, shadow: false),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(mSs(valid), style: Px.display),
                  Text(
                    blocks.isEmpty ? 'brak ukończonego bloku' : 'w celu, ${(share * 100).round()}% sesji',
                    style: Px.tiny,
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (blocks.isEmpty)
            Text('Sesja nie liczy się do postępu: nie ukończono żadnego bloku.', style: Px.small)
          else ...[
            PkWindow(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(children: [
                for (final b in blocks)
                  PkLeader(
                    'Blok ${b.blockNo}',
                    '${mSs(b.validSignalS)} ${b.validSignalS > 0 ? (b.timeAboveThresholdS / b.validSignalS * 100).round() : 0}% '
                        '${b.rewardCount}x',
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            PkWindow(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Wskaźnik co 30 s, kreska to próg', style: Px.tiny),
                const SizedBox(height: 8),
                PkChart(
                  bars: true,
                  height: 80,
                  values: [for (final b in blocks) ...b.yTrace],
                  threshold: blocks.first.threshold,
                ),
                const SizedBox(height: 8),
                PkLeader('Średnia w blokach', blocks.map((b) => decimal(b.meanY).replaceFirst('0,', ',')).join(' ')),
                PkLeader('Odrzucone okna', '${blocks.fold(0, (a, b) => a + b.windowsInvalid)}/${blocks.fold(0, (a, b) => a + b.windowsTotal)}'),
                if (result.controlRatings.isNotEmpty)
                  PkLeader('Poczucie kontroli', [for (final b in blocks) result.controlRatings[b.blockNo]?.toString() ?? '-'].join(' ')),
              ]),
            ),
            const SizedBox(height: 12),
            PkWindow(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(children: [
                PkLeader('Odrzucone fragmenty', '${intervals.length} (${mSs(invalidMs / 1000)})'),
                for (final e in (reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3))
                  PkLeader(reasonTitle(e.key), '${e.value}'),
                PkLeader('Próby kalibracji', '${result.calibrations.length}'),
                PkLeader('Naliczony postęp', '+${decimal(valid / 60, 1)} min', bold: true),
              ]),
            ),
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            PkWindow(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('OSTATNIE SESJE', style: Px.t(9, color: Px.ink2)),
                const SizedBox(height: 8),
                PkChart(
                  bars: true,
                  height: 60,
                  values: [
                    for (final s in recent.take(5).toList().reversed) (s.validMinutes / 12).clamp(0.05, 1.0),
                    (valid / 60 / 12).clamp(0.05, 1.0),
                  ],
                  threshold: null,
                ),
                const SizedBox(height: 4),
                Text('poprawne minuty w kolejnych sesjach', style: Px.tiny),
              ]),
            ),
          ],
          if (onMood != null && blocks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('JAK SIĘ CZUJESZ?', style: Px.t(10)),
            Text('1 bardzo źle, 5 bardzo dobrze', style: Px.tiny),
            const SizedBox(height: 6),
            PkRating(value: mood, onChanged: onMood!, label: 'Samopoczucie'),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
