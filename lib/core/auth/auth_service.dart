import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ulid/ulid.dart';

import '../network/api_client.dart';
import 'auth_state.dart';
import 'token_store.dart';

class AuthService {
  AuthService(this._api, this._tokenStore);
  final ApiClient _api;
  final TokenStore _tokenStore;

  Future<AuthSession> login({
    required String email,
    required String password,
    String? deviceName,
  }) async {
    final deviceId = await _tokenStore.deviceId() ?? Ulid().toCanonical();
    final platform = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'web');

    final res = await _api.dio.post('/api/auth/login', data: {
      'email': email.trim(),
      'password': password,
      'device_id': deviceId,
      'device_name': deviceName ?? 'Aparèy Kinkayri POS',
      'platform': platform,
      'app_version': '1.0.0',
    });

    final data = res.data as Map<String, dynamic>;
    await _tokenStore.save(
      token: data['token'] as String,
      userId: (data['user'] as Map)['id'] as String,
      deviceId: data['device_id'] as String,
    );

    final session = AuthSession.fromJson(data);
    await _tokenStore.setActiveTenantId(session.tenant?.id);
    if (session.stores.length == 1) {
      await _tokenStore.setActiveStoreId(session.stores.first.id);
      _api.setActiveStoreId(session.stores.first.id);
    }
    return session;
  }

  Future<AuthSession> register({
    required String businessName,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
    String? adminPhone,
    String? businessPhone,
    String? storeName,
  }) async {
    try {
      final res = await _api.dio.post('/api/auth/register', data: {
        'business_name': businessName.trim(),
        'admin_name': adminName.trim(),
        'admin_email': adminEmail.trim(),
        'admin_password': adminPassword,
        if (adminPhone != null && adminPhone.isNotEmpty) 'admin_phone': adminPhone,
        if (businessPhone != null && businessPhone.isNotEmpty) 'business_phone': businessPhone,
        if (storeName != null && storeName.isNotEmpty) 'store_name': storeName,
      });
      final data = res.data as Map<String, dynamic>;
      await _tokenStore.save(
        token: data['token'] as String,
        userId: (data['user'] as Map)['id'] as String,
        deviceId: data['device_id'] as String,
      );
      final session = AuthSession.fromJson(data);
      await _tokenStore.setActiveTenantId(session.tenant?.id);
      if (session.stores.length == 1) {
        await _tokenStore.setActiveStoreId(session.stores.first.id);
        _api.setActiveStoreId(session.stores.first.id);
      }
      return session;
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? e.message ?? 'Erè rezo';
      final errors = e.response?.data['errors'] as Map?;
      final firstError = errors?.values.firstOrNull;
      throw Exception(firstError is List ? firstError.first : msg);
    }
  }

  Future<void> logout() async {
    // Mòd offline: pa gen bezwen rele sèvè (li ap tan tan pou anyen)
    if (!await _tokenStore.isOfflineMode()) {
      try {
        await _api.dio.post('/api/auth/logout');
      } on DioException {
        // ignore — eta lokal pi enpòtan
      }
    }
    await _tokenStore.clear();
    _api.setActiveStoreId(null);
  }

  Future<AuthSession?> restore() async {
    if (!await _tokenStore.hasToken()) return null;
    final activeStore = await _tokenStore.activeStoreId();
    if (activeStore != null) {
      _api.setActiveStoreId(activeStore);
    }
    // Mòd offline: pa rele sèvè, retounen sesyon lokal la.
    if (await _tokenStore.isOfflineMode()) {
      final json = await _tokenStore.offlineSessionJson();
      if (json == null) return null;
      return AuthSession.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }
    try {
      final res = await _api.dio.get('/api/auth/me');
      return AuthSession.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _tokenStore.clear();
      }
      return null;
    }
  }

  /// Kreye yon sesyon lokal san bezwen sèvè. Done yo ap sove nan SQLite
  /// epi ap sync avèk sèvè a lè yo migre kont lan pi ta.
  Future<AuthSession> loginOffline({
    required String storeName,
    required String adminName,
    required String adminEmail,
  }) async {
    final deviceId = await _tokenStore.deviceId() ?? Ulid().toCanonical();
    final tenantId = Ulid().toCanonical();
    final storeId = Ulid().toCanonical();
    final userId = Ulid().toCanonical();

    final sessionMap = {
      'user': {
        'id': userId,
        'name': adminName.trim().isEmpty ? 'Admin' : adminName.trim(),
        'email': adminEmail.trim().isEmpty ? 'offline@local' : adminEmail.trim(),
        'phone': null,
        'locale': 'ht',
        'avatar_path': null,
      },
      'tenant': {
        'id': tenantId,
        'name': storeName.trim().isEmpty ? 'Biznis Lokal' : storeName.trim(),
        'slug': 'offline',
        'plan': 'free_18m',
        'status': 'active',
        'logo_path': null,
        'expires_at': null,
        'days_remaining': 99999,
      },
      'roles': [
        {
          'name': 'admin',
          'label': 'Admin',
          'level': 2,
          'store_id': storeId,
        }
      ],
      'stores': [
        {
          'id': storeId,
          'name': storeName.trim().isEmpty ? 'Boutik Prensipal' : storeName.trim(),
          'code': 'MAIN',
          'currency': 'HTG',
        }
      ],
    };

    await _tokenStore.setOfflineSession(
      sessionJson: jsonEncode(sessionMap),
      userId: userId,
      deviceId: deviceId,
      storeId: storeId,
      tenantId: tenantId,
    );
    _api.setActiveStoreId(storeId);

    return AuthSession.fromJson(sessionMap);
  }

  Future<void> setActiveStore(String storeId) async {
    await _tokenStore.setActiveStoreId(storeId);
    _api.setActiveStoreId(storeId);
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider));
});
