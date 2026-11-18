import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

class FlushResult {
  FlushResult(this.sent, this.dropped, this.remaining);
  final int sent;
  final int dropped;
  final int remaining;
}

/// File d'envoi hors ligne. Un élément = un signalement (photo) et, en option, un mémo vocal.
/// Le mémo n'est envoyé qu'après le signalement (le serveur le rattache par client_id).
class Outbox {
  static const _key = 'outbox_v1';

  Future<List<Map<String, dynamic>>> _read() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _write(List<Map<String, dynamic>> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(items));
  }

  Future<int> count() async => (await _read()).length;

  Future<Directory> _dir() async {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/outbox');
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> _copyAudio(String clientId, String audioPath) async {
    final dir = await _dir();
    final ext = audioPath.contains('.') ? audioPath.substring(audioPath.lastIndexOf('.')) : '.m4a';
    return (await File(audioPath).copy('${dir.path}/$clientId$ext')).path;
  }

  Future<void> add(Map<String, String> fields, String photoPath, {String? audioPath, int audioSeconds = 0}) async {
    final dir = await _dir();
    final saved = await File(photoPath).copy('${dir.path}/${fields['client_id']}.jpg');
    final audio = audioPath == null ? null : await _copyAudio(fields['client_id']!, audioPath);
    final items = await _read();
    items.add({
      'fields': fields,
      'photo': saved.path,
      if (audio != null) 'audio': audio,
      if (audio != null) 'audio_s': audioSeconds,
      'sent': false,
    });
    await _write(items);
  }

  /// Le signalement est déjà parti, mais pas son mémo vocal.
  Future<void> addAudioOnly(String clientId, String audioPath, int seconds) async {
    final audio = await _copyAudio(clientId, audioPath);
    final items = await _read();
    items.add({
      'fields': {'client_id': clientId},
      'audio': audio,
      'audio_s': seconds,
      'sent': true,
    });
    await _write(items);
  }

  bool _retry(ApiException e) =>
      e.network || e.status >= 500 || e.status == 401 || e.status == 408 || e.status == 429;

  Future<FlushResult> flush(Api api) async {
    final items = await _read();
    var sent = 0;
    var dropped = 0;
    final keep = <Map<String, dynamic>>[];
    var stop = false;
    for (final it in items) {
      if (stop) {
        keep.add(it);
        continue;
      }
      final fields = Map<String, String>.from(it['fields'] as Map);
      final photo = it['photo'] as String?;
      final audio = it['audio'] as String?;
      var reportSent = it['sent'] == true;

      if (!reportSent && photo != null) {
        try {
          await api.upload('/api/reports', fields, filePath: photo);
          sent++;
          reportSent = true;
          await _remove(photo);
        } on ApiException catch (e) {
          if (_retry(e)) {
            keep.add(it);
            stop = true;
          } else {
            dropped++;
            await _remove(photo);
            if (audio != null) await _remove(audio);
          }
          continue;
        }
      }

      if (audio != null) {
        try {
          await api.upload(
            '/api/voice',
            {'client_id': fields['client_id'] ?? '', 'duration_s': '${it['audio_s'] ?? 0}'},
            filePath: audio,
            field: 'audio',
          );
          await _remove(audio);
        } on ApiException catch (e) {
          if (_retry(e)) {
            keep.add({...it, 'photo': null, 'sent': true});
            stop = true;
          } else {
            await _remove(audio);
          }
        }
      }
    }
    await _write(keep);
    return FlushResult(sent, dropped, keep.length);
  }

  Future<void> _remove(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
