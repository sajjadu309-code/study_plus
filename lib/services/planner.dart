import '../models.dart';

class PlannedSession {
  final String topicId;
  final String title;
  final String bookId;
  final String due;
  final int minutes;
  final bool overCapacity;

  const PlannedSession({required this.topicId,required this.title,required this.bookId,required this.due,required this.minutes,required this.overCapacity});
}

class PlannerResult {
  final List<PlannedSession> sessions;
  final int overloaded;
  const PlannerResult(this.sessions, this.overloaded);
}

class ExamPlanner {
  static PlannerResult generate({
    required List<StudyEntry> topics,
    required List<StudyEntry> plans,
    required String bookId,
    required DateTime examDate,
    required DateTime today,
    int dailyLimit = 3,
    int minutes = 35,
  }) {
    if (dailyLimit < 1 || minutes < 5) throw ArgumentError('Invalid study capacity');
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final start = day(today);
    final last = day(examDate).subtract(const Duration(days: 1));
    if (last.isBefore(start)) throw ArgumentError('Choose an exam date after today.');

    final alreadyPlanned = plans.where((p) => !p.deleted).map((p) => p.data['topicId']?.toString() ?? '').toSet();
    final pending = topics.where((topic) => topic.bookId == bookId && !topic.deleted && !topic.done && !alreadyPlanned.contains(topic.id)).toList();
    pending.sort((a,b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    final loads = <String,int>{};
    for (final p in plans) {
      if (p.deleted || p.done || p.bookId != bookId) continue;
      if (p.due.isNotEmpty) loads[p.due] = (loads[p.due] ?? 0) + 1;
    }

    final dates = <DateTime>[];
    for (DateTime date = start; !date.isAfter(last) && dates.length < 180; date = date.add(const Duration(days: 1))) {
      dates.add(date);
    }
    if (dates.isEmpty) throw ArgumentError('No days available before the exam.');

    final result = <PlannedSession>[];
    var overloaded = 0;
    for (final topic in pending) {
      dates.sort((a,b) {
        final loadCompare = (loads[studyDay(a)] ?? 0).compareTo(loads[studyDay(b)] ?? 0);
        return loadCompare == 0 ? a.compareTo(b) : loadCompare;
      });
      final key = studyDay(dates.first);
      final count = loads[key] ?? 0;
      if (count >= dailyLimit) overloaded++;
      loads[key] = count + 1;
      result.add(PlannedSession(topicId:topic.id, title:topic.title, bookId:bookId, due:key, minutes:minutes, overCapacity:count>=dailyLimit));
    }
    result.sort((a,b) { final c=a.due.compareTo(b.due); return c!=0?c:a.title.compareTo(b.title); });
    return PlannerResult(result, overloaded);
  }
}
