enum StockMovementType {
  sale('sale', 'Vant', -1),
  purchase('purchase', 'Acha', 1),
  adjust('adjust', 'Ajiste', 0),
  transferIn('transfer_in', 'Tranfè antre', 1),
  transferOut('transfer_out', 'Tranfè soti', -1),
  returnIn('return', 'Retounen', 1),
  damage('damage', 'Domaj', -1);

  final String code;
  final String label;
  final int defaultSign;
  const StockMovementType(this.code, this.label, this.defaultSign);

  static StockMovementType fromCode(String code) =>
      StockMovementType.values.firstWhere((t) => t.code == code, orElse: () => StockMovementType.adjust);
}

class StockMovement {
  final String id;
  final String storeId;
  final String productId;
  final String? userId;
  final StockMovementType type;
  final double quantity;
  final double balanceAfter;
  final double? costAtTime;
  final String? referenceType;
  final String? referenceId;
  final String? notes;
  final String version;
  final DateTime createdAt;
  final String? productName;
  final String? userName;

  const StockMovement({
    required this.id,
    required this.storeId,
    required this.productId,
    this.userId,
    required this.type,
    required this.quantity,
    required this.balanceAfter,
    this.costAtTime,
    this.referenceType,
    this.referenceId,
    this.notes,
    required this.version,
    required this.createdAt,
    this.productName,
    this.userName,
  });

  factory StockMovement.fromMap(Map<String, dynamic> m, {String? productName, String? userName}) => StockMovement(
        id: m['id'] as String,
        storeId: m['store_id'] as String,
        productId: m['product_id'] as String,
        userId: m['user_id'] as String?,
        type: StockMovementType.fromCode(m['type'] as String),
        quantity: (m['quantity'] as num).toDouble(),
        balanceAfter: (m['balance_after'] as num).toDouble(),
        costAtTime: (m['cost_at_time'] as num?)?.toDouble(),
        referenceType: m['reference_type'] as String?,
        referenceId: m['reference_id'] as String?,
        notes: m['notes'] as String?,
        version: m['version'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        productName: productName ?? m['product_name'] as String?,
        userName: userName ?? m['user_name'] as String?,
      );
}
