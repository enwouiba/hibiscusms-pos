class Category {
  final String id;
  final String? storeId;
  final String? parentId;
  final String name;
  final int color;
  final String? icon;
  final int sortOrder;
  final String version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Category({
    required this.id,
    this.storeId,
    this.parentId,
    required this.name,
    this.color = 0xFF455A64,
    this.icon,
    this.sortOrder = 0,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        id: m['id'] as String,
        storeId: m['store_id'] as String?,
        parentId: m['parent_id'] as String?,
        name: m['name'] as String,
        color: (m['color'] as num?)?.toInt() ?? 0xFF455A64,
        icon: m['icon'] as String?,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        version: m['version'] as String,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'store_id': storeId,
        'parent_id': parentId,
        'name': name,
        'color': color,
        'icon': icon,
        'sort_order': sortOrder,
        'version': version,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  Category copyWith({String? name, int? color, int? sortOrder, String? version, DateTime? updatedAt}) =>
      Category(
        id: id,
        storeId: storeId,
        parentId: parentId,
        name: name ?? this.name,
        color: color ?? this.color,
        icon: icon,
        sortOrder: sortOrder ?? this.sortOrder,
        version: version ?? this.version,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
