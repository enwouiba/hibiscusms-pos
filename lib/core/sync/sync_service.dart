import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../auth/token_store.dart';
import '../constants/app_constants.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import 'hlc.dart';
import 'outbox_service.dart';

enum SyncStatus { idle, pushing, pulling, error, offline }

class SyncProgress {
  final SyncStatus status;
  final int pendingOutbox;
  final String? lastError;
  final DateTime? lastSyncAt;

  const SyncProgress({
    required this.status,
    this.pendingOutbox = 0,
    this.lastError,
    this.lastSyncAt,
  });
}

class SyncService {
  SyncService({
    required this.api,
    required this.outbox,
    required this.database,
    required this.tokenStore,
  });

  final ApiClient api;
  final OutboxService outbox;
  final AppDatabase database;
  final TokenStore tokenStore;

  Timer? _timer;
  final StreamController<SyncProgress> _progress = StreamController.broadcast();

  Stream<SyncProgress> get progress => _progress.stream;

  void start() {
    _timer?.cancel();
    // Reset kompteur eseye pou rekipere apre yon bug sèvè (v7 heal)
    // ignore: unawaited_futures
    outbox.resetAttempts();
    _timer = Timer.periodic(
      Duration(seconds: AppConstants.syncPushIntervalSeconds),
      (_) => runOnce(),
    );
    runOnce();
  }

  /// Fose yon sync imedyat + reset eseye — pou bouton "Sync Now"
  Future<void> forceSync() async {
    await outbox.resetAttempts();
    await runOnce();
  }

