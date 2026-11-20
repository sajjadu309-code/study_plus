import 'package:flutter_test/flutter_test.dart';
import 'package:study_pulse_mobile/models.dart';
import 'package:study_pulse_mobile/services/planner.dart';

void main() {
  StudyEntry topic(String title, String book, {bool done=false}) =>
    StudyEntry.create('topic',{'title':title,'bookId':book,'done':done});

  test('Plans unfinished topics before exam and respects the selected book', () {
    final topics=[topic('Stacks','book1'),topic('Queues','book1'),topic('Networking','book2'),topic('Done','book1',done:true)];
    final plan=ExamPlanner.generate(topics:topics,plans:[],bookId:'book1',today:DateTime(2026,11,18),examDate:DateTime(2026,11,21));
    expect(plan.sessions.length,2);
    expect(plan.sessions.every((s)=>s.bookId=='book1'&&s.due.compareTo('2026-11-21')<0),true);
  });

  test('Never duplicates a topic that already has a plan', () {
    final a=topic('Stacks','book1');
    final existing=StudyEntry.create('plan',{'title':'Study: Stacks','topicId':a.id,'bookId':'book1','due':'2026-11-19','done':false});
    final plan=ExamPlanner.generate(topics:[a],plans:[existing],bookId:'book1',today:DateTime(2026,11,18),examDate:DateTime(2026,11,22));
    expect(plan.sessions,isEmpty);
  });

  test('Marks overloaded days instead of silently dropping topics', () {
    final topics=[for(var i=0;i<4;i++)topic('Chapter $i','book1')];
    final plan=ExamPlanner.generate(topics:topics,plans:[],bookId:'book1',today:DateTime(2026,11,18),examDate:DateTime(2026,11,19),dailyLimit:2);
    expect(plan.sessions.length,4);
    expect(plan.overloaded,2);
  });
}
