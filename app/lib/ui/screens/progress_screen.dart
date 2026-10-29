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
    const days = ['pn', 'wt', 'śr', 'cz', 'pt', 'sb', 'nd'];
    return ScreenFrame(
      child: ListView(
        children: [
          Row(children: [
            PixelBack(onPressed: onBack),
            const SizedBox(width: 12),
            Text('Postęp', style: Px.h1),
          ]),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(decimal(data.totalMinutes, 0), style: Px.hero),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(next == null ? 'min' : '/${next.requiredValidMinutes} min',
                  style: Px.text(28, color: Px.ink2)),
            ),
          ]),
          Text(
            next == null
                ? 'poprawnego treningu, ostatni etap osiągnięty'
                : 'poprawnego treningu do etapu: ${next.name}',
            style: Px.secondary,
          ),
          const SizedBox(height: 10),
          PixelBar(value: data.stageProgress),
          const SizedBox(height: 16),
          Row(children: [
            for (var i = 0; i < visible.length; i++)
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                  child: PixelCard(
                    selected: i == 0,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Column(children: [
                      Opacity(
                        opacity: i == 0 ? 1 : 0.3,
                        child: Neuronek(
                            mood: i == 0 ? Mood.happy : Mood.sleepy, height: 64, shadow: false),
                      ),
                      const SizedBox(height: 6),
                      Text(visible[i].name,
                          textAlign: TextAlign.center, style: Px.text(13, weight: 500)),
                      Text(i == 0 ? 'obecny' : 'od ${visible[i].requiredValidMinutes} min',
                          style: Px.caption),
                    ]),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 20),
          Text('Ten tydzień', style: Px.h2),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 28,
                    decoration: BoxDecoration(
                      color: data.week[i] ? Px.accent : Px.panel,
                      border: Border.all(color: i == todayIndex ? Px.accent : Px.ink, width: 2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(days[i], style: Px.caption),
                ]),
              ),
          ]),
          const SizedBox(height: 4),
          Text('Pominięty dzień niczego nie zeruje. Postęp rośnie z poprawnego czasu treningu.',
              style: Px.caption),
          const SizedBox(height: 20),
          Text('Ostatnie sesje', style: Px.h2),
          const SizedBox(height: 4),
          if (data.recent.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Jeszcze nie ma sesji. Zacznij pierwszy trening.', style: Px.secondary),
            ),
          for (final s in data.recent.take(8))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Px.soft))),
              child: Row(children: [
                Expanded(
                  child: Text('${s.protocol.title}, ${s.createdAt.toLocal().day}.${s.createdAt.toLocal().month.toString().padLeft(2, '0')}',
                      style: Px.body),
                ),
                Text(mSs(s.validMinutes * 60), style: Px.text(16, weight: 500)),
              ]),
            ),
        ],
      ),
    );
  }
}
