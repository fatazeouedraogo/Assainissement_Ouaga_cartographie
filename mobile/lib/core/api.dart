import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const kDefaultBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:3000');

class ApiException implements Exception {
  ApiException(this.status, this.message, [this.code]);
  final int status;
  final String message;
  final String? code;
  bool get network => status == 0;
  bool get unauthorized => status == 401;
  @override
  String toString() => message;
}

class Api {
  Api(this.base);
  String base;
  String? token;

  String get _root => base.replaceAll(RegExp(r'/+$'), '');

  Uri _uri(String path, [Map<String, String>? q]) {
    final u = Uri.parse('$_root$path');
    return q == null || q.isEmpty ? u : u.replace(queryParameters: q);
  }

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<dynamic> get(String path, {Map<String, String>? query, int timeout = 25}) =>
      _run(() => http.get(_uri(path, query), headers: _headers), timeout);

  Future<dynamic> post(String path, [Map<String, dynamic>? body, int timeout = 25]) => _run(
    () => http.post(
      _uri(path),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(body ?? {}),
    ),
    timeout,
  );

  Future<dynamic> upload(
    String path,
    Map<String, String> fields, {
    String? filePath,
    String field = 'photo',
  }) {
    return _run(() async {
      final req = http.MultipartRequest('POST', _uri(path))
        ..headers.addAll(_headers)
        ..fields.addAll(fields);
      if (filePath != null) req.files.add(await http.MultipartFile.fromPath(field, filePath));
      return http.Response.fromStream(await req.send());
    }, 60);
  }

  Future<Uint8List> postBytes(String path, [Map<String, dynamic>? body, int timeout = 60]) async {
    http.Response r;
    try {
      r = await http
          .post(
            _uri(path),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body ?? {}),
          )
          .timeout(Duration(seconds: timeout));
    } on TimeoutException {
      throw ApiException(0, 'Le serveur ne répond pas. Vérifiez la connexion.');
    } catch (_) {
      throw ApiException(0, 'Connexion impossible. Vérifiez le réseau et l’adresse du serveur.');
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
    var msg = 'Erreur ${r.statusCode}';
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map) {
        final e = d['error'];
        msg = (e is Map ? e['message'] : (d['message'] ?? e))?.toString() ?? msg;
      }
    } catch (_) {}
    throw ApiException(r.statusCode, msg);
  }

  Future<dynamic> _run(Future<http.Response> Function() call, int timeout) async {
    http.Response r;
    try {
      r = await call().timeout(Duration(seconds: timeout));
    } on TimeoutException {
      throw ApiException(0, 'Le serveur ne répond pas. Vérifiez la connexion.');
    } catch (_) {
      throw ApiException(0, 'Connexion impossible. Vérifiez le réseau et l’adresse du serveur.');
    }
    dynamic data;
    if (r.body.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(r.bodyBytes));
      } catch (_) {
        data = null;
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return data;
    var msg = 'Erreur ${r.statusCode}';
    String? code;
    if (data is Map) {
      final e = data['error'];
      if (e is Map) {
        msg = (e['message'] ?? msg).toString();
        code = e['code']?.toString();
      } else {
        msg = (data['message'] ?? e ?? msg).toString();
        code = data['code']?.toString();
      }
    }
    throw ApiException(r.statusCode, msg, code);
  }

  String photoUrl(String name) => name.startsWith('http') ? name : '$_root/uploads/$name';
}
