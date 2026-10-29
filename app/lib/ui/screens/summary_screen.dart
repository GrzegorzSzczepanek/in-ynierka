import 'package:flutter/material.dart';

import '../../core/db/session_repository.dart';
import '../../core/dsp/alpha_pipeline.dart';
import '../../core/session/session_models.dart';
import '../format.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';

class SummaryScreen extends StatelessWidget {
  const SummaryScreen({
    super.key,
    required this.result,
    required this.recent,
    required this.onDone,
  });

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
      bottom: PixelButton(label: 'Zapisz i wróć', onPressed: onDone),
      child: ListView(
        children: [
          Text(done ? 'Sesja zakończona' : 'Sesja przerwana', style: Px.h1),
          const SizedBox(height: 12),
          PixelCard(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Neuronek(mood: blocks.isEmpty ? Mood.sleepy : Mood.happy, height: 80, shadow: false),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(mSs(valid), style: Px.display),
                  Text(
                    blocks.isEmpty
                        ? 'brak ukończonego bloku'
                        : 'poprawnego sygnału, ${(share * 100).round()}% w celu',
                    style: Px.caption,
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (blocks.isEmpty)
            Text(
              'Sesja nie liczy się do postępu, bo nie ukończono żadnego bloku.',
              style: Px.secondary,
            )
          else ...[
            Text('Bloki', style: Px.h2),
            const SizedBox(height: 8),
            for (final b in blocks)
              _Line(
                'Blok ${b.blockNo}',
                '${mSs(b.validSignalS)} poprawnego, '
                    '${b.validSignalS > 0 ? (b.timeAboveThresholdS / b.validSignalS * 100).round() : 0}% w celu, '
                    '${b.rewardCount} ${_nagrody(b.rewardCount)}',
              ),
            const SizedBox(height: 16),
            Text('Jakość pomiaru', style: Px.h2),
            const SizedBox(height: 8),
            _Line('Odrzucone fragmenty', '${intervals.length} (${mSs(invalidMs / 1000)})'),
            for (final e in (reasons.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(3))
              _Line(reasonTitle(e.key), '${e.value}'),
            _Line('Próby kalibracji', '${result.calibrations.length}'),
            const SizedBox(height: 16),
            _Line('Naliczony postęp', '+${decimal(valid / 60, 1)} min'),
          ],
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Ostatnie sesje', style: Px.h2),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final s in recent.take(6).toList().reversed)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 8 + (s.validMinutes / 12).clamp(0, 1) * 56,
                      color: Px.accentLight,
                    ),
                  ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 8 + (valid / 60 / 12).clamp(0, 1) * 56,
                    color: Px.accent,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Text('poprawne minuty w kolejnych sesjach', style: Px.caption),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  static String _nagrody(int n) => n == 1
      ? 'nagroda'
      : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14))
          ? 'nagrody'
          : 'nagród';
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Px.soft))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Px.body),
          const SizedBox(width: 12),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: Px.text(15, weight: 500))),
        ]),
      );
}
