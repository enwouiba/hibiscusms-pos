class Customer {
  final String id;
  final String? storeId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final double balance;
  final int loyaltyPoints;
  final String version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Customer({
    required this.id,
    this.storeId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.balance = 0,
    this.loyaltyPoints = 0,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'] as String,
        storeId: m['store_id'] as String?,
        name: m['name'] as String,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        address: m['address'] as String?,
        notes: m['notes'] as String?,
        balance: (m['balance'] as num?)?.toDouble() ?? 0,
        loyaltyPoints: (m['loyalty_points'] as num?)?.toInt() ?? 0,
        version: m['version'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'store_id': storeId,
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'notes': notes,
        'balance': balance,
        'loyalty_points': loyaltyPoints,
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  Customer copyWith({String? name, String? phone, String? email, String? address, String? notes, double? balance, String? version, DateTime? updatedAt}) =>
      Customer(
        id: id,
        storeId: storeId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        notes: notes ?? this.notes,
        balance: balance ?? this.balance,
        loyaltyPoints: loyaltyPoints,
        version: version ?? this.version,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
