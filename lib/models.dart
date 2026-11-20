import 'package:uuid/uuid.dart';

class StudyEntry {
  final String id;
  final String kind;
  final Map<String, dynamic> data;
  final String updatedAt;
  final bool deleted;

  const StudyEntry({required this.id, required this.kind, required this.data, required this.updatedAt, this.deleted = false});

  factory StudyEntry.create(String kind, Map<String, dynamic> data) => StudyEntry(
    id: const Uuid().v4(), kind: kind, data: Map<String, dynamic>.from(data),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  StudyEntry change(Map<String, dynamic> patch, {bool? isDeleted}) => StudyEntry(
    id: id, kind: kind, data: {...data, ...patch},
    updatedAt: DateTime.now().toUtc().toIso8601String(), deleted: isDeleted ?? deleted,
  );

  String get title => data['title']?.toString() ?? 'Untitled';
  String get due => data['due']?.toString() ?? '';
  String get bookId => data['bookId']?.toString() ?? '';
  bool get done => data['done'] == true;
  int get minutes => (data['minutes'] as num?)?.toInt() ?? 0;

  Map<String, dynamic> toJson() => {
    'id': id, 'kind': kind, 'data': data, 'updatedAt': updatedAt, 'deleted': deleted,
  };

  factory StudyEntry.fromJson(Map<String, dynamic> json) => StudyEntry(
    id: json['id'].toString(), kind: json['kind'].toString(),
    data: Map<String, dynamic>.from(json['data'] as Map? ?? {}),
    updatedAt: json['updatedAt'].toString(), deleted: json['deleted'] == true,
  );

  factory StudyEntry.fromCloud(Map<String, dynamic> row) => StudyEntry(
    id: row['id'].toString(), kind: row['kind'].toString(),
    data: Map<String, dynamic>.from(row['payload'] as Map? ?? {}),
    updatedAt: row['updated_at'].toString(), deleted: row['deleted_at'] != null,
  );

  Map<String, dynamic> toCloud(String userId) => {
    'id': id, 'user_id': userId, 'kind': kind, 'payload': data,
    'updated_at': updatedAt, 'deleted_at': deleted ? updatedAt : null,
  };
}

String studyDay(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

DateTime? dayFromString(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? null : DateTime(date.year, date.month, date.day);
}
