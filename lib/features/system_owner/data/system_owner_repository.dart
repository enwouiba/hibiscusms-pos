import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class TenantSummary {
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
  final int storesCount;
  final int usersCount;
  final DateTime createdAt;

  const TenantSummary({
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
    required this.storesCount,
    required this.usersCount,
    required this.createdAt,
  });

  factory TenantSummary.fromJson(Map<String, dynamic> j) => TenantSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        slug: j['slug'] as String,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        plan: j['plan'] as String,
        status: j['status'] as String,
        expiresAt: j['expires_at'] != null ? DateTime.tryParse(j['expires_at'] as String) : null,
        daysRemaining: (j['days_remaining'] as num).toInt(),
        isExpired: (j['is_expired'] as bool?) ?? false,
        storesCount: int.tryParse(j['stores_count'].toString()) ?? 0,
        usersCount: int.tryParse(j['users_count'].toString()) ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class RenewalReq {
  final String id;
  final String tenantId;
  final String plan;
  final double amount;
  final String currency;
  final String? paymentMethod;
  final String? paymentReference;
  final String status;
  final DateTime createdAt;
  final Map<String, dynamic>? tenant;

  const RenewalReq({
    required this.id,
    required this.tenantId,
    required this.plan,
    required this.amount,
    required this.currency,
    this.paymentMethod,
    this.paymentReference,
    required this.status,
    required this.createdAt,
    this.tenant,
  });

  factory RenewalReq.fromJson(Map<String, dynamic> j) => RenewalReq(
        id: j['id'] as String,
        tenantId: j['tenant_id'] as String,
        plan: j['plan'] as String,
        amount: (j['amount'] as num).toDouble(),
        currency: (j['currency'] as String?) ?? 'HTG',
        paymentMethod: j['payment_method'] as String?,
        paymentReference: j['payment_reference'] as String?,
        status: j['status'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        tenant: j['tenant'] as Map<String, dynamic>?,
      );
}

class SystemOwnerRepository {
  SystemOwnerRepository(this._api);
  final ApiClient _api;

  Future<List<TenantSummary>> listTenants() async {
    final res = await _api.dio.get('/api/system/tenants');
    final data = (res.data['data'] as List).cast<Map<String, dynamic>>();
    return data.map(TenantSummary.fromJson).toList();
  }

  Future<Map<String, dynamic>> tenantDetail(String id) async {
    final res = await _api.dio.get('/api/system/tenants/$id');
    return res.data as Map<String, dynamic>;
  }

  Future<void> extendTenant(String tenantId, {required int months, String? plan, String? notes}) async {
    await _api.dio.post('/api/system/tenants/$tenantId/extend', data: {
      'months': months,
      if (plan != null) 'plan': plan,
      if (notes != null) 'notes': notes,
    });
  }

  Future<void> grantPlan(String tenantId, {required String planCode, String? notes}) async {
    await _api.dio.post('/api/system/tenants/$tenantId/grant-plan', data: {
      'plan': planCode,
      if (notes != null) 'notes': notes,
    });
  }

  Future<List<Map<String, dynamic>>> listPlans() async {
    final res = await _api.dio.get('/api/system/plans');
    return (res.data['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> setStatus(String tenantId, String status, {String? reason}) async {
    await _api.dio.post('/api/system/tenants/$tenantId/status', data: {
      'status': status,
      if (reason != null) 'reason': reason,
    });
  }

  Future<List<RenewalReq>> listRenewals() async {
    final res = await _api.dio.get('/api/system/renewals');
    final data = (res.data['data'] as List).cast<Map<String, dynamic>>();
    return data.map(RenewalReq.fromJson).toList();
  }

  Future<void> approveRenewal(String id) async {
    await _api.dio.post('/api/system/renewals/$id/approve');
  }

  Future<void> rejectRenewal(String id, {String? reason}) async {
    await _api.dio.post('/api/system/renewals/$id/reject', data: {
      if (reason != null) 'reason': reason,
    });
  }
}

final systemOwnerRepositoryProvider = Provider<SystemOwnerRepository>((ref) {
  return SystemOwnerRepository(ref.watch(apiClientProvider));
});
