enum PaymentMethod {
  cash('cash', 'Kach'),
  monCash('mon_cash', 'Moncash'),
  natcash('natcash', 'Natcash'),
  card('card', 'Kat'),
  bankTransfer('bank_transfer', 'Vire bank'),
  credit('credit', 'Kredite'),
  check('check', 'Chèk');

  final String code;
  final String label;
  const PaymentMethod(this.code, this.label);

  static PaymentMethod fromCode(String code) =>
      PaymentMethod.values.firstWhere((m) => m.code == code, orElse: () => PaymentMethod.cash);
}

enum SaleStatus {
  completed('completed', 'Konplete'),
  refunded('refunded', 'Ranbouse'),
  cancelled('cancelled', 'Anile'),
  credit('credit', 'Kredite');

  final String code;
  final String label;
  const SaleStatus(this.code, this.label);

  static SaleStatus fromCode(String code) =>
      SaleStatus.values.firstWhere((s) => s.code == code, orElse: () => SaleStatus.completed);
}

class SaleItem {
  final String id;
  final String saleId;
  final String? productId;
  final String nameSnapshot;
  final String? skuSnapshot;
  final double priceSnapshot;
  final double costSnapshot;
  final double taxRateSnapshot;
  final double quantity;
  final double discount;
  final double subtotal;

  const SaleItem({
    required this.id,
    required this.saleId,
    this.productId,
    required this.nameSnapshot,
    this.skuSnapshot,
    required this.priceSnapshot,
    this.costSnapshot = 0,
    this.taxRateSnapshot = 0,
    required this.quantity,
    this.discount = 0,
    required this.subtotal,
  });

  factory SaleItem.fromMap(Map<String, dynamic> m) => SaleItem(
        id: m['id'] as String,
        saleId: m['sale_id'] as String,
        productId: m['product_id'] as String?,
        nameSnapshot: m['name_snapshot'] as String,
        skuSnapshot: m['sku_snapshot'] as String?,
        priceSnapshot: (m['price_snapshot'] as num).toDouble(),
        costSnapshot: (m['cost_snapshot'] as num?)?.toDouble() ?? 0,
        taxRateSnapshot: (m['tax_rate_snapshot'] as num?)?.toDouble() ?? 0,
        quantity: (m['quantity'] as num).toDouble(),
        discount: (m['discount'] as num?)?.toDouble() ?? 0,
        subtotal: (m['subtotal'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'sale_id': saleId,
        'product_id': productId,
        'name_snapshot': nameSnapshot,
        'sku_snapshot': skuSnapshot,
        'price_snapshot': priceSnapshot,
        'cost_snapshot': costSnapshot,
        'tax_rate_snapshot': taxRateSnapshot,
        'quantity': quantity,
        'discount': discount,
        'subtotal': subtotal,
      };
}

class Payment {
  final String id;
  final String? saleId;
  final String? purchaseId;
  final String userId;
  final PaymentMethod method;
  final double amount;
  final String? reference;
  final String? notes;
  final String version;
  final DateTime createdAt;

  const Payment({
    required this.id,
    this.saleId,
    this.purchaseId,
    required this.userId,
    required this.method,
    required this.amount,
    this.reference,
    this.notes,
    required this.version,
    required this.createdAt,
  });

  factory Payment.fromMap(Map<String, dynamic> m) => Payment(
        id: m['id'] as String,
        saleId: m['sale_id'] as String?,
        purchaseId: m['purchase_id'] as String?,
        userId: m['user_id'] as String,
        method: PaymentMethod.fromCode(m['method'] as String),
        amount: (m['amount'] as num).toDouble(),
        reference: m['reference'] as String?,
        notes: m['notes'] as String?,
        version: m['version'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'sale_id': saleId,
        'purchase_id': purchaseId,
        'user_id': userId,
        'method': method.code,
        'amount': amount,
        'reference': reference,
        'notes': notes,
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

class Sale {
  final String id;
  final String storeId;
  final String userId;
  final String? cashierName; // non kèsye ki fè vant la
  final String? customerId;
  final String? cashSessionId;
  final int saleNumber;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double? amountReceived;
  final double? changeDue;
  final double amountDue;
  final SaleStatus status;
  final String? notes;
  final String version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SaleItem> items;
  final List<Payment> payments;
  final String? customerName;

  const Sale({
    required this.id,
    required this.storeId,
    required this.userId,
    this.cashierName,
    this.customerId,
    this.cashSessionId,
    required this.saleNumber,
    required this.subtotal,
    this.discount = 0,
    this.tax = 0,
    required this.total,
    this.amountReceived,
    this.changeDue,
    this.amountDue = 0,
    this.status = SaleStatus.completed,
    this.notes,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.items = const [],
    this.payments = const [],
    this.customerName,
  });

  factory Sale.fromMap(Map<String, dynamic> m, {List<SaleItem>? items, List<Payment>? payments, String? customerName}) => Sale(
        id: m['id'] as String,
        storeId: m['store_id'] as String,
        userId: m['user_id'] as String,
        cashierName: m['cashier_name'] as String?,
        customerId: m['customer_id'] as String?,
        cashSessionId: m['cash_session_id'] as String?,
        saleNumber: (m['sale_number'] as num).toInt(),
        subtotal: (m['subtotal'] as num).toDouble(),
        discount: (m['discount'] as num?)?.toDouble() ?? 0,
        tax: (m['tax'] as num?)?.toDouble() ?? 0,
        total: (m['total'] as num).toDouble(),
        amountReceived: (m['amount_received'] as num?)?.toDouble(),
        changeDue: (m['change_due'] as num?)?.toDouble(),
        amountDue: (m['amount_due'] as num?)?.toDouble() ?? 0,
        status: SaleStatus.fromCode((m['status'] as String?) ?? 'completed'),
        notes: m['notes'] as String?,
        version: m['version'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
        items: items ?? const [],
        payments: payments ?? const [],
        customerName: customerName,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'store_id': storeId,
        'user_id': userId,
        'cashier_name': cashierName,
        'customer_id': customerId,
        'cash_session_id': cashSessionId,
        'sale_number': saleNumber,
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'total': total,
        'amount_received': amountReceived,
        'change_due': changeDue,
        'amount_due': amountDue,
        'status': status.code,
        'notes': notes,
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  PaymentMethod get primaryPaymentMethod =>
      payments.isNotEmpty ? payments.first.method : PaymentMethod.cash;
}
