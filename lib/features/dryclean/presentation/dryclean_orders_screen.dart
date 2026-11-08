import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/dryclean_order.dart';
import '../data/dryclean_repository.dart';

final _filterProvider = StateProvider<DrycleanStatus?>((_) => null);

final _ordersProvider = FutureProvider.autoDispose<List<DrycleanOrder>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  final status = ref.watch(_filterProvider);
  return ref.watch(drycleanRepositoryProvider).list(storeId, status: status);
});

class DrycleanOrdersScreen extends ConsumerWidget {
  const DrycleanOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(_ordersProvider);
    final filter = ref.watch(_filterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lòd Dry Cleaning'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_ordersProvider)),
        ],
      ),
      body: Column(
        children: [
          // Filtè estati
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _chip(ref, 'Tout', null, filter),
                for (final s in DrycleanStatus.values) _chip(ref, '${s.emoji} ${s.label}', s, filter),
              ],
            ),
          ),
          Expanded(
            child: orders.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('Pa gen lòd pou kounye a.'));
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final o = list[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text('${o.orderNumber}')),
                      title: Text(o.customerName?.isNotEmpty == true ? o.customerName! : 'Lòd #${o.orderNumber}'),
                      subtitle: Text([
                        '${o.status.emoji} ${o.status.label}',
                        if (o.readyDate != null) 'Pare: ${_d(o.readyDate!)}',
                        if (o.amountDue > 0) 'Dèt: ${MoneyFormatter.format(o.amountDue)}',
                      ].join('  •  ')),
                      trailing: Text(MoneyFormatter.format(o.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () => context.push('/dryclean/${o.id}'),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erè: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nouvo Lòd'),
        onPressed: () => context.push('/dryclean/new'),
      ),
    );
  }

  Widget _chip(WidgetRef ref, String label, DrycleanStatus? value, DrycleanStatus? current) {
    final sel = value == current;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => ref.read(_filterProvider.notifier).state = value,
      ),
    );
  }

  static String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
