import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../data/hotel_repository.dart';

final _statsProvider = FutureProvider.autoDispose<Map<String, num>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return {};
  return ref.watch(hotelRepositoryProvider).stats(storeId);
});

class HotelReportsScreen extends ConsumerWidget {
  const HotelReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(_statsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapò Otèl'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_statsProvider)),
        ],
      ),
      body: stats.when(
        data: (s) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _tile('🏨 Total chanm', '${s['total_rooms'] ?? 0}', Colors.indigo),
            _tile('🟢 Chanm lib', '${s['available'] ?? 0}', Colors.green),
            _tile('🔴 Chanm okipe', '${s['occupied'] ?? 0}', Colors.red),
            const Divider(height: 28),
            _tile('👥 Sejou aktif', '${s['active_stays'] ?? 0}', Colors.teal),
            _tile('📅 Sejou jodi a', '${s['today_count'] ?? 0}', Colors.blue),
            _tile('💰 Lajan jodi a', MoneyFormatter.format((s['today_revenue'] ?? 0).toDouble()), Colors.green),
            _tile('⚠️ Dèt pa peye', MoneyFormatter.format((s['uncollected'] ?? 0).toDouble()), Colors.orange),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
    );
  }

  Widget _tile(String label, String value, Color color) => Card(
        child: ListTile(
          title: Text(label),
          trailing: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ),
      );
}
