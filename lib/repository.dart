import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';
import 'services/reminders.dart';

class StudyRepository extends ChangeNotifier {
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();
  final Map<String,StudyEntry> _entries = {};
  final Set<String> _pending = {};
  String? _owner;
  bool syncing = false;
  bool loading = false;
  String? syncError;
  DateTime? lastSynced;

  String? get owner => _owner;
  int get pendingCount => _pending.length;
  List<StudyEntry> get all {
    final result = _entries.values.where((e) => !e.deleted).toList();
    result.sort((a,b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }
  List<StudyEntry> ofKind(String kind) => all.where((e) => e.kind == kind).toList();
  StudyEntry? get profile {
    final profiles = ofKind('profile');
    return profiles.isEmpty ? null : profiles.first;
  }
  String get _itemsKey => 'study_pulse_v2_${_owner}_items';
  String get _queueKey => 'study_pulse_v2_${_owner}_queue';

  Future<void> open(User user) async {
    if (_owner == user.id) return;
    _owner = user.id;
    _entries.clear(); _pending.clear(); syncError = null;
    loading = true; notifyListeners();
    try {
      final saved = await prefs.getString(_itemsKey);
      final queue = await prefs.getString(_queueKey);
      if (saved != null) {
        for (final raw in jsonDecode(saved) as List) {
          final entry = StudyEntry.fromJson(Map<String,dynamic>.from(raw as Map));
          _entries[entry.id] = entry;
        }
      }
      if (queue != null) _pending.addAll((jsonDecode(queue) as List).map((e) => e.toString()));
    } catch (e) {
      syncError = 'Local data could not be loaded: $e';
    } finally {
      loading = false; notifyListeners();
    }
    unawaited(sync());
    unawaited(ReminderService.instance.refresh(all));
  }

  void closeAccount() {
    _owner = null; _entries.clear(); _pending.clear();
    syncing = false; syncError = null; notifyListeners();
  }

  Future<void> _save() async {
    if (_owner == null) return;
    await prefs.setString(_itemsKey, jsonEncode(_entries.values.map((e) => e.toJson()).toList()));
    await prefs.setString(_queueKey, jsonEncode(_pending.toList()));
  }

  Future<StudyEntry> add(String kind, Map<String,dynamic> data, {bool syncNow = true}) async {
    if (_owner == null) throw StateError('Sign in before saving');
    final record = StudyEntry.create(kind,data);
    _entries[record.id]=record; _pending.add(record.id);
    await _save(); notifyListeners();
    unawaited(ReminderService.instance.schedule(record));
    if (syncNow) unawaited(sync());
    return record;
  }

  Future<void> update(StudyEntry record, Map<String,dynamic> patch) async {
    final changed = record.change(patch);
    _entries[record.id]=changed; _pending.add(record.id);
    await _save(); notifyListeners();
    unawaited(ReminderService.instance.schedule(changed));
    unawaited(sync());
  }

  Future<void> delete(StudyEntry record) async {
    final changed = record.change({}, isDeleted:true);
    _entries[record.id]=changed; _pending.add(record.id);
    await _save(); notifyListeners();
    unawaited(ReminderService.instance.schedule(changed));
    unawaited(sync());
  }

  Future<void> sync() async {
    final owner = _owner;
    if (owner==null || syncing) return;
    syncing=true; syncError=null; notifyListeners();
    try {
      final cloud=Supabase.instance.client;
      if (cloud.auth.currentUser?.id != owner) throw StateError('Sign in to sync');
      // Exactly one snapshot of the queue. Remote downloads never create queue entries.
      final ids=_pending.toList();
      for (final id in ids) {
        if (_owner != owner) return;
        final snapshot=_entries[id];
        if (snapshot == null) { _pending.remove(id); await _save(); continue; }
        await cloud.from('sp2_items').upsert(snapshot.toCloud(owner),onConflict:'id');
        if (_entries[id]?.updatedAt == snapshot.updatedAt) _pending.remove(id);
        await _save(); notifyListeners();
      }
      if (_owner != owner) return;
      final rows=await cloud.from('sp2_items').select('id,kind,payload,updated_at,deleted_at').eq('user_id',owner);
      for (final raw in rows) {
        final remote=StudyEntry.fromCloud(Map<String,dynamic>.from(raw));
        if (_pending.contains(remote.id)) continue;
        final local=_entries[remote.id];
        final localDate=local==null ? null : DateTime.tryParse(local.updatedAt);
        final remoteDate=DateTime.tryParse(remote.updatedAt);
        if (local==null || (remoteDate!=null && (localDate==null || remoteDate.isAfter(localDate)))) {
          _entries[remote.id]=remote;
        }
      }
      await _save();
      lastSynced=DateTime.now();
      unawaited(ReminderService.instance.refresh(all));
    } catch(e) {
      // Keep unsent changes; no deletions, resets or endless retries.
      syncError=e.toString();
    } finally {
      syncing=false; notifyListeners();
    }
  }

  String exportJson() {
    if (_owner==null) throw StateError('Sign in first');
    return jsonEncode({'version':3,'userId':_owner,'exportedAt':DateTime.now().toUtc().toIso8601String(),
      'items':_entries.values.map((e)=>e.toJson()).toList()});
  }

  Future<int> importJson(String source) async {
    if (_owner==null) throw StateError('Sign in first');
    final json=Map<String,dynamic>.from(jsonDecode(source) as Map);
    if (json['userId']!=_owner) throw StateError('Backup belongs to a different Supabase account');
    if (![2,3].contains(json['version'])) throw const FormatException('Unknown backup version');
    var added=0;
    for (final raw in (json['items'] as List? ?? [])) {
      final entry=StudyEntry.fromJson(Map<String,dynamic>.from(raw as Map));
      final local=_entries[entry.id];
      final remoteTime=DateTime.tryParse(entry.updatedAt);
      final localTime=local==null ? null : DateTime.tryParse(local.updatedAt);
      if (local==null || (remoteTime!=null && (localTime==null || remoteTime.isAfter(localTime)))) {
        _entries[entry.id]=entry;
        _pending.add(entry.id); added++;
      }
    }
    await _save(); notifyListeners();
    unawaited(sync());
    return added;
  }
}
