import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/outbox.dart';
import 'api.dart';
import 'models.dart';

class SubmitResult {
  SubmitResult({required this.queued, this.status, this.flags = const [], this.rejects = const [], this.points = 0, this.dumpStatus, this.reporters = 0});
  final bool queued;
  final String? status;
  final List<String> flags;
  final List<String> rejects;
  final int points;
  final String? dumpStatus;
  final int reporters;
}

class AppState extends ChangeNotifier {
  final api = Api();
  final _outbox = Outbox();
  final _uuid = const Uuid();
  StreamSubscription<List<ConnectivityResult>>? _net;

  AppUser? user;
  List<String> badges = [];
  List<Dump> dumps = [];
  int pending = 0;
  bool booting = true;
  bool loadingDumps = false;
  bool syncing = false;
  String? dumpError;

  Future<void> boot() async {
    await api.restore();
    if (api.token != null) {
      try {
        await _loadMe();
      } on ApiException catch (e) {
        if (e.status == 401) await api.saveToken(null);
      }
    }
    pending = (await _outbox.all()).length;
    _net = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((c) => c != ConnectivityResult.none)) sync();
    });
    booting = false;
    notifyListeners();
    if (user != null) {
      unawaited(refreshDumps());
      unawaited(sync());
    }
  }

  @override
  void dispose() {
    _net?.cancel();
    super.dispose();
  }

  Future<void> _loadMe() async {
    final j = await api.get('/api/auth/me');
    user = AppUser.fromJson(j['user'] as Map<String, dynamic>);
    badges = ((j['badges'] as List?) ?? []).map((b) => '${b['label']}').toList();
  }

  Future<void> login(String phone, String password) async {
    final j = await api.post('/api/auth/login', {'phone': phone, 'password': password});
    await api.saveToken(j['token'] as String);
    await _loadMe();
    notifyListeners();
    unawaited(refreshDumps());
    unawaited(sync());
  }

  Future<void> register(String name, String phone, String password) async {
    final j = await api.post('/api/auth/register', {'name': name, 'phone': phone, 'password': password});
    await api.saveToken(j['token'] as String);
    await _loadMe();
    notifyListeners();
    unawaited(refreshDumps());
  }

  Future<void> logout() async {
    await api.saveToken(null);
    user = null;
    dumps = [];
    notifyListeners();
  }

  Future<void> refreshMe() async {
    try {
      await _loadMe();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshDumps() async {
    loadingDumps = true;
    dumpError = null;
    notifyListeners();
    try {
      final j = await api.get('/api/dumps', {'limit': '3000'});
      dumps = (j['features'] as List).map((f) => Dump.fromFeature(f as Map<String, dynamic>)).toList();
    } on ApiException catch (e) {
      dumpError = e.message;
    }
    loadingDumps = false;
    notifyListeners();
  }

  Future<String> _keepPhoto(String path) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = '${dir.path}/${_uuid.v4()}.jpg';
    await File(path).copy(target);
    return target;
  }

  Future<SubmitResult> submitReport({
    required double lat,
    required double lon,
    required double accuracy,
    required String size,
    required String wasteType,
    required String photoPath,
    String? note,
  }) async {
    final id = _uuid.v4();
    final kept = await _keepPhoto(photoPath);
    final fields = {
      'client_id': id,
      'lat': '$lat',
      'lon': '$lon',
      'accuracy_m': accuracy.toStringAsFixed(1),
      'size': size,
      'waste_type': wasteType,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    try {
      final r = await _post(fields, kept);
      await File(kept).delete().catchError((_) => File(kept));
      return r;
    } on ApiException catch (e) {
      if (!e.isNetwork) {
        await File(kept).delete().catchError((_) => File(kept));
        rethrow;
      }
      await _outbox.add(OutboxItem(clientId: id, fields: fields, photoPath: kept, createdAt: DateTime.now()));
      pending = (await _outbox.all()).length;
      notifyListeners();
      return SubmitResult(queued: true);
    }
  }

  Future<SubmitResult> _post(Map<String, String> fields, String photoPath) async {
    final j = await api.multipart('/api/reports', fields, filePath: photoPath);
    final rep = j['report'] as Map<String, dynamic>;
    final dump = j['dump'] as Map<String, dynamic>?;
    unawaited(refreshDumps());
    unawaited(refreshMe());
    return SubmitResult(
      queued: false,
      status: rep['status'] as String,
      flags: (rep['flags'] as List).cast<String>(),
      rejects: (rep['reject_reasons'] as List).cast<String>(),
      points: (j['points_awarded'] as num).toInt(),
      dumpStatus: dump?['status'] as String?,
      reporters: (dump?['reporter_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> sync() async {
    if (syncing || user == null) return;
    syncing = true;
    notifyListeners();
    try {
      for (final item in await _outbox.all()) {
        if (item.photoPath == null || !File(item.photoPath!).existsSync()) {
          await _outbox.remove(item.clientId);
          continue;
        }
        try {
          await _post(item.fields, item.photoPath!);
          await _outbox.remove(item.clientId);
          await File(item.photoPath!).delete().catchError((_) => File(item.photoPath!));
        } on ApiException catch (e) {
          if (e.isNetwork || e.status == 401 || e.status >= 500) break;
          await _outbox.markError(item.clientId, e.message);
          await _outbox.remove(item.clientId);
        }
      }
    } finally {
      pending = (await _outbox.all()).length;
      syncing = false;
      notifyListeners();
    }
  }
}