  /// Fose sync KONPLÈ — reset cursor lokal → rale tout done depi zewo sou sèvè
  /// (repare kachet lokal ki bloke — san bezwen uninstall)
  Future<void> forceFullPull() async {
    final storeId = await tokenStore.activeStoreId();
    final deviceId = await tokenStore.deviceId();
    if (storeId == null || deviceId == null) {
      throw StateError('Pa gen sesyon aktif');
    }
    final db = await database.database;
    // Efase cursor pou sa tab la — pwochen pull ap kòmanse depi zewo
    await db.delete(
      'sync_state',
      where: 'key = ?',
      whereArgs: ['pull_cursor:$storeId'],
    );
    // Efase magazen lokal yo pou yo re-pull FRE (settings/type/nif/email
    // korije) — san sa, chèk vèsyon an ta sote wou ki pa chanje yo.
    try { await db.delete('stores'); } catch (_) {}
    // Reset outbox tou
    await outbox.resetAttempts();
    // Kounye a fè sync total
    await runOnce();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> runOnce() async {
    // Mòd offline: pa eseye rele sèvè (IDs yo lokal sèlman)
    if (await tokenStore.isOfflineMode()) {
      _emit(SyncStatus.offline);
      return;
    }
    if (!await _hasInternet()) {
      _emit(SyncStatus.offline);
      return;
    }
    final storeId = await tokenStore.activeStoreId();
    final deviceId = await tokenStore.deviceId();
    if (storeId == null || deviceId == null) {
      _emit(SyncStatus.idle);
      return;
    }

    try {
      await _push(storeId, deviceId);
      await _pull(storeId, deviceId);
      _emit(SyncStatus.idle, lastSyncAt: DateTime.now());
    } catch (e) {
      _emit(SyncStatus.error, error: e.toString());
    }
  }

  Future<void> _push(String storeId, String deviceId) async {
    final entries = await outbox.pending(limit: AppConstants.syncBatchSize);
    if (entries.isEmpty) return;
    _emit(SyncStatus.pushing);

    final res = await api.dio.post('/api/sync/push', data: {
      'device_id': deviceId,
      'store_id': storeId,
      'operations': entries.map((e) => e.toApi()).toList(),
    });

    final results = (res.data['results'] as List).cast<Map<String, dynamic>>();
    final succeeded = results.where((r) => r['status'] == 'ok').map((r) => r['op_id'] as String).toList();
    await outbox.markSucceeded(succeeded);
    for (final r in results.where((r) => r['status'] == 'error')) {
      await outbox.markFailed(r['op_id'] as String, r['error']?.toString() ?? 'unknown');
    }
  }

  Future<void> _pull(String storeId, String deviceId) async {
    _emit(SyncStatus.pulling);
    final db = await database.database;
    final cursorRow = await db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: ['pull_cursor:$storeId'],
      limit: 1,
    );
    final since = cursorRow.isEmpty ? 0 : int.parse(cursorRow.first['value'] as String);

    final res = await api.dio.get('/api/sync/pull', queryParameters: {
      'store_id': storeId,
      'device_id': deviceId,
      'since': since,
      'limit': 500,
    });

    final changes = (res.data['changes'] as List).cast<Map<String, dynamic>>();
    final newCursor = (res.data['cursor'] as num).toInt();

    // Aplike chak row nan yon pwòp tranzaksyon — konsa yon sèl row ki echwe
    // pa lakòz tout pull la fè rollback (chwazi rezistans olye atomik).
    int applied = 0;
    int failed = 0;
    final errors = <String>[];
    for (final c in changes) {
      try {
        await db.transaction((txn) async {
          await _applyRemoteChange(txn, c);
        });
        applied++;
      } catch (e) {
        failed++;
        final tableName = c['table'] ?? '?';
        final rowId = c['row_id'] ?? '?';
        errors.add('$tableName#$rowId: $e');
        // ignore: avoid_print
        print('[SYNC] Row echwe $tableName#$rowId: $e');
      }
    }
    // Sove cursor sèlman si omwens yon row te aplike (konsa nou pa perdi pwogrè)
    await db.insert(
      'sync_state',
      {
        'key': 'pull_cursor:$storeId',
        'value': newCursor.toString(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (failed > 0) {
      // ignore: avoid_print
      print('[SYNC] $applied aplike, $failed echwe. Premye erè: ${errors.first}');
    }
  }

  Future<void> _applyRemoteChange(Transaction txn, Map<String, dynamic> change) async {
    final table = change['table'] as String;
    final rowId = change['row_id'] as String;
    final op = change['op'] as String;
    final payload = (change['payload'] as Map).cast<String, dynamic>();
    final remoteVersion = change['version'] as String?;

    if (op == 'delete') {
      await txn.delete(table, where: 'id = ?', whereArgs: [rowId]);
      return;
    }

    final existing = await txn.query(table, where: 'id = ?', whereArgs: [rowId], limit: 1);
    if (existing.isNotEmpty) {
      final localVersion = existing.first['version'] as String?;
      if (localVersion != null && remoteVersion != null &&
          Hlc.compare(localVersion, remoteVersion) >= 0) {
        return; // lokal a deja gen yon vèsyon egal oswa pi nouvo
      }
      await txn.update(
        table,
        await _normalizeRowForTable(txn, table, payload),
        where: 'id = ?',
        whereArgs: [rowId],
      );
    } else {
      await txn.insert(
        table,
        await _normalizeRowForTable(txn, table, payload),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // Kachet kolòn ki egziste pou chak tab (evite re-kesyon PRAGMA)
  final Map<String, Set<String>> _tableCols = {};
  Future<Set<String>> _columnsForTable(Transaction txn, String table) async {
    final cached = _tableCols[table];
    if (cached != null) return cached;
    final info = await txn.rawQuery('PRAGMA table_info($table)');
    final cols = info.map((r) => r['name'] as String).toSet();
    _tableCols[table] = cols;
    return cols;
  }

  /// Konvèti done API pou schema lokal:
  /// - filtè kolòn ki pa egziste lokal
  /// - konvèti bool→int
  /// - konvèti string pri "200.00" → double
  /// - garanti version pa NULL (paske schema mande NOT NULL)
  Future<Map<String, Object?>> _normalizeRowForTable(
    Transaction txn, String table, Map<String, dynamic> json,
  ) async {
    final cols = await _columnsForTable(txn, table);
    final out = <String, Object?>{};
    json.forEach((k, v) {
      if (!cols.contains(k)) return; // jete kolòn ki pa egziste
      if (v is bool) { out[k] = v ? 1 : 0; return; }
      // JSON valab (jsonEncode) — PA v.toString() ki bay yon fòma envalab
      // ke jsonDecode pa ka li (konsa settings tankou `type`/`nif`/`email`
      // pa pèdi apre sync).
      if (v is List || v is Map) { out[k] = jsonEncode(v); return; }
      // Konvèti String pri (ex: "200.00") an double si posib
      if (v is String && (k == 'price' || k == 'cost' || k == 'tax_rate' ||
          k == 'subtotal' || k == 'total' || k == 'discount' ||
          k == 'amount_received' || k == 'change_due' || k == 'amount_due' ||
          k == 'quantity' || k == 'unit_price' || k == 'total_price')) {
        out[k] = double.tryParse(v) ?? 0.0;
        return;
      }
      out[k] = v;
    });
    // Version obligatwa nan schema — bay valè defo si li manke
    if (cols.contains('version') && (out['version'] == null || out['version'] == '')) {
      out['version'] = 'srv:' + DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    }
    return out;
  }

  /// (Ansyen) — kite pou konpatibilite men pa itilize
  Map<String, Object?> _normalizeRow(Map<String, dynamic> json) {
    return json.map((k, v) {
      if (v is bool) return MapEntry(k, v ? 1 : 0);
      if (v is List || v is Map) return MapEntry(k, v.toString());
      return MapEntry(k, v);
    });
  }

  Future<bool> _hasInternet() async {
    final r = await Connectivity().checkConnectivity();
    return r.isNotEmpty && !r.contains(ConnectivityResult.none);
  }

  Future<void> _emit(SyncStatus status, {String? error, DateTime? lastSyncAt}) async {
    final pending = await outbox.count();
    _progress.add(SyncProgress(
      status: status,
      pendingOutbox: pending,
      lastError: error,
      lastSyncAt: lastSyncAt,
    ));
  }

  void dispose() {
    _timer?.cancel();
    _progress.close();
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  throw UnimplementedError('Override syncServiceProvider nan main.dart');
});

final syncProgressProvider = StreamProvider<SyncProgress>((ref) {
  return ref.watch(syncServiceProvider).progress;
});
