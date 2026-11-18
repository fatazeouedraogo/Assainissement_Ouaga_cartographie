import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'outbox.dart';

class Session extends ChangeNotifier {
  Session._(this.api, this._prefs);

  final Api api;
  final SharedPreferences _prefs;
  final Outbox outbox = Outbox();

  Map<String, dynamic>? user;
  int queued = 0;
  int toVerify = 0;
  int unread = 0;
  bool syncing = false;
  final ValueNotifier<List<double>?> focus = ValueNotifier(null);

  static Future<Session> load() async {
    final p = await SharedPreferences.getInstance();
    final s = Session._(Api(p.getString('base') ?? kDefaultBase), p);
    s.api.token = p.getString('token');
    final u = p.getString('user');
    if (u != null && s.api.token != null) s.user = Map<String, dynamic>.from(jsonDecode(u) as Map);
    s.queued = await s.outbox.count();
    return s;
  }

  bool get loggedIn => api.token != null && user != null;
  String get role => (user?['role'] as String?) ?? 'citizen';
  bool get isStaff => role == 'verifier' || role == 'admin';
  bool get isAdmin => role == 'admin';
  String get name => (user?['name'] as String?) ?? '';
  int get points => (user?['points'] as num?)?.toInt() ?? 0;

  Future<void> setBase(String url) async {
    api.base = url.trim();
    await _prefs.setString('base', api.base);
    notifyListeners();
  }

  Future<void> login(String phone, String password) async {
    final j = await api.post('/api/auth/login', {'phone': phone, 'password': password});
    await _accept(j as Map);
  }

  Future<void> register(String name, String phone, String password) async {
    final j = await api.post('/api/auth/register', {'name': name, 'phone': phone, 'password': password});
    await _accept(j as Map);
  }

  Future<void> _accept(Map j) async {
    api.token = j['token'] as String;
    user = Map<String, dynamic>.from(j['user'] as Map);
    await _prefs.setString('token', api.token!);
    await _prefs.setString('user', jsonEncode(user));
    notifyListeners();
  }

  Future<void> logout() async {
    api.token = null;
    user = null;
    toVerify = 0;
    unread = 0;
    await _prefs.remove('token');
    await _prefs.remove('user');
    notifyListeners();
  }

  Future<void> refreshMe() async {
    try {
      final j = await api.get('/api/auth/me');
      final u = (j is Map && j['user'] is Map) ? j['user'] : j;
      if (u is Map) {
        user = {...?user, ...Map<String, dynamic>.from(u)};
        await _prefs.setString('user', jsonEncode(user));
        notifyListeners();
      }
    } on ApiException catch (e) {
      if (e.unauthorized) await logout();
    }
  }

  Future<void> refreshCounters() async {
    try {
      final j = await api.get('/api/notifications');
      unread = ((j as Map)['unread'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } on ApiException catch (e) {
      if (e.unauthorized) await logout();
    }
  }

  Future<FlushResult> syncOutbox() async {
    syncing = true;
    notifyListeners();
    try {
      final r = await outbox.flush(api);
      queued = r.remaining;
      if (r.sent > 0) refreshMe();
      return r;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> noteQueued() async {
    queued = await outbox.count();
    notifyListeners();
  }

  void setToVerify(int n) {
    if (n == toVerify) return;
    toVerify = n;
    notifyListeners();
  }

  void addPoints(int n) {
    if (user == null || n <= 0) return;
    user = {...user!, 'points': points + n};
    notifyListeners();
  }
}
