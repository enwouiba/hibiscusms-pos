// Modèl pou jesyon otèl — chanm ak sejou (check-in / check-out).
//
// De mòd lwaye:
//   • Pa nwit  — pri_pa_nwit × kantite nwit
//   • Pa èdtan — pri_pa_èdtan × kantite èdtan (1h, 2h, 3h...)
// Dire a chwazi nan check-in (mòd 2a), total = tarif × dire (mòd 1a).

/// Estati yon chanm.
enum HotelRoomStatus {
  available('available', 'Lib', '🟢'),
  occupied('occupied', 'Okipe', '🔴'),
  cleaning('cleaning', 'Netwayaj', '🧹');

  final String code;
  final String label;
  final String emoji;
  const HotelRoomStatus(this.code, this.label, this.emoji);

  static HotelRoomStatus fromCode(String? code) => HotelRoomStatus.values
      .firstWhere((s) => s.code == code, orElse: () => HotelRoomStatus.available);
}

/// Mòd lwaye yon sejou.
enum HotelRentalMode {
  hourly('hourly', 'Pa èdtan', '⏱️', 'èdtan'),
  nightly('nightly', 'Pa nwit', '🌙', 'nwit');

  final String code;
  final String label;
  final String emoji;
  final String unit; // non inite a pou afichaj (egz. "3 èdtan")
  const HotelRentalMode(this.code, this.label, this.emoji, this.unit);

  static HotelRentalMode fromCode(String? code) => HotelRentalMode.values
      .firstWhere((m) => m.code == code, orElse: () => HotelRentalMode.nightly);
}

/// Estati yon sejou.
enum HotelStayStatus {
  active('active', 'Anndan', '🟢'),
  completed('completed', 'Soti', '✅');

  final String code;
  final String label;
  final String emoji;
  const HotelStayStatus(this.code, this.label, this.emoji);

  static HotelStayStatus fromCode(String? code) => HotelStayStatus.values
      .firstWhere((s) => s.code == code, orElse: () => HotelStayStatus.active);
}

class HotelRoom {
  final String id;
  final String storeId;
  final String name; // nimewo/non chanm, egz. "Chanm 101"
  final String? roomType; // egz. "Standard", "VIP"
  final double pricePerNight;
  final double pricePerHour;
  final HotelRoomStatus status;
  final String? notes;
  final DateTime createdAt;

  const HotelRoom({
    required this.id,
    required this.storeId,
    required this.name,
    this.roomType,
    required this.pricePerNight,
    required this.pricePerHour,
    this.status = HotelRoomStatus.available,
    this.notes,
    required this.createdAt,
  });

  bool get isAvailable => status == HotelRoomStatus.available;

  /// Chanm « Moman » (lwaye pa èdtan/moman) kont chanm « Nwit ».
  /// Make eksplisit pa `room_type`, oswa dedwi: sèlman pri/èdtan = Moman.
  bool get isMoman =>
      roomType == 'Moman' || (pricePerNight <= 0 && pricePerHour > 0);

  factory HotelRoom.fromMap(Map<String, dynamic> m) => HotelRoom(
        id: m['id'] as String,
        storeId: m['store_id'] as String,
        name: m['name'] as String,
        roomType: m['room_type'] as String?,
        pricePerNight: (m['price_per_night'] as num?)?.toDouble() ?? 0,
        pricePerHour: (m['price_per_hour'] as num?)?.toDouble() ?? 0,
        status: HotelRoomStatus.fromCode(m['status'] as String?),
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

class HotelStay {
  final String id;
  final String storeId;
  final String? userId;
  final String? cashierName;
  final String roomId;
  final String roomNameSnapshot;
  final String? guestName;
  final String? guestPhone;
  final String? guestIdDoc; // NIF/CIN kliyan
  final HotelRentalMode mode;
  final int duration; // kantite èdtan oswa nwit (chwazi nan check-in)
  final double rate; // tarif pa inite nan moman check-in (snapshot)
  final int stayNumber;
  final HotelStayStatus status;
  final DateTime checkInAt;
  final DateTime? checkOutAt;
  final double extra; // chaj anplis (sèvis, elatriye)
  final double discount;
  final double total;
  final double amountPaid;
  final String? notes;
  final DateTime createdAt;

  const HotelStay({
    required this.id,
    required this.storeId,
    this.userId,
    this.cashierName,
    required this.roomId,
    required this.roomNameSnapshot,
    this.guestName,
    this.guestPhone,
    this.guestIdDoc,
    required this.mode,
    required this.duration,
    required this.rate,
    required this.stayNumber,
    this.status = HotelStayStatus.active,
    required this.checkInAt,
    this.checkOutAt,
    this.extra = 0,
    this.discount = 0,
    required this.total,
    this.amountPaid = 0,
    this.notes,
    required this.createdAt,
  });

  double get roomCharge => rate * duration;
  double get amountDue => (total - amountPaid).clamp(0, double.infinity).toDouble();

  /// Lè sejou a dwe fini selon dire ki chwazi a (check-in + dire).
  DateTime get plannedEndAt => mode == HotelRentalMode.hourly
      ? checkInAt.add(Duration(hours: duration))
      : checkInAt.add(Duration(days: duration));

  factory HotelStay.fromMap(Map<String, dynamic> m) => HotelStay(
        id: m['id'] as String,
        storeId: m['store_id'] as String,
        userId: m['user_id'] as String?,
        cashierName: m['cashier_name'] as String?,
        roomId: m['room_id'] as String,
        roomNameSnapshot: m['room_name_snapshot'] as String? ?? '',
        guestName: m['guest_name'] as String?,
        guestPhone: m['guest_phone'] as String?,
        guestIdDoc: m['guest_id_doc'] as String?,
        mode: HotelRentalMode.fromCode(m['mode'] as String?),
        duration: (m['duration'] as num?)?.toInt() ?? 1,
        rate: (m['rate'] as num?)?.toDouble() ?? 0,
        stayNumber: (m['stay_number'] as num?)?.toInt() ?? 0,
        status: HotelStayStatus.fromCode(m['status'] as String?),
        checkInAt: DateTime.parse(m['check_in_at'] as String),
        checkOutAt: m['check_out_at'] != null
            ? DateTime.tryParse(m['check_out_at'] as String)
            : null,
        extra: (m['extra'] as num?)?.toDouble() ?? 0,
        discount: (m['discount'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        amountPaid: (m['amount_paid'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}
