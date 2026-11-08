import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

class TenantInfo {
  final String id;
  final String name;
  final String slug;
  final String plan;
  final String status;
  final String? logoPath;
  final DateTime? expiresAt;
  final int daysRemaining;

  const TenantInfo({
    required this.id,
    required this.name,
    required this.slug,
    required this.plan,
    required this.status,
    this.logoPath,
    this.expiresAt,
    this.daysRemaining = 99999,
  });

  String get planLabel => switch (plan) {
        'free_18m' => '18 Mwa Gratis',
        'free' => 'Gratis',
        'basic' => 'Basic',
        'pro' => 'Pro',
        'premium' => 'Premium',
        _ => plan,
      };

  bool get isExpiringSoon => daysRemaining <= 30;
  bool get isExpired => daysRemaining <= 0;

  factory TenantInfo.fromJson(Map<String, dynamic> json) => TenantInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        plan: (json['plan'] as String?) ?? 'free',
        status: (json['status'] as String?) ?? 'active',
        logoPath: json['logo_path'] as String?,
        expiresAt: json['expires_at'] != null
            ? DateTime.tryParse(json['expires_at'] as String)
            : null,
        daysRemaining: (json['days_remaining'] as num?)?.toInt() ?? 99999,
      );
}

class StoreSummary {
  final String id;
  final String name;
  final String code;
  final String currency;

  const StoreSummary({required this.id, required this.name, required this.code, required this.currency});

  factory StoreSummary.fromJson(Map<String, dynamic> json) => StoreSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
        currency: (json['currency'] as String?) ?? 'HTG',
      );
}

class RoleAssignment {
  final String name;
  final String label;
  final int level;
  final String? storeId;

  const RoleAssignment({required this.name, required this.label, required this.level, this.storeId});

  factory RoleAssignment.fromJson(Map<String, dynamic> json) => RoleAssignment(
        name: json['name'] as String,
        label: json['label'] as String,
        level: (json['level'] as num).toInt(),
        storeId: json['store_id'] as String?,
      );

  bool get isSuperAdmin => name == 'super_admin';
  bool get isAdmin => name == 'admin';
  bool get isCashier => name == 'cashier';
  bool get isSystemOwner => name == 'system_owner';
}

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String locale;
  final String? avatarPath;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.locale,
    this.avatarPath,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        locale: (json['locale'] as String?) ?? 'ht',
        avatarPath: json['avatar_path'] as String?,
      );
}

class AuthSession {
  final AuthUser user;
  final TenantInfo? tenant;
  final List<RoleAssignment> roles;
  final List<StoreSummary> stores;

  const AuthSession({required this.user, this.tenant, required this.roles, required this.stores});

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
      tenant: json['tenant'] != null
          ? TenantInfo.fromJson(json['tenant'] as Map<String, dynamic>)
          : null,
      roles: ((json['roles'] as List?) ?? const [])
          .map((e) => RoleAssignment.fromJson(e as Map<String, dynamic>))
          .toList(),
      stores: ((json['stores'] as List?) ?? const [])
          .map((e) => StoreSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  bool get isSuperAdmin => roles.any((r) => r.isSuperAdmin);
  bool get isSystemOwner => roles.any((r) => r.isSystemOwner);

  /// Wòl ki pi wo nan kontèks yon magazen (oswa global pou Super Admin).
  int highestLevel(String? storeId) {
    if (isSuperAdmin) return 3;
    return roles
        .where((r) => storeId == null || r.storeId == storeId)
        .fold<int>(0, (max, r) => r.level > max ? r.level : max);
  }

  bool canForStore(String storeId, {required int minLevel}) {
    return highestLevel(storeId) >= minLevel;
  }
}

class AuthController extends StateNotifier<AsyncValue<AuthSession?>> {
  AuthController(this._service) : super(const AsyncValue.loading()) {
    _restore();
  }
  final AuthService _service;

  Future<void> _restore() async {
    final session = await _service.restore();
    state = AsyncValue.data(session);
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncValue.loading();
    try {
      final session = await _service.login(email: email, password: password);
      state = AsyncValue.data(session);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> logout() async {
    await _service.logout();
    state = const AsyncValue.data(null);
  }

  Future<void> loginOffline({
    required String storeName,
    required String adminName,
    required String adminEmail,
  }) async {
    state = const AsyncValue.loading();
    try {
      final session = await _service.loginOffline(
        storeName: storeName,
        adminName: adminName,
        adminEmail: adminEmail,
      );
      state = AsyncValue.data(session);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> setActiveStore(String storeId) async {
    await _service.setActiveStore(storeId);
  }

  Future<void> register({
    required String businessName,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
    String? adminPhone,
    String? businessPhone,
    String? storeName,
  }) async {
    state = const AsyncValue.loading();
    try {
      final session = await _service.register(
        businessName: businessName,
        adminName: adminName,
        adminEmail: adminEmail,
        adminPassword: adminPassword,
        adminPhone: adminPhone,
        businessPhone: businessPhone,
        storeName: storeName,
      );
      state = AsyncValue.data(session);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AuthSession?>>((ref) {
  return AuthController(ref.watch(authServiceProvider));
});
