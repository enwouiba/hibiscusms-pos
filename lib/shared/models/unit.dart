class Unit {
  final String id;
  final String code;
  final String name;
  final int decimals;

  const Unit({
    required this.id,
    required this.code,
    required this.name,
    this.decimals = 0,
  });

  factory Unit.fromMap(Map<String, dynamic> m) => Unit(
        id: m['id'] as String,
        code: m['code'] as String,
        name: m['name'] as String,
        decimals: (m['decimals'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'name': name,
        'decimals': decimals,
      };
}
