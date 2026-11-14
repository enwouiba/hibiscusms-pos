import 'dart:convert';

class Store {
  final String id;
  final String name;
  final String code;
  final String? address;
  final String? phone;
  final String currency;
  final String timezone;
  final bool isActive;
  final Map<String, dynamic> settings;
  final String version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Store({
    required this.id,
    required this.name,
    required this.code,
    this.address,
    this.phone,
    this.currency = 'HTG',
    this.timezone = 'America/Port-au-Prince',
    this.isActive = true,
    this.settings = const {},
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  // Shortcuts pou settings JSON
  String? get footerText => settings['footer_text'] as String?;
  String? get email => settings['email'] as String?;
  String? get nif => settings['nif'] as String?;

  /// Tip biznis magazen an: 'retail' (vant pwodwi), 'drycleaning' (netwayaj)
  /// oswa 'hotel' (jesyon chanm otèl).
  String get type => (settings['type'] as String?) ?? 'retail';
  bool get isDryCleaning => type == 'drycleaning';
  bool get isHotel => type == 'hotel';
  String? get website => settings['website'] as String?;

  factory Store.fromMap(Map<String, dynamic> m) {
    Map<String, dynamic> settings = {};
    final rawSettings = m['settings'];
    if (rawSettings is String && rawSettings.isNotEmpty) {
      try {
        settings = jsonDecode(rawSettings) as Map<String, dynamic>;
      } catch (_) {}
    } else if (rawSettings is Map) {
      settings = Map<String, dynamic>.from(rawSettings);
    }
    return Store(
      id: m['id'] as String,
      name: m['name'] as String,
      code: m['code'] as String,
      address: m['address'] as String?,
      phone: m['phone'] as String?,
      currency: (m['currency'] as String?) ?? 'HTG',
      timezone: (m['timezone'] as String?) ?? 'America/Port-au-Prince',
      isActive: ((m['is_active'] as num?) ?? 1) == 1,
      settings: settings,
      version: m['version'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'address': address,
        'phone': phone,
        'currency': currency,
        'timezone': timezone,
        'is_active': isActive ? 1 : 0,
        'settings': jsonEncode(settings),
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  Store copyWith({
    String? name,
    String? address,
    String? phone,
    String? currency,
    Map<String, dynamic>? settings,
    String? version,
    DateTime? updatedAt,
  }) =>
      Store(
        id: id,
        name: name ?? this.name,
        code: code,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        currency: currency ?? this.currency,
        timezone: timezone,
        isActive: isActive,
        settings: settings ?? this.settings,
        version: version ?? this.version,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
