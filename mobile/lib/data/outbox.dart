import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class OutboxItem {
  OutboxItem({required this.clientId, required this.fields, required this.photoPath, required this.createdAt, this.error});
  final String clientId;
  final Map<String, String> fields;
  final String? photoPath;
  final DateTime createdAt;
  final String? error;
}

class Outbox {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      '$dir/ouaga_outbox.db',
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE outbox (client_id TEXT PRIMARY KEY, fields TEXT NOT NULL, photo_path TEXT, created_at INTEGER NOT NULL, error TEXT)',
      ),
    );
    return _db!;
  }

  Future<void> add(OutboxItem i) async {
    final db = await _open();
    await db.insert(
      'outbox',
      {
        'client_id': i.clientId,
        'fields': jsonEncode(i.fields),
        'photo_path': i.photoPath,
        'created_at': i.createdAt.millisecondsSinceEpoch,
        'error': i.error,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<OutboxItem>> all() async {
    final db = await _open();
    final rows = await db.query('outbox', orderBy: 'created_at ASC');
    return rows
        .map((r) => OutboxItem(
              clientId: r['client_id'] as String,
              fields: (jsonDecode(r['fields'] as String) as Map).map((k, v) => MapEntry('$k', '$v')),
              photoPath: r['photo_path'] as String?,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
              error: r['error'] as String?,
            ))
        .toList();
  }

  Future<void> remove(String clientId) async {
    final db = await _open();
    await db.delete('outbox', where: 'client_id = ?', whereArgs: [clientId]);
  }

  Future<void> markError(String clientId, String error) async {
    final db = await _open();
    await db.update('outbox', {'error': error}, where: 'client_id = ?', whereArgs: [clientId]);
  }
}
