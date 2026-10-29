import 'package:flutter/material.dart';

import '../../core/db/session_repository.dart';
import '../format.dart';
import '../neuronek/neuronek.dart';
import '../theme/pixel_theme.dart';

class ProgressData {
  const ProgressData({
    required this.totalMinutes,
    required this.stages,
    required this.currentIndex,
    required this.week,
    required this.recent,
  });

  final double totalMinutes;
  final List<AvatarStage> stages;
  final int currentIndex;

  /// Poniedzialek do niedzieli: true, gdy w danym dniu byla sesja z postepem.
  final List<bool> week;
  final List<SessionRow> recent;

  AvatarStage get current => stages[currentIndex];
  AvatarStage? get next => currentIndex + 1 < stages.length ? stages[currentIndex + 1] : null;

  double get stageProgress {
    final n = next;
    if (n == null) return 1;
    final span = n.requiredValidMinutes - current.requiredValidMinutes;
    return span <= 0 ? 1 : ((totalMinutes - current.requiredValidMinutes) / span).clamp(0, 1);
  }
}

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.data, required this.onBack, this.todayIndex});

  final ProgressData data;
  final VoidCallback onBack;
  final int? todayIndex;

  @override
  Widget build(BuildContext context) {
    final next = data.next;
    final visible = data.stages.skip(data.currentIndex).take(3).toList();
    const days = ['PN', 'WT', 'ŚR', 'CZ', 'PT', 'SB', 'ND'];
    return ScreenFrame(
      child: ListView(
        children: [
          Row(children: [
            PkBack(onPressed: onBack),
            const SizedBox(width: 12),
            Text('POSTĘP', style: Px.t(20, height: 1.3, shadow: true)),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(decimal(data.totalMinutes, 0), style: Px.hero),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(next == null ? 'min' : '/${next.requiredValidMinutes}', style: Px.t(18, color: Px.ink2)),
            ),
          ]),
          Text(
            next == null
                ? 'minut poprawnego treningu, ostatni etap'
                : 'minut do etapu: ${next.name}',
            style: Px.small,
          ),
          const SizedBox(height: 10),
          PkSegBar(value: data.stageProgress, segments: 12, height: 22),
          const SizedBox(height: 14),
          PkWindow(
            padding: const EdgeInsets.all(6),
            child: Column(children: [
              for (var i = 0; i < visible.length; i++)
                Container(
                  color: i == 0 ? Px.accentLight : null,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(children: [
                    SizedBox(width: 18, child: i == 0 ? const PkCursor() : null),
                    Opacity(
                      opacity: i == 0 ? 1 : 0.35,
                      child: Neuronek(mood: i == 0 ? Mood.happy : Mood.sleepy, height: 52, shadow: false),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('NO.${visible[i].sortOrder.toString().padLeft(3, '0')}', style: Px.tiny),
                        Text(visible[i].name.toUpperCase(), style: Px.t(11, height: 1.5)),
                        Text(i == 0 ? 'obecny etap' : 'od ${visible[i].requiredValidMinutes} min',
                            style: Px.tiny),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text('TYDZIEŃ', style: Px.t(11))),
            Text('${data.week.where((d) => d).length} z 7', style: Px.tiny),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 24,
                    decoration: BoxDecoration(
                      color: data.week[i] ? Px.accent : Px.panel,
                      border: Border.all(color: i == todayIndex ? Px.accent : Px.ink, width: 3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(days[i], style: Px.t(7, color: Px.ink2, height: 1)),
                ]),
              ),
          ]),
          const SizedBox(height: 14),
          Text('OSTATNIE SESJE', style: Px.t(11)),
          const SizedBox(height: 6),
          if (data.recent.isEmpty) Text('Jeszcze nie ma sesji. Zacznij pierwszy trening.', style: Px.small),
          for (final s in data.recent.take(8))
            PkLeader(
              '${s.protocol.title} ${s.createdAt.toLocal().day}.${s.createdAt.toLocal().month.toString().padLeft(2, '0')}',
              mSs(s.validMinutes * 60),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
