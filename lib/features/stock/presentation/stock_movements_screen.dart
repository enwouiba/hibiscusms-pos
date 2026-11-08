import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../shared/models/stock_movement.dart';
import '../data/stock_movement_repository.dart';

final _movementsProvider = FutureProvider.autoDispose<List<StockMovement>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  return ref.watch(stockMovementRepositoryProvider).list(storeId);
});

class StockMovementsScreen extends ConsumerWidget {
  const StockMovementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(_movementsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mouvman Stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_movementsProvider),
          ),
        ],
      ),
      body: movements.when(
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('Pa gen mouvman.'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = list[i];
              final color = m.quantity > 0 ? Colors.green : Colors.red;
              final icon = switch (m.type) {
                StockMovementType.sale => Icons.point_of_sale,
                StockMovementType.purchase => Icons.shopping_cart,
                StockMovementType.adjust => Icons.tune,
                StockMovementType.transferIn => Icons.call_received,
                StockMovementType.transferOut => Icons.call_made,
                StockMovementType.returnIn => Icons.undo,
                StockMovementType.damage => Icons.broken_image,
              };
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, color: color),
                ),
                title: Text(m.productName ?? '—'),
                subtitle: Text([
                  m.type.label,
                  DateFormatter.short(m.createdAt),
                  if (m.userName != null) m.userName!,
                ].join('  •  ')),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${m.quantity > 0 ? "+" : ""}${m.quantity.toStringAsFixed(0)}',
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text('Bal: ${m.balanceAfter.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
    );
  }
}
