import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ulid/ulid.dart';

import '../../../core/di/providers.dart';
import '../../../core/sync/hlc.dart';
import '../../../core/sync/outbox_service.dart';
import '../../../shared/models/hotel.dart';

class HotelRepository {
  HotelRepository(this._db, this._outbox, this._hlc);

  final Database _db;
  final OutboxService _outbox;
  final Hlc _hlc;

  // ───────────────────────── Chanm ─────────────────────────

  Future<List<HotelRoom>> listRooms(String storeId) async {
    final rows = await _db.query(
      'hotel_rooms',
      where: 'store_id = ? AND (deleted_at IS NULL)',
      whereArgs: [storeId],
      orderBy: 'name ASC',
    );
    return rows.map(HotelRoom.fromMap).toList();
  }

  Future<HotelRoom?> findRoom(String id) async {
    final rows = await _db.query('hotel_rooms', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return HotelRoom.fromMap(rows.first);
  }

  Future<HotelRoom> createRoom({
    required String storeId,
    required String name,
    String? roomType,
    required double pricePerNight,
    required double pricePerHour,
    String? notes,
  }) async {
    final now = DateTime.now().toUtc();
    final id = Ulid().toCanonical();
    final version = _hlc.next();
    final map = <String, dynamic>{
      'id': id,
      'store_id': storeId,
      'name': name,
      'room_type': roomType,
      'price_per_night': pricePerNight,
      'price_per_hour': pricePerHour,
      'status': HotelRoomStatus.available.code,
      'notes': notes,
      'version': version,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    await _db.transaction((txn) async {
      await txn.insert('hotel_rooms', map);
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_rooms', rowId: id, op: 'create',
        payload: map, overrideVersion: version,
      );
    });
    return HotelRoom.fromMap(map);
  }

  Future<void> updateRoom({
    required String id,
    required String name,
    String? roomType,
    required double pricePerNight,
    required double pricePerHour,
    String? notes,
  }) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final rows = await txn.query('hotel_rooms', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first);
      map['name'] = name;
      map['room_type'] = roomType;
      map['price_per_night'] = pricePerNight;
      map['price_per_hour'] = pricePerHour;
      map['notes'] = notes;
      map['version'] = version;
      map['updated_at'] = now.toIso8601String();
      await txn.update('hotel_rooms', map, where: 'id = ?', whereArgs: [id]);
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_rooms', rowId: id, op: 'update',
        payload: map, overrideVersion: version,
      );
    });
  }

  Future<void> setRoomStatus(String id, HotelRoomStatus status) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final rows = await txn.query('hotel_rooms', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first);
      map['status'] = status.code;
      map['version'] = version;
      map['updated_at'] = now.toIso8601String();
      await txn.update('hotel_rooms', map, where: 'id = ?', whereArgs: [id]);
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_rooms', rowId: id, op: 'update',
        payload: map, overrideVersion: version,
      );
    });
  }

  Future<void> deleteRoom(String id) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      await txn.update(
        'hotel_rooms',
        {'deleted_at': now.toIso8601String(), 'updated_at': now.toIso8601String(), 'version': version},
        where: 'id = ?', whereArgs: [id],
      );
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_rooms', rowId: id, op: 'delete',
        payload: {'id': id}, overrideVersion: version,
      );
    });
  }

  // ───────────────────────── Sejou ─────────────────────────

  Future<int> _nextStayNumber(String storeId) async {
    final r = await _db.rawQuery(
      'SELECT COALESCE(MAX(stay_number), 0) AS m FROM hotel_stays WHERE store_id = ?',
      [storeId],
    );
    return ((r.first['m'] as num?)?.toInt() ?? 0) + 1;
  }

  /// Sejou aktif (moun ki anndan) pou yon chanm, si genyen.
  Future<HotelStay?> activeStayForRoom(String roomId) async {
    final rows = await _db.query(
      'hotel_stays',
      where: "room_id = ? AND status = 'active' AND (deleted_at IS NULL)",
      whereArgs: [roomId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return HotelStay.fromMap(rows.first);
  }

  /// Check-in: kreye sejou a + mete chanm nan okipe (atomik).
  Future<HotelStay> checkIn({
    required String storeId,
    required HotelRoom room,
    String? userId,
    String? cashierName,
    String? guestName,
    String? guestPhone,
    String? guestIdDoc,
    required HotelRentalMode mode,
    required int duration,
    double extra = 0,
    double discount = 0,
    double deposit = 0,
    String? notes,
  }) async {
    final now = DateTime.now().toUtc();
    final stayId = Ulid().toCanonical();
    final stayNumber = await _nextStayNumber(storeId);
    final rate = mode == HotelRentalMode.hourly ? room.pricePerHour : room.pricePerNight;
    final total = (rate * hotelBillableUnits(mode, duration) + extra - discount)
        .clamp(0, double.infinity)
        .toDouble();
    final version = _hlc.next();

    final map = <String, dynamic>{
      'id': stayId,
      'store_id': storeId,
      'user_id': userId,
      'cashier_name': cashierName,
      'room_id': room.id,
      'room_name_snapshot': room.name,
      'guest_name': guestName,
      'guest_phone': guestPhone,
      'guest_id_doc': guestIdDoc,
      'mode': mode.code,
      'duration': duration,
      'rate': rate,
      'stay_number': stayNumber,
      'status': HotelStayStatus.active.code,
      'check_in_at': now.toIso8601String(),
      'check_out_at': null,
      'extra': extra,
      'discount': discount,
      'total': total,
      'amount_paid': deposit,
      'notes': notes,
      'proforma_validated': 0,
      'version': version,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    await _db.transaction((txn) async {
      await txn.insert('hotel_stays', map);
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_stays', rowId: stayId, op: 'create',
        payload: map, overrideVersion: version,
      );
      // Mete chanm nan okipe
      final rv = _hlc.next();
      final rows = await txn.query('hotel_rooms', where: 'id = ?', whereArgs: [room.id], limit: 1);
      if (rows.isNotEmpty) {
        final rm = Map<String, dynamic>.from(rows.first);
        rm['status'] = HotelRoomStatus.occupied.code;
        rm['version'] = rv;
        rm['updated_at'] = now.toIso8601String();
        await txn.update('hotel_rooms', rm, where: 'id = ?', whereArgs: [room.id]);
        await _outbox.enqueue(
          txn: txn, tableName: 'hotel_rooms', rowId: room.id, op: 'update',
          payload: rm, overrideVersion: rv,
        );
      }
    });

    return HotelStay.fromMap(map);
  }

  /// Check-out: fèmen sejou a + mete chanm nan netwayaj (atomik).
  /// `finalDuration`/`finalExtra`/`finalDiscount` kite w ajiste total la.
  Future<void> checkOut(
    String stayId, {
    int? finalDuration,
    double? finalExtra,
    double? finalDiscount,
  }) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final rows = await txn.query('hotel_stays', where: 'id = ?', whereArgs: [stayId], limit: 1);
      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first);
      final rate = (map['rate'] as num?)?.toDouble() ?? 0;
      final mode = HotelRentalMode.fromCode(map['mode'] as String?);
      final dur = finalDuration ?? (map['duration'] as num?)?.toInt() ?? 1;
      final extra = finalExtra ?? (map['extra'] as num?)?.toDouble() ?? 0;
      final disc = finalDiscount ?? (map['discount'] as num?)?.toDouble() ?? 0;
      final total = (rate * hotelBillableUnits(mode, dur) + extra - disc)
          .clamp(0, double.infinity)
          .toDouble();

      map['duration'] = dur;
      map['extra'] = extra;
      map['discount'] = disc;
      map['total'] = total;
      map['status'] = HotelStayStatus.completed.code;
      map['check_out_at'] = now.toIso8601String();
      map['version'] = version;
      map['updated_at'] = now.toIso8601String();
      await txn.update('hotel_stays', map, where: 'id = ?', whereArgs: [stayId]);
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_stays', rowId: stayId, op: 'update',
        payload: map, overrideVersion: version,
      );

      // Chanm nan ale nan netwayaj
      final roomId = map['room_id'] as String?;
      if (roomId != null) {
        final rv = _hlc.next();
        final rrows = await txn.query('hotel_rooms', where: 'id = ?', whereArgs: [roomId], limit: 1);
        if (rrows.isNotEmpty) {
          final rm = Map<String, dynamic>.from(rrows.first);
          rm['status'] = HotelRoomStatus.cleaning.code;
          rm['version'] = rv;
          rm['updated_at'] = now.toIso8601String();
          await txn.update('hotel_rooms', rm, where: 'id = ?', whereArgs: [roomId]);
          await _outbox.enqueue(
            txn: txn, tableName: 'hotel_rooms', rowId: roomId, op: 'update',
            payload: rm, overrideVersion: rv,
          );
        }
      }
    });
  }

  Future<void> addPayment(String stayId, double amount) async {
    if (amount <= 0) return;
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final rows = await txn.query('hotel_stays', where: 'id = ?', whereArgs: [stayId], limit: 1);
      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first);
      final paid = ((map['amount_paid'] as num?)?.toDouble() ?? 0) + amount;
      map['amount_paid'] = paid;
      map['version'] = version;
      map['updated_at'] = now.toIso8601String();
      await txn.update('hotel_stays', map, where: 'id = ?', whereArgs: [stayId]);
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_stays', rowId: stayId, op: 'update',
        payload: map, overrideVersion: version,
      );
    });
  }

  /// Valide pofoma a → li vin yon fakti ofisyèl.
  Future<void> validateProforma(String stayId) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final rows = await txn.query('hotel_stays', where: 'id = ?', whereArgs: [stayId], limit: 1);
      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first);
      map['proforma_validated'] = 1;
      map['version'] = version;
      map['updated_at'] = now.toIso8601String();
      await txn.update('hotel_stays', map, where: 'id = ?', whereArgs: [stayId]);
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_stays', rowId: stayId, op: 'update',
        payload: map, overrideVersion: version,
      );
    });
  }

  /// Efase yon sejou (soft delete). Si l te aktif, libere chanm nan.
  Future<void> deleteStay(String stayId) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final rows = await txn.query('hotel_stays', where: 'id = ?', whereArgs: [stayId], limit: 1);
      if (rows.isEmpty) return;
      final roomId = rows.first['room_id'] as String?;
      final active = (rows.first['status'] as String?) == 'active';
      // Libere chanm nan si sejou a te aktif
      if (roomId != null && active) {
        final rv = _hlc.next();
        final rrows = await txn.query('hotel_rooms', where: 'id = ?', whereArgs: [roomId], limit: 1);
        if (rrows.isNotEmpty) {
          final rm = Map<String, dynamic>.from(rrows.first);
          rm['status'] = HotelRoomStatus.available.code;
          rm['version'] = rv;
          rm['updated_at'] = now.toIso8601String();
          await txn.update('hotel_rooms', rm, where: 'id = ?', whereArgs: [roomId]);
          await _outbox.enqueue(
            txn: txn, tableName: 'hotel_rooms', rowId: roomId, op: 'update',
            payload: rm, overrideVersion: rv,
          );
        }
      }
      await txn.update(
        'hotel_stays',
        {'deleted_at': now.toIso8601String(), 'updated_at': now.toIso8601String(), 'version': version},
        where: 'id = ?', whereArgs: [stayId],
      );
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_stays', rowId: stayId, op: 'delete',
        payload: {'id': stayId}, overrideVersion: version,
      );
    });
  }

  Future<List<HotelStay>> listStays(String storeId, {HotelStayStatus? status}) async {
    final where = StringBuffer('store_id = ? AND (deleted_at IS NULL)');
    final args = <Object?>[storeId];
    if (status != null) {
      where.write(' AND status = ?');
      args.add(status.code);
    }
    final rows = await _db.query(
      'hotel_stays',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
    return rows.map(HotelStay.fromMap).toList();
  }

  Future<HotelStay?> findStay(String id) async {
    final rows = await _db.query('hotel_stays', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return HotelStay.fromMap(rows.first);
  }

  // ───────────────────────── Pofoma (devi milti-chanm) ─────────────────────────

  Future<int> _nextProformaNumber(String storeId) async {
    final r = await _db.rawQuery(
      'SELECT COALESCE(MAX(proforma_number), 0) AS m FROM hotel_proformas WHERE store_id = ?',
      [storeId],
    );
    return ((r.first['m'] as num?)?.toInt() ?? 0) + 1;
  }

  /// Kreye yon pofoma ki SOVE (ak plizyè chanm). Retounen objè a.
  Future<HotelProforma> createProforma({
    required String storeId,
    String? userId,
    String? cashierName,
    String? guestName,
    String? guestPhone,
    String? guestIdDoc,
    required List<HotelProformaItem> items,
    double extra = 0,
    double discount = 0,
    String? notes,
  }) async {
    final now = DateTime.now().toUtc();
    final id = Ulid().toCanonical();
    final number = await _nextProformaNumber(storeId);
    final version = _hlc.next();
    final itemsTotal = items.fold<double>(0, (s, i) => s + i.lineTotal);
    final total = (itemsTotal + extra - discount).clamp(0, double.infinity).toDouble();
    final itemsJson = jsonEncode(items.map((e) => e.toJson()).toList());

    final map = <String, dynamic>{
      'id': id,
      'store_id': storeId,
      'user_id': userId,
      'cashier_name': cashierName,
      'proforma_number': number,
      'guest_name': guestName,
      'guest_phone': guestPhone,
      'guest_id_doc': guestIdDoc,
      'items': itemsJson,
      'extra': extra,
      'discount': discount,
      'total': total,
      'validated': 0,
      'validated_at': null,
      'notes': notes,
      'version': version,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    await _db.transaction((txn) async {
      await txn.insert('hotel_proformas', map);
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_proformas', rowId: id, op: 'create',
        payload: map, overrideVersion: version,
      );
    });
    return HotelProforma.fromMap(map);
  }

  Future<List<HotelProforma>> listProformas(String storeId) async {
    final rows = await _db.query(
      'hotel_proformas',
      where: 'store_id = ? AND (deleted_at IS NULL)',
      whereArgs: [storeId],
      orderBy: 'created_at DESC',
    );
    return rows.map(HotelProforma.fromMap).toList();
  }

  Future<HotelProforma?> findProforma(String id) async {
    final rows = await _db.query('hotel_proformas', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return HotelProforma.fromMap(rows.first);
  }

  /// Valide yon pofoma → li vin yon fakti ofisyèl (si kliyan aksepte).
  Future<void> markProformaValidated(String id) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      final rows = await txn.query('hotel_proformas', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return;
      final map = Map<String, dynamic>.from(rows.first);
      map['validated'] = 1;
      map['validated_at'] = now.toIso8601String();
      map['version'] = version;
      map['updated_at'] = now.toIso8601String();
      await txn.update('hotel_proformas', map, where: 'id = ?', whereArgs: [id]);
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_proformas', rowId: id, op: 'update',
        payload: map, overrideVersion: version,
      );
    });
  }

  Future<void> deleteProforma(String id) async {
    final now = DateTime.now().toUtc();
    final version = _hlc.next();
    await _db.transaction((txn) async {
      await txn.update(
        'hotel_proformas',
        {'deleted_at': now.toIso8601String(), 'updated_at': now.toIso8601String(), 'version': version},
        where: 'id = ?', whereArgs: [id],
      );
      await _outbox.enqueue(
        txn: txn, tableName: 'hotel_proformas', rowId: id, op: 'delete',
        payload: {'id': id}, overrideVersion: version,
      );
    });
  }

  /// Estatistik otèl pou ekran Rapò a.
  Future<Map<String, num>> stats(String storeId) async {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day).toUtc().toIso8601String();

    final r = await _db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END), 0) AS active_stays,
        COALESCE(SUM(CASE WHEN created_at >= ? THEN 1 ELSE 0 END), 0) AS today_count,
        COALESCE(SUM(CASE WHEN created_at >= ? THEN amount_paid ELSE 0 END), 0) AS today_revenue,
        COALESCE(SUM(CASE WHEN status = 'active' THEN (total - amount_paid) ELSE 0 END), 0) AS uncollected
      FROM hotel_stays
      WHERE store_id = ? AND (deleted_at IS NULL)
    ''', [startOfDay, startOfDay, storeId]);

    final rooms = await _db.rawQuery('''
      SELECT
        COUNT(*) AS total_rooms,
        COALESCE(SUM(CASE WHEN status = 'available' THEN 1 ELSE 0 END), 0) AS available,
        COALESCE(SUM(CASE WHEN status = 'occupied' THEN 1 ELSE 0 END), 0) AS occupied
      FROM hotel_rooms
      WHERE store_id = ? AND (deleted_at IS NULL)
    ''', [storeId]);

    final row = r.first;
    final rr = rooms.first;
    return {
      'active_stays': (row['active_stays'] as num?) ?? 0,
      'today_count': (row['today_count'] as num?) ?? 0,
      'today_revenue': (row['today_revenue'] as num?) ?? 0,
      'uncollected': (row['uncollected'] as num?) ?? 0,
      'total_rooms': (rr['total_rooms'] as num?) ?? 0,
      'available': (rr['available'] as num?) ?? 0,
      'occupied': (rr['occupied'] as num?) ?? 0,
    };
  }
}

final hotelRepositoryProvider = Provider<HotelRepository>((ref) {
  final db = ref.watch(databaseProvider).requireValue;
  final outbox = ref.watch(outboxServiceProvider);
  final hlc = ref.watch(hlcProvider).requireValue;
  return HotelRepository(db, outbox, hlc);
});
