enum PurchaseStatus {
  draft('draft', 'Bouyon'),
  received('received', 'Resevwa'),
  cancelled('cancelled', 'Anile');

  final String code;
  final String label;
  const PurchaseStatus(this.code, this.label);

  static PurchaseStatus fromCode(String code) =>
      PurchaseStatus.values.firstWhere((s) => s.code == code, orElse: () => PurchaseStatus.received);
}

class PurchaseItem {
  final String id;
  final String purchaseId;
  final String productId;
  final String nameSnapshot;
  final double quantity;
  final double cost;
  final double subtotal;

  const PurchaseItem({
    required this.id,
    required this.purchaseId,
    required this.productId,
    required this.nameSnapshot,
    required this.quantity,
    required this.cost,
    required this.subtotal,
  });

  factory PurchaseItem.fromMap(Map<String, dynamic> m) => PurchaseItem(
        id: m['id'] as String,
        purchaseId: m['purchase_id'] as String,
        productId: m['product_id'] as String,
        nameSnapshot: m['name_snapshot'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        cost: (m['cost'] as num).toDouble(),
        subtotal: (m['subtotal'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'purchase_id': purchaseId,
        'product_id': productId,
        'name_snapshot': nameSnapshot,
        'quantity': quantity,
        'cost': cost,
        'subtotal': subtotal,
      };
}

class Purchase {
  final String id;
  final String storeId;
  final String? supplierId;
  final String userId;
  final String? invoiceNumber;
  final int purchaseNumber;
  final double subtotal;
  final double tax;
  final double total;
  final double amountPaid;
  final PurchaseStatus status;
  final String? notes;
  final String version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PurchaseItem> items;
  final String? supplierName;

  const Purchase({
    required this.id,
    required this.storeId,
    this.supplierId,
    required this.userId,
    this.invoiceNumber,
    required this.purchaseNumber,
    required this.subtotal,
    this.tax = 0,
    required this.total,
    this.amountPaid = 0,
    this.status = PurchaseStatus.received,
    this.notes,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.supplierName,
  });

  factory Purchase.fromMap(Map<String, dynamic> m, {List<PurchaseItem>? items, String? supplierName}) => Purchase(
        id: m['id'] as String,
        storeId: m['store_id'] as String,
        supplierId: m['supplier_id'] as String?,
        userId: m['user_id'] as String,
        invoiceNumber: m['invoice_number'] as String?,
        purchaseNumber: (m['purchase_number'] as num).toInt(),
        subtotal: (m['subtotal'] as num).toDouble(),
        tax: (m['tax'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num).toDouble(),
        amountPaid: (m['amount_paid'] as num?)?.toDouble() ?? 0,
        status: PurchaseStatus.fromCode((m['status'] as String?) ?? 'received'),
        notes: m['notes'] as String?,
        version: m['version'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
        items: items ?? const [],
        supplierName: supplierName,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'store_id': storeId,
        'supplier_id': supplierId,
        'user_id': userId,
        'invoice_number': invoiceNumber,
        'purchase_number': purchaseNumber,
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'amount_paid': amountPaid,
        'status': status.code,
        'notes': notes,
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}
