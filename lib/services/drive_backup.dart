import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repository.dart';

/// Google Drive app-created file backup. Google OAuth setup is required.
/// Storage file bytes are embedded as base64 (up to 25 MB total).
class DriveBackupService {
  DriveBackupService._();
  static final DriveBackupService instance=DriveBackupService._();
  static const String _webClientId=String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const String _scope='https://www.googleapis.com/auth/drive.file';
  static const int maxDocumentBytes=25*1024*1024;
  bool initialized=false;

  Future<String> _token() async {
    if (kIsWeb) throw StateError('Google Drive backup is available in the Android app.');
    if (_webClientId.isEmpty) throw StateError('Google OAuth Web Client ID not set. See GOOGLE_DRIVE_SETUP.md');
    final google=GoogleSignIn.instance;
    if (!initialized) {
      await google.initialize(serverClientId:_webClientId);
      initialized=true;
    }
    final account=await google.authenticate();
    var auth=await account.authorizationClient.authorizationForScopes([_scope]);
    auth ??= await account.authorizationClient.authorizeScopes([_scope]);
    return auth.accessToken;
  }

  Future<String> createBackup(StudyRepository repo) async {
    final token=await _token();
    final files=<String,String>{};
    var total=0;
    final supa=Supabase.instance.client;
    final paths=<String>{
      for (final item in repo.ofKind('file')) item.data['storagePath']?.toString() ?? '',
      if (repo.profile != null) repo.profile!.data['avatarPath']?.toString() ?? '',
    };
    for (final path in paths) {
      if (path.isEmpty) continue;
      if (path.isEmpty) continue;
      final data=await supa.storage.from('sp2_materials').download(path);
      total+=data.length;
      if (total>maxDocumentBytes) {
        throw StateError('Document backup exceeds 25 MB. Remove large files from backup or use Supabase Storage.');
      }
      files[path]=base64Encode(data);
    }
    final backup=jsonEncode({
      'format':'StudyPulse-Full-Backup-v3',
      'records':jsonDecode(repo.exportJson()),
      'files':files,
    });
    final filename='StudyPulse_Full_${DateTime.now().toUtc().millisecondsSinceEpoch}.json';
    const boundary='studyPulseBoundary2026';
    final multipart='--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode({'name':filename,'mimeType':'application/json'})}\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$backup\r\n'
        '--$boundary--\r\n';
    final response=await http.post(Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name'),
      headers:{'Authorization':'Bearer $token','Content-Type':'multipart/related; boundary=$boundary'}, body:utf8.encode(multipart));
    if (response.statusCode<200 || response.statusCode>=300) {
      throw StateError('Google Drive upload failed: ${response.statusCode} ${response.body}');
    }
    return filename;
  }

  Future<int> restoreLatest(StudyRepository repo) async {
    final token=await _token();
    final headers={'Authorization':'Bearer $token'};
    final uri=Uri.https('www.googleapis.com','/drive/v3/files',{
      'q':"name contains 'StudyPulse_Full_' and trashed = false",
      'orderBy':'createdTime desc','fields':'nextPageToken,files(id,name,createdTime)','pageSize':'30',
    });
    final listing=await http.get(uri,headers:headers);
    if (listing.statusCode!=200) throw StateError('Cannot list Drive backups: ${listing.statusCode}');
    final files=(jsonDecode(listing.body) as Map<String,dynamic>)['files'] as List? ?? [];
    if (files.isEmpty) throw StateError('No StudyPulse Full backup found in this Google account.');
    final id=(files.first as Map)['id'].toString();
    final downloaded=await http.get(Uri.https('www.googleapis.com','/drive/v3/files/$id',{'alt':'media'}),headers:headers);
    if (downloaded.statusCode!=200) throw StateError('Could not download backup: ${downloaded.statusCode}');
    final json=Map<String,dynamic>.from(jsonDecode(utf8.decode(downloaded.bodyBytes)) as Map);
    if (json['format']!='StudyPulse-Full-Backup-v3') throw const FormatException('Not a compatible StudyPulse full backup');
    final records=Map<String,dynamic>.from(json['records'] as Map);
    if (records['userId']!=repo.owner) throw StateError('Backup belongs to another Supabase user.');
    final photoFiles=Map<String,dynamic>.from(json['files'] as Map? ?? {});
    final supa=Supabase.instance.client;
    for (final item in photoFiles.entries) {
      final path=item.key;
      if (!path.startsWith('${repo.owner}/')) throw const FormatException('Invalid backup path');
      final bytes=Uint8List.fromList(base64Decode(item.value.toString()));
      // A conflict generally indicates that the file already exists: do not overwrite it.
      try {
        await supa.storage.from('sp2_materials').uploadBinary(path,bytes,
          fileOptions:const FileOptions(upsert:false,contentType:'application/octet-stream'));
      } on StorageException catch(e) {
        if (e.statusCode!='409' && !e.message.toLowerCase().contains('already exists')) rethrow;
      }
    }
    return repo.importJson(jsonEncode(records));
  }
}
