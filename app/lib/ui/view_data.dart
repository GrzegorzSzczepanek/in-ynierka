import '../core/db/session_repository.dart';
import 'screens/home_screen.dart';
import 'screens/progress_screen.dart';

HomeData homeData(SessionRepository repo, {required int trainingMinutes, required String sourceLabel}) {
  final stages = repo.unlockedStages();
  final current = stages.last;
  final next = repo.nextStage;
  final total = repo.totalValidMinutes();
  final span = next == null ? 0 : next.requiredValidMinutes - current.requiredValidMinutes;
  return HomeData(
    stageNo: current.sortOrder,
    stageName: current.name,
    stageProgress: next == null || span <= 0
        ? 1
        : ((total - current.requiredValidMinutes) / span).clamp(0, 1),
    minutesToNext: next == null ? null : next.requiredValidMinutes - total,
    sourceLabel: sourceLabel,
    trainingMinutes: trainingMinutes,
    channelsLabel: sourceLabel,
  );
}

ProgressData progressData(SessionRepository repo, DateTime now) {
  final all = repo.allStages();
  final total = repo.totalValidMinutes();
  final currentIndex = all.lastIndexWhere((s) => s.requiredValidMinutes <= total);
  final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
  final days = {for (final d in repo.dailyStats()) d.date: d};
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return ProgressData(
    totalMinutes: total,
    stages: all,
    currentIndex: currentIndex < 0 ? 0 : currentIndex,
    week: [for (var i = 0; i < 7; i++) days.containsKey(key(monday.add(Duration(days: i))))],
    recent: repo.history(),
  );
}
