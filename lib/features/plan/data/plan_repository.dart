import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class PlanPricing {
  final String code;
  final String label;
  final int? durationMonths; // null = lifetime
  final double price;
  final String currency;
  final int? maxStores;
  final int? maxUsers;
  final int? maxProducts;
  final List<String> features;

  const PlanPricing({
    required this.code,
    required this.label,
    this.durationMonths,
    required this.price,
    required this.currency,
    this.maxStores,
    this.maxUsers,
    this.maxProducts,
    required this.features,
  });

  bool get isLifetime => durationMonths == null || code == 'lifetime';

  factory PlanPricing.fromJson(Map<String, dynamic> j) {
    int? _i(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }
    double _d(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }
    return PlanPricing(
      code: (j['code'] ?? '').toString(),
      label: (j['label'] ?? j['code'] ?? '').toString(),
      durationMonths: _i(j['duration_months']),
      price: _d(j['price']),
      currency: (j['currency'] as String?) ?? 'HTG',
      maxStores: _i(j['max_stores']),
      maxUsers: _i(j['max_users']),
      maxProducts: _i(j['max_products']),
      features: ((j['features'] as List?) ?? const []).map((e) => e.toString()).toList(),
    );
  }
}

class PlanRepository {
  PlanRepository(this._api);
  final ApiClient _api;

  Future<List<PlanPricing>> listPlans() async {
    final res = await _api.dio.get('/api/tenant/plans');
    final data = (res.data['data'] as List).cast<Map<String, dynamic>>();
    return data.map(PlanPricing.fromJson).toList();
  }

  Future<void> requestRenewal({
    required String planCode,
    required String paymentMethod,
    String? paymentReference,
    String? notes,
  }) async {
    try {
      await _api.dio.post('/api/tenant/renewal', data: {
        'plan': planCode,
        'payment_method': paymentMethod,
        if (paymentReference != null) 'payment_reference': paymentReference,
        if (notes != null) 'notes': notes,
      });
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? e.message ?? 'Erè rezo');
    }
  }
}

final planRepositoryProvider = Provider<PlanRepository>((ref) {
  return PlanRepository(ref.watch(apiClientProvider));
});
