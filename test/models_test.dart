import 'package:flutter_test/flutter_test.dart';
import 'package:study_pulse_mobile/models.dart';

void main(){
  test('StudyEntry JSON round-trip preserves titles and due dates',(){
    final e=StudyEntry.create('assignment',{'title':'OS assignment','due':'2026-11-21','done':false});
    final restored=StudyEntry.fromJson(e.toJson());
    expect(restored.title,'OS assignment');
    expect(restored.due,'2026-11-21');
    expect(restored.id,e.id);
  });
}
