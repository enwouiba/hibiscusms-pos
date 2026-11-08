import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class TenantProfile {
  final String id;
  final String name;
  final String slug;
  final String? email;
  final String? phone;
  final String plan;
  final String status;
  final DateTime? expiresAt;
  final int daysRemaining;
  final bool isExpired;
  final String? logoPath;
  final String? logoUrl;

  TenantProfile({
    required this.id,
    required this.name,
    required this.slug,
    this.email,
    this.phone,
    required this.plan,
    required this.status,
    this.expiresAt,
    required this.daysRemaining,
    required this.isExpired,
    this.logoPath,
    this.logoUrl,
  });

  factory TenantProfile.fromJson(Map<String, dynamic> j, {String? baseUrl}) {
    int _i(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }
    final logoPath = j['logo_path']?.toString();
    String? logoUrl;
    if (logoPath != null && logoPath.isNotEmpty && baseUrl != null) {
      logoUrl = '$baseUrl/storage/$logoPath';
    }
    return TenantProfile(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      slug: (j['slug'] ?? '').toString(),
      email: j['email']?.toString(),
      phone: j['phone']?.toString(),
      plan: (j['plan'] ?? '').toString(),
      status: (j['status'] ?? '').toString(),
      expiresAt: j['expires_at'] != null ? DateTime.tryParse(j['expires_at'].toString()) : null,
      daysRemaining: _i(j['days_remaining']),
      isExpired: j['is_expired'] == true,
      logoPath: logoPath,
      logoUrl: logoUrl,
    );
  }
}

class TenantRepository {
  TenantRepository(this._api);
  final ApiClient _api;

  Future<TenantProfile> current() async {
    final res = await _api.dio.get('/api/tenant');
    return TenantProfile.fromJson(
      res.data['data'] as Map<String, dynamic>,
      baseUrl: _api.dio.options.baseUrl,
    );
  }

  Future<TenantProfile> update({
    String? name,
    String? email,
    String? phone,
  }) async {
    final res = await _api.dio.patch('/api/tenant', data: {
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
    });
    return TenantProfile.fromJson(
      (res.data['data'] as Map<String, dynamic>),
      baseUrl: _api.dio.options.baseUrl,
    );
  }

  Future<String> uploadLogo(File file) async {
    final form = FormData.fromMap({
      'logo': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
    });
    final res = await _api.dio.post('/api/tenant/logo', data: form);
    return (res.data['url'] ?? '').toString();
  }
}

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  return TenantRepository(ref.watch(apiClientProvider));
});

final currentTenantProvider = FutureProvider.autoDispose<TenantProfile>((ref) async {
  return ref.watch(tenantRepositoryProvider).current();
});
