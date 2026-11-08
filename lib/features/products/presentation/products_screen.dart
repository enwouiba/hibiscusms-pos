import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/product.dart';
import '../data/product_repository.dart';

final _searchProvider = StateProvider<String>((_) => '');

final _productsListProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final repo = ref.watch(productRepositoryProvider);
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  final search = ref.watch(_searchProvider);
  return repo.listAll(storeId, search: search);
});

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(_productsListProvider);
    final auth = ref.watch(authControllerProvider).valueOrNull;
    // Sekretè (cashier) ka WÈ pwodwi pou vann, men li pa ka ajoute/modifye stock.
    final canManage = auth != null && auth.highestLevel(null) >= 2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pwodwi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_productsListProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Chèche pa non, SKU, oswa barcode',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => ref.read(_searchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: products.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('Pa gen pwodwi.'));
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: p.isLowStock ? Colors.red.shade100 : null,
                        child: Icon(
                          p.trackStock ? Icons.inventory_2 : Icons.label_outline,
                          color: p.isLowStock ? Colors.red : null,
                        ),
                      ),
                      title: Text(p.name),
                      subtitle: Text([
                        if (p.sku != null) 'SKU: ${p.sku}',
                        if (p.trackStock) 'Stock: ${MoneyFormatter.formatPlain(p.stock)}',
                      ].join('  •  ')),
                      trailing: Text(
                        MoneyFormatter.format(p.price),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onTap: () => context.push('/products/${p.id}'),
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
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Nouvo'),
              onPressed: () => context.push('/products/new'),
            )
          : null,
    );
  }
}
