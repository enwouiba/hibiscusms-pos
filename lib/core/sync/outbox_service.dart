import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../database/app_database.dart';
import 'hlc.dart';

/// Liy nan outbox lokal — yon chanjman ki gen pou voye sou sèvèr.
class OutboxEntry {
  final int id;
  final String opId;
  final String tableName;
  final String rowId;
  final String op; // create | update | delete
  final Map<String, dynamic> payload;
  final String version;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  OutboxEntry({
    required this.id,
    required this.opId,
    required this.tableName,
    required this.rowId,
    required this.op,
    required this.payload,
    required this.version,
    required this.createdAt,
    required this.attempts,
    this.lastError,
  });

  factory OutboxEntry.fromRow(Map<String, Object?> row) => OutboxEntry(
        id: row['id'] as int,
        opId: row['op_id'] as String,
        tableName: row['table_name'] as String,
        rowId: row['row_id'] as String,
        op: row['op'] as String,
        payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        version: row['version'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        attempts: row['attempts'] as int,
        lastError: row['last_error'] as String?,
      );

  Map<String, dynamic> toApi() => {
        'op_id': opId,
        'table': tableName,
        'op': op,
        'row_id': rowId,
        'payload': payload,
        'version': version,
        'client_at': createdAt.toIso8601String(),
      };
}

/// Pwèn santral pou ekri/li outbox.
class OutboxService {
  OutboxService(this._database, this._hlc);
  final AppDatabase _database;
  final Hlc _hlc;

  /// Anrejistre yon mitasyon (create/update/delete) nan outbox.
  ///
  /// Apèl sa ta dwe pase nan menm tranzaksyon ke ekriti reyèl tab la (e.g. `INSERT INTO sales`).
  Future<void> enqueue({
    required Transaction txn,
    required String tableName,
    required String rowId,
    required String op,
    required Map<String, dynamic> payload,
    String? overrideVersion,
  }) async {
    final version = overrideVersion ?? _hlc.next();
    await txn.insert('sync_outbox', {
      'op_id': Ulid().toCanonical(),
      'table_name': tableName,
      'row_id': rowId,
      'op': op,
      'payload': jsonEncode(payload),
      'version': version,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'attempts': 0,
    });
  }

  Future<List<OutboxEntry>> pending({int limit = 200}) async {
    final db = await _database.database;
    // Envoi TOUT items (limit 100 attempts pou anti-boul enfini nan ka trè patoloji)
    final rows = await db.query(
      'sync_outbox',
      where: 'attempts < ?',
      whereArgs: [100],
      orderBy: 'id ASC',
      limit: limit,
    );
    // REZISTANS: yon sèl liy korwonpi (chan null, payload ki pa JSON valab)
    // pa dwe fè `fromRow` lanse epi BLOKE tout push la. Nou sote move liy yo
    // epi nou make yo (attempts++) pou yo pa retounen san rete.
    final out = <OutboxEntry>[];
    for (final r in rows) {
      try {
        out.add(OutboxEntry.fromRow(r));
      } catch (_) {
        try {
          await db.rawUpdate(
            'UPDATE sync_outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?',
            ['parse_error: liy move', r['id']],
          );
        } catch (_) {}
      }
    }
    return out;
  }

  /// Reset konpteur eseye pou tout item ki nan outbox (rekipere apre bug sèvè).
  Future<int> resetAttempts() async {
    final db = await _database.database;
    return await db.update(
      'sync_outbox',
      {'attempts': 0, 'last_error': null},
    );
  }

  Future<int> count() async {
    final db = await _database.database;
    final r = await db.rawQuery('SELECT COUNT(*) c FROM sync_outbox');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> markSucceeded(List<String> opIds) async {
    if (opIds.isEmpty) return;
    final db = await _database.database;
    final placeholders = List.filled(opIds.length, '?').join(',');
    await db.delete('sync_outbox', where: 'op_id IN ($placeholders)', whereArgs: opIds);
  }

  Future<void> markFailed(String opId, String error) async {
    final db = await _database.database;
    await db.rawUpdate(
      'UPDATE sync_outbox SET attempts = attempts + 1, last_error = ?, last_attempt_at = ? WHERE op_id = ?',
      [error, DateTime.now().toUtc().toIso8601String(), opId],
    );
  }
}

final outboxServiceProvider = Provider<OutboxService>((ref) {
  throw UnimplementedError('Override outboxServiceProvider nan main.dart');
});
