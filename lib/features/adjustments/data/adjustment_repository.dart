import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';

/// Repository pou ajisteman manyèl sou VANT NÈT ak KREDIT
/// target: 'net' oswa 'credit'
/// operation: 'add' oswa 'subtract'
class AdjustmentRepository {
  AdjustmentRepository(this._db, this._outbox, this._hlc);
  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  Future<void> recordAdjustment({
    required String target,
    required String operation,
    required double amount,
    required String reason,
    String? storeId,
    String? userId,
    String? notes,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');
    if (reason.trim().isEmpty) throw ArgumentError('reason obligatwa');
    if (target != 'net' && target != 'credit') {
      throw ArgumentError('target dwe "net" oswa "credit"');
    }
    if (operation != 'add' && operation != 'subtract') {
      throw ArgumentError('operation dwe "add" oswa "subtract"');
    }
    final now = DateTime.now().toUtc();
    final id = Ulid().toCanonical();
    final version = _hlc.next();

    await _db.transaction((txn) async {
      final payload = {
        'id': id,
        'store_id': storeId,
        'user_id': userId,
        'target': target,
        'operation': operation,
        'amount': amount,
        'reason': reason,
        'notes': notes,
        'version': version,
        'created_at': now.toIso8601String(),
      };
      await txn.insert('manual_adjustments', payload);
      await _outbox.enqueue(
        txn: txn,
        tableName: 'manual_adjustments',
        rowId: id,
        op: 'create',
        payload: payload,
        overrideVersion: version,
      );
    });
  }

  Future<List<Map<String, Object?>>> listRecent({int limit = 50}) async {
    return await _db.query(
      'manual_adjustments',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
      limit: limit,
    );
  }
}

final adjustmentRepositoryProvider = Provider<AdjustmentRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return AdjustmentRepository(db, outbox, hlc);
});
