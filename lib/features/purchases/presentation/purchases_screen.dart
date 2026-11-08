import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/purchase.dart';
import '../data/purchase_repository.dart';

final _purchasesListProvider = FutureProvider.autoDispose<List<Purchase>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  return ref.watch(purchaseRepositoryProvider).listRecent(storeId);
});

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(_purchasesListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acha'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_purchasesListProvider),
          ),
        ],
      ),
      body: purchases.when(
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('Pa gen acha.'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = list[i];
              return ListTile(
                leading: CircleAvatar(child: Text('#${p.purchaseNumber}')),
                title: Text(MoneyFormatter.format(p.total)),
                subtitle: Text([
                  DateFormatter.short(p.createdAt),
                  if (p.supplierName != null) p.supplierName!,
                ].join('  •  ')),
                trailing: Chip(label: Text(p.status.label), visualDensity: VisualDensity.compact),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('Nouvo Acha'),
        onPressed: () => context.push('/purchases/new'),
      ),
    );
  }
}
