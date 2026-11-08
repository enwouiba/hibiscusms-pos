class Supplier {
  final String id;
  final String? storeId;
  final String name;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final double balance;
  final String version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Supplier({
    required this.id,
    this.storeId,
    required this.name,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.balance = 0,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Supplier.fromMap(Map<String, dynamic> m) => Supplier(
        id: m['id'] as String,
        storeId: m['store_id'] as String?,
        name: m['name'] as String,
        contactName: m['contact_name'] as String?,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        address: m['address'] as String?,
        notes: m['notes'] as String?,
        balance: (m['balance'] as num?)?.toDouble() ?? 0,
        version: m['version'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'store_id': storeId,
        'name': name,
        'contact_name': contactName,
        'phone': phone,
        'email': email,
        'address': address,
        'notes': notes,
        'balance': balance,
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  Supplier copyWith({String? name, String? contactName, String? phone, String? email, String? address, String? notes, double? balance, String? version, DateTime? updatedAt}) =>
      Supplier(
        id: id,
        storeId: storeId,
        name: name ?? this.name,
        contactName: contactName ?? this.contactName,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        notes: notes ?? this.notes,
        balance: balance ?? this.balance,
        version: version ?? this.version,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
