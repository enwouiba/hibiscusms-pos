import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class ManagedUser {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final bool isActive;
  final List<UserRole> roles;
  final DateTime? lastLoginAt;

  const ManagedUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.isActive,
    required this.roles,
    this.lastLoginAt,
  });

  String get primaryRoleLabel {
    if (roles.isEmpty) return '—';
    // Pi gwo nivo wòl
    final sorted = [...roles]..sort((a, b) => b.level.compareTo(a.level));
    return sorted.first.label;
  }

  String get primaryRoleName {
    if (roles.isEmpty) return '';
    final sorted = [...roles]..sort((a, b) => b.level.compareTo(a.level));
    return sorted.first.name;
  }

  bool get isSuperAdmin => roles.any((r) => r.name == 'super_admin');
  bool get isAdmin => roles.any((r) => r.name == 'admin');
  bool get isCashier => roles.any((r) => r.name == 'cashier');

  factory ManagedUser.fromJson(Map<String, dynamic> j) {
    // is_active ka rive kòm bool (Laravel JSON) oswa num (SQLite)
    final raw = j['is_active'];
    final isActive = switch (raw) {
      bool b => b,
      num n => n == 1,
      _ => true,
    };
    return ManagedUser(
      id: j['id'] as String,
      name: j['name'] as String,
      email: j['email'] as String,
      phone: j['phone'] as String?,
      isActive: isActive,
      lastLoginAt: j['last_login_at'] != null
          ? DateTime.tryParse(j['last_login_at'] as String)
          : null,
      roles: ((j['roles'] as List?) ?? const [])
          .map((r) => UserRole.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

class UserRole {
  final String name;
  final String label;
  final int level;
  final String? storeId;
  const UserRole({required this.name, required this.label, required this.level, this.storeId});

  factory UserRole.fromJson(Map<String, dynamic> j) => UserRole(
        name: j['name'] as String,
        label: j['label'] as String,
        level: (j['level'] as num).toInt(),
        storeId: (j['pivot'] as Map?)?['store_id'] as String?,
      );
}

class UserRepository {
  UserRepository(this._api);
  final ApiClient _api;

  Future<List<ManagedUser>> list({String? roleFilter}) async {
    try {
      final res = await _api.dio.get('/api/users', queryParameters: {
        'per_page': 100,
      });
      final data = (res.data['data'] as List).cast<Map<String, dynamic>>();
      var users = data.map(ManagedUser.fromJson).toList();
      if (roleFilter != null) {
        users = users.where((u) => u.roles.any((r) => r.name == roleFilter)).toList();
      }
      return users;
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message ?? 'Erè rezo');
    }
  }

  Future<ManagedUser> create({
    required String name,
    required String email,
    required String password,
    String? phone,
    required String roleName, // 'cashier', 'admin', 'super_admin'
    String? storeId, // null pou super_admin
  }) async {
    try {
      final res = await _api.dio.post('/api/users', data: {
        'name': name,
        'email': email,
        'password': password,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'role_assignments': [
          {
            'role_name': roleName,
            if (storeId != null) 'store_id': storeId,
          }
        ],
      });
      return ManagedUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? e.message ?? 'Erè rezo';
      final errors = e.response?.data['errors'] as Map?;
      final firstError = errors?.values.firstOrNull;
      throw Exception(firstError is List ? firstError.first : msg);
    }
  }

  Future<void> update(String userId, {
    String? name,
    String? email,
    String? phone,
    String? password,
    bool? isActive,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (email != null) body['email'] = email;
      if (phone != null) body['phone'] = phone;
      if (password != null && password.isNotEmpty) body['password'] = password;
      if (isActive != null) body['is_active'] = isActive;
      if (body.isEmpty) return;
      await _api.dio.patch('/api/users/$userId', data: body);
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? e.message ?? 'Erè rezo';
      final errors = e.response?.data['errors'] as Map?;
      final firstError = errors?.values.firstOrNull;
      throw Exception(firstError is List ? firstError.first : msg);
    }
  }

  /// Fetch enfòmasyon itilizatè aktyèl la
  Future<ManagedUser> me() async {
    try {
      final res = await _api.dio.get('/api/auth/me');
      final user = res.data['user'] as Map<String, dynamic>;
      final roles = (res.data['roles'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return ManagedUser.fromJson({...user, 'roles': roles});
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message ?? 'Erè rezo');
    }
  }

  Future<void> delete(String userId) async {
    try {
      await _api.dio.delete('/api/users/$userId');
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message ?? 'Erè rezo');
    }
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(ref.watch(apiClientProvider));
});
