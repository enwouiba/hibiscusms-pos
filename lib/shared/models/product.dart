class Product {
  final String id;
  final String? categoryId;
  final String unitId;
  final String name;
  final String? sku;
  final String? barcode;
  final String? description;
  final double price;
  final double cost;
  final double taxRate;
  final bool trackStock;
  final String? imagePath;
  final bool isActive;
  final String version;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Anbake (pa nan tab products) — sòti pa JOIN ak product_stocks
  final double stock;
  final double lowStockAlert;

  const Product({
    required this.id,
    this.categoryId,
    required this.unitId,
    required this.name,
    this.sku,
    this.barcode,
    this.description,
    required this.price,
    this.cost = 0,
    this.taxRate = 0,
    this.trackStock = true,
    this.imagePath,
    this.isActive = true,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.stock = 0,
    this.lowStockAlert = 5,
  });

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        categoryId: m['category_id'] as String?,
        unitId: m['unit_id'] as String,
        name: m['name'] as String,
        sku: m['sku'] as String?,
        barcode: m['barcode'] as String?,
        description: m['description'] as String?,
        price: (m['price'] as num).toDouble(),
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
        taxRate: (m['tax_rate'] as num?)?.toDouble() ?? 0,
        trackStock: ((m['track_stock'] as num?) ?? 1) == 1,
        imagePath: m['image_path'] as String?,
        isActive: ((m['is_active'] as num?) ?? 1) == 1,
        version: m['version'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
        stock: (m['stock'] as num?)?.toDouble() ?? 0,
        lowStockAlert: (m['low_stock_alert'] as num?)?.toDouble() ?? 5,
      );

  /// Map pou tab `products` (san stock).
  Map<String, dynamic> toMap() => {
        'id': id,
        'category_id': categoryId,
        'unit_id': unitId,
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'description': description,
        'price': price,
        'cost': cost,
        'tax_rate': taxRate,
        'track_stock': trackStock ? 1 : 0,
        'image_path': imagePath,
        'is_active': isActive ? 1 : 0,
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  bool get isLowStock => trackStock && stock <= lowStockAlert;

  Product copyWith({
    String? categoryId,
    String? unitId,
    String? name,
    String? sku,
    String? barcode,
    String? description,
    double? price,
    double? cost,
    double? taxRate,
    bool? trackStock,
    String? imagePath,
    bool? isActive,
    String? version,
    DateTime? updatedAt,
    double? stock,
    double? lowStockAlert,
  }) =>
      Product(
        id: id,
        categoryId: categoryId ?? this.categoryId,
        unitId: unitId ?? this.unitId,
        name: name ?? this.name,
        sku: sku ?? this.sku,
        barcode: barcode ?? this.barcode,
        description: description ?? this.description,
        price: price ?? this.price,
        cost: cost ?? this.cost,
        taxRate: taxRate ?? this.taxRate,
        trackStock: trackStock ?? this.trackStock,
        imagePath: imagePath ?? this.imagePath,
        isActive: isActive ?? this.isActive,
        version: version ?? this.version,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        stock: stock ?? this.stock,
        lowStockAlert: lowStockAlert ?? this.lowStockAlert,
      );
}
