import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stoke token Sanctum nan Android Keystore (sekirite materyèl).
class TokenStore {
  TokenStore(this._storage);
  final FlutterSecureStorage _storage;

  static const _tokenKey = 'sanctum_token';
  static const _userIdKey = 'user_id';
  static const _deviceIdKey = 'device_id';
  static const _activeStoreIdKey = 'active_store_id';
  static const _activeTenantIdKey = 'active_tenant_id';
  static const _offlineFlagKey = 'offline_mode';
  static const _offlineSessionKey = 'offline_session_json';

  Future<void> save({required String token, required String userId, required String deviceId}) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _deviceIdKey, value: deviceId);
  }

  Future<void> setDeviceId(String deviceId) async {
    await _storage.write(key: _deviceIdKey, value: deviceId);
  }

  Future<String?> read() => _storage.read(key: _tokenKey);
  Future<String?> userId() => _storage.read(key: _userIdKey);
  Future<String?> deviceId() => _storage.read(key: _deviceIdKey);
  Future<String?> activeStoreId() => _storage.read(key: _activeStoreIdKey);

  /// Tenant (biznis) ki konekte kounye a. Nou sèvi ak li pou limite
  /// katalòg pwodwi a — konsa done yon lòt magazen ki ta rete nan baz
  /// lokal la pa parèt melanje ak sa k pou magazen aktyèl la.
  Future<String?> activeTenantId() => _storage.read(key: _activeTenantIdKey);

  Future<void> setActiveStoreId(String? id) async {
    if (id == null) {
      await _storage.delete(key: _activeStoreIdKey);
    } else {
      await _storage.write(key: _activeStoreIdKey, value: id);
    }
  }

  Future<void> setActiveTenantId(String? id) async {
    if (id == null) {
      await _storage.delete(key: _activeTenantIdKey);
    } else {
      await _storage.write(key: _activeTenantIdKey, value: id);
    }
  }

  Future<bool> hasToken() async => (await read())?.isNotEmpty ?? false;

  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _activeStoreIdKey);
    await _storage.delete(key: _activeTenantIdKey);
    await _storage.delete(key: _offlineFlagKey);
    await _storage.delete(key: _offlineSessionKey);
  }

  Future<bool> isOfflineMode() async =>
      (await _storage.read(key: _offlineFlagKey)) == 'true';

  Future<void> setOfflineSession({
    required String sessionJson,
    required String userId,
    required String deviceId,
    required String storeId,
    String? tenantId,
  }) async {
    await _storage.write(key: _offlineFlagKey, value: 'true');
    await _storage.write(key: _offlineSessionKey, value: sessionJson);
    await _storage.write(key: _tokenKey, value: 'OFFLINE_TOKEN');
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _deviceIdKey, value: deviceId);
    await _storage.write(key: _activeStoreIdKey, value: storeId);
    if (tenantId != null) {
      await _storage.write(key: _activeTenantIdKey, value: tenantId);
    }
  }

  Future<String?> offlineSessionJson() =>
      _storage.read(key: _offlineSessionKey);
}

final tokenStoreProvider = Provider<TokenStore>((ref) {
  return TokenStore(const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ));
});
