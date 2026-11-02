import '../core/db/session_repository.dart';
import 'screens/home_screen.dart';
import 'screens/progress_screen.dart';

HomeData homeData(
  SessionRepository repo, {
  required int trainingMinutes,
  String sourceLabel = '',
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  final current = repo.unlockedStages().last;
  final weekGoal = 3.0 * trainingMinutes;
  return HomeData(
    stageNo: current.sortOrder,
    stageName: current.name,
    trainingMinutes: trainingMinutes,
    energy:
        (repo.validMinutesSince(t.subtract(const Duration(days: 7))) / weekGoal)
            .clamp(0.0, 1.0),
    focus: repo.lastSessionTargetShare(),
    streakDays: repo.streakDays(t),
    sourceLabel: sourceLabel,
  );
}

ProgressData progressData(SessionRepository repo, DateTime now) {
  final all = repo.allStages();
  final total = repo.totalValidMinutes();
  final currentIndex = all.lastIndexWhere(
    (s) => s.requiredValidMinutes <= total,
  );
  final monday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  final days = {for (final d in repo.dailyStats()) d.date: d};
  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return ProgressData(
    totalMinutes: total,
    stages: all,
    currentIndex: currentIndex < 0 ? 0 : currentIndex,
    week: [
      for (var i = 0; i < 7; i++)
        days.containsKey(key(monday.add(Duration(days: i)))),
    ],
    recent: repo.history(),
  );
}
