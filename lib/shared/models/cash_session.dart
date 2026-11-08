class CashSession {
  final String id;
  final String storeId;
  final String userId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingBalance;
  final double? closingBalance;
  final double? expectedBalance;
  final double? difference;
  final double totalSales;
  final double totalCash;
  final String? notes;
  final String version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CashSession({
    required this.id,
    required this.storeId,
    required this.userId,
    required this.openedAt,
    this.closedAt,
    this.openingBalance = 0,
    this.closingBalance,
    this.expectedBalance,
    this.difference,
    this.totalSales = 0,
    this.totalCash = 0,
    this.notes,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOpen => closedAt == null;

  factory CashSession.fromMap(Map<String, dynamic> m) => CashSession(
        id: m['id'] as String,
        storeId: m['store_id'] as String,
        userId: m['user_id'] as String,
        openedAt: DateTime.parse(m['opened_at'] as String),
        closedAt: m['closed_at'] != null ? DateTime.parse(m['closed_at'] as String) : null,
        openingBalance: (m['opening_balance'] as num?)?.toDouble() ?? 0,
        closingBalance: (m['closing_balance'] as num?)?.toDouble(),
        expectedBalance: (m['expected_balance'] as num?)?.toDouble(),
        difference: (m['difference'] as num?)?.toDouble(),
        totalSales: (m['total_sales'] as num?)?.toDouble() ?? 0,
        totalCash: (m['total_cash'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String?,
        version: m['version'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'store_id': storeId,
        'user_id': userId,
        'opened_at': openedAt.toUtc().toIso8601String(),
        'closed_at': closedAt?.toUtc().toIso8601String(),
        'opening_balance': openingBalance,
        'closing_balance': closingBalance,
        'expected_balance': expectedBalance,
        'difference': difference,
        'total_sales': totalSales,
        'total_cash': totalCash,
        'notes': notes,
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}
