import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../data/dryclean_repository.dart';

final _statsProvider = FutureProvider.autoDispose<Map<String, num>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return {};
  return ref.watch(drycleanRepositoryProvider).stats(storeId);
});

class DrycleanReportsScreen extends ConsumerWidget {
  const DrycleanReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_statsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapò Dry Cleaning'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_statsProvider))],
      ),
      body: async.when(
        data: (s) {
          if (s.isEmpty) return const Center(child: Text('Pa gen done.'));
          final cards = [
            _Stat('Lòd jodi a', '${s['today_count']}', Icons.today, Colors.blue),
            _Stat('Lajan jodi a', MoneyFormatter.format((s['today_revenue'] ?? 0).toDouble()), Icons.payments, Colors.green),
            _Stat('An atant', '${s['pending']}', Icons.hourglass_bottom, Colors.orange, sub: 'Resevwa + Ap travay'),
            _Stat('Pare (ap tann)', '${s['ready']}', Icons.check_circle, Colors.teal, sub: 'Pou ranmase'),
            _Stat('Total lòd', '${s['total_orders']}', Icons.list_alt, Colors.indigo),
            _Stat('Dèt pou ranmase', MoneyFormatter.format((s['uncollected'] ?? 0).toDouble()), Icons.account_balance_wallet, Colors.red, sub: 'Lòd ki poko ranmase'),
          ];
          return GridView.count(
            padding: const EdgeInsets.all(12),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
            children: cards.map((c) => _card(c)).toList(),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
    );
  }

  Widget _card(_Stat c) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(c.icon, color: c.color, size: 28),
              const SizedBox(height: 8),
              Text(c.value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c.color)),
              const SizedBox(height: 2),
              Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (c.sub != null) Text(c.sub!, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      );
}

class _Stat {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;
  _Stat(this.label, this.value, this.icon, this.color, {this.sub});
}
