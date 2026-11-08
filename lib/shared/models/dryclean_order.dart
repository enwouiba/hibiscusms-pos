/// Modèl pou dry cleaning — yon lòd ak rad li yo.

enum DrycleanStatus {
  received('received', 'Resevwa', '📥'),
  inProgress('in_progress', 'Ap travay', '🧼'),
  ready('ready', 'Pare', '✅'),
  completed('completed', 'Ranmase', '📤');

  final String code;
  final String label;
  final String emoji;
  const DrycleanStatus(this.code, this.label, this.emoji);

  static DrycleanStatus fromCode(String? code) =>
      DrycleanStatus.values.firstWhere((s) => s.code == code, orElse: () => DrycleanStatus.received);

  /// Pwochen etap nan pwosesis la (null si deja ranmase).
  DrycleanStatus? get next => switch (this) {
        DrycleanStatus.received => DrycleanStatus.inProgress,
        DrycleanStatus.inProgress => DrycleanStatus.ready,
        DrycleanStatus.ready => DrycleanStatus.completed,
        DrycleanStatus.completed => null,
      };
}

class DrycleanOrderItem {
  final String id;
  final String orderId;
  final String? storeId;
  final String? productId;
  final String nameSnapshot;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
  final String? tagNumber;
  final String? conditionNotes;

  const DrycleanOrderItem({
    required this.id,
    required this.orderId,
    this.storeId,
    this.productId,
    required this.nameSnapshot,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.tagNumber,
    this.conditionNotes,
  });

  factory DrycleanOrderItem.fromMap(Map<String, dynamic> m) => DrycleanOrderItem(
        id: m['id'] as String,
        orderId: m['order_id'] as String,
        storeId: m['store_id'] as String?,
        productId: m['product_id'] as String?,
        nameSnapshot: m['name_snapshot'] as String,
        quantity: (m['quantity'] as num?)?.toDouble() ?? 1,
        unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0,
        lineTotal: (m['line_total'] as num?)?.toDouble() ?? 0,
        tagNumber: m['tag_number'] as String?,
        conditionNotes: m['condition_notes'] as String?,
      );
}

class DrycleanOrder {
  final String id;
  final String storeId;
  final String? userId;
  final String? cashierName;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final int orderNumber;
  final DrycleanStatus status;
  final String? rackLocation;
  final DateTime? readyDate;
  final double subtotal;
  final double discount;
  final double total;
  final double amountPaid;
  final String? notes;
  final DateTime createdAt;
  final DateTime? completedAt;
  final List<DrycleanOrderItem> items;

  const DrycleanOrder({
    required this.id,
    required this.storeId,
    this.userId,
    this.cashierName,
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.orderNumber,
    required this.status,
    this.rackLocation,
    this.readyDate,
    required this.subtotal,
    this.discount = 0,
    required this.total,
    this.amountPaid = 0,
    this.notes,
    required this.createdAt,
    this.completedAt,
    this.items = const [],
  });

  double get amountDue => (total - amountPaid).clamp(0, double.infinity).toDouble();
  int get itemCount => items.fold(0, (s, i) => s + i.quantity.round());

  factory DrycleanOrder.fromMap(Map<String, dynamic> m, {List<DrycleanOrderItem> items = const []}) => DrycleanOrder(
        id: m['id'] as String,
        storeId: m['store_id'] as String,
        userId: m['user_id'] as String?,
        cashierName: m['cashier_name'] as String?,
        customerId: m['customer_id'] as String?,
        customerName: m['customer_name'] as String?,
        customerPhone: m['customer_phone'] as String?,
        orderNumber: (m['order_number'] as num).toInt(),
        status: DrycleanStatus.fromCode(m['status'] as String?),
        rackLocation: m['rack_location'] as String?,
        readyDate: m['ready_date'] != null ? DateTime.tryParse(m['ready_date'] as String) : null,
        subtotal: (m['subtotal'] as num?)?.toDouble() ?? 0,
        discount: (m['discount'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num?)?.toDouble() ?? 0,
        amountPaid: (m['amount_paid'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        completedAt: m['completed_at'] != null ? DateTime.tryParse(m['completed_at'] as String) : null,
        items: items,
      );
}
