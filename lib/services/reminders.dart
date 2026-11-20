import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;
import '../models.dart';

class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();
  final FlutterLocalNotificationsPlugin plugin=FlutterLocalNotificationsPlugin();
  bool ready=false;
  bool get available => !kIsWeb && defaultTargetPlatform==TargetPlatform.android;

  Future<void> initialize() async {
    if (!available || ready) return;
    timezone_data.initializeTimeZones();
    try {
      final info=await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch(e) {
      debugPrint('Time zone discovery failed, using UTC: $e');
      tz.setLocalLocation(tz.UTC);
    }
    await plugin.initialize(settings:const InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher')));
    ready=true;
  }

  Future<bool> requestPermission() async {
    if (!available) return false;
    await initialize();
    final android=plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return (await android?.requestNotificationsPermission()) ?? false;
  }

  int notificationId(StudyEntry e) => int.parse(e.id.replaceAll('-', '').substring(0,8),radix:16) & 0x7fffffff;

  Future<void> schedule(StudyEntry entry) async {
    if (!available || !{'assignment','quiz','exam'}.contains(entry.kind)) return;
    try {
      await initialize();
      final id=notificationId(entry);
      await plugin.cancel(id:id);
      if (entry.deleted || entry.done) return;
      final due=dayFromString(entry.due);
      if (due==null) return;
      final android=plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (await android?.areNotificationsEnabled() != true) return;
      var target=DateTime(due.year,due.month,due.day,9).subtract(const Duration(days:1));
      if (!target.isAfter(DateTime.now())) target=DateTime(due.year,due.month,due.day,8);
      if (!target.isAfter(DateTime.now())) return;
      await plugin.zonedSchedule(
        id:id, title:'${entry.kind.toUpperCase()} coming up',
        body:'${entry.title} is due on ${entry.due}',
        scheduledDate:tz.TZDateTime.from(target,tz.local),
        notificationDetails:const NotificationDetails(android:AndroidNotificationDetails(
          'studypulse_deadline_channel','StudyPulse deadlines',
          channelDescription:'Upcoming assignments, quizzes and exams',importance:Importance.high,priority:Priority.high,
        )),
        androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch(e) {
      debugPrint('Reminder scheduling error: $e');
    }
  }

  Future<void> refresh(Iterable<StudyEntry> entries) async {
    if (!available) return;
    final upcoming=entries.where((e) => {'assignment','quiz','exam'}.contains(e.kind) && !e.deleted && !e.done && dayFromString(e.due)!=null)
      .toList()..sort((a,b)=>a.due.compareTo(b.due));
    for (final entry in upcoming.take(60)) {
      await schedule(entry);
    }
  }
}
