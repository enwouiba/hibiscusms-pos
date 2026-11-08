import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/token_store.dart';
import '../../../shared/models/supplier.dart';
import '../data/supplier_repository.dart';

final _searchProvider = StateProvider<String>((_) => '');

final _suppliersListProvider = FutureProvider.autoDispose<List<Supplier>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  return ref.watch(supplierRepositoryProvider).list(storeId, search: ref.watch(_searchProvider));
});

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(_suppliersListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Founisè')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Chèche founisè',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => ref.read(_searchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: suppliers.when(
              data: (list) {
                if (list.isEmpty) return const Center(child: Text('Pa gen founisè.'));
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = list[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
                      title: Text(s.name),
                      subtitle: Text([
                        if (s.contactName != null) s.contactName!,
                        if (s.phone != null) s.phone!,
                      ].join('  •  ')),
                      onTap: () => context.push('/suppliers/${s.id}'),
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
        label: const Text('Nouvo'),
        onPressed: () => context.push('/suppliers/new'),
      ),
    );
  }
}
