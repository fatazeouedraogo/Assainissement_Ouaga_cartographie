import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _defaultBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:3000');

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.fields = const []]);
  final int status;
  final String code;
  final String message;
  final List<String> fields;
  bool get isNetwork => status == 0;
  @override
  String toString() => message;
}

class Api {
  String baseUrl = _defaultBase;
  String? token;

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('base_url') ?? _defaultBase;
    token = p.getString('token');
  }

  Future<void> saveBase(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final p = await SharedPreferences.getInstance();
    await p.setString('base_url', baseUrl);
  }

  Future<void> saveToken(String? t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    if (t == null) {
      await p.remove('token');
    } else {
      await p.setString('token', t);
    }
  }

  Map<String, String> get _headers => {
        if (token != null) 'Authorization': 'Bearer $token',
      };

  String photoUrl(String? name) => name == null ? '' : '$baseUrl/uploads/$name';

  Future<dynamic> _send(Future<http.Response> Function() run) async {
    http.Response res;
    try {
      res = await run().timeout(const Duration(seconds: 90));
    } on SocketException {
      throw ApiException(0, 'reseau', 'Pas de connexion au serveur');
    } on http.ClientException {
      throw ApiException(0, 'reseau', 'Pas de connexion au serveur');
    } on Exception {
      throw ApiException(0, 'reseau', 'Le serveur ne répond pas');
    }
    final body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final map = body is Map ? body : const {};
    final fields = (map['fields'] is List) ? (map['fields'] as List).map((f) => '${f['field']}: ${f['message']}').toList() : <String>[];
    throw ApiException(res.statusCode, '${map['error'] ?? 'erreur'}', '${map['message'] ?? 'Erreur ${res.statusCode}'}', fields);
  }

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$baseUrl$path').replace(queryParameters: q);

  Future<dynamic> get(String path, [Map<String, String>? q]) => _send(() => http.get(_u(path, q), headers: _headers));

  Future<dynamic> post(String path, [Object? json]) => _send(() => http.post(
        _u(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(json ?? {}),
      ));

  Future<dynamic> put(String path, [Object? json]) => _send(() => http.put(
        _u(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(json ?? {}),
      ));

  Future<List<int>> postBytes(String path, [Object? json]) async {
    try {
      final res = await http.post(_u(path), headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(json ?? {})).timeout(const Duration(seconds: 90));
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
      final map = res.body.isEmpty ? const {} : jsonDecode(utf8.decode(res.bodyBytes));
      throw ApiException(res.statusCode, '${map['error'] ?? 'erreur'}', '${map['message'] ?? 'Erreur ${res.statusCode}'}');
    } on SocketException {
      throw ApiException(0, 'reseau', 'Pas de connexion au serveur');
    }
  }

  Future<dynamic> multipart(String path, Map<String, String> fields, {String? filePath, String fileField = 'photo'}) => _send(() async {
        final req = http.MultipartRequest('POST', _u(path))
          ..headers.addAll(_headers)
          ..fields.addAll(fields);
        if (filePath != null) req.files.add(await http.MultipartFile.fromPath(fileField, filePath));
        return http.Response.fromStream(await req.send());
      });
}
