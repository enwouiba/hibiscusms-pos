import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/sale.dart';
import '../data/sale_repository.dart';

final _salesListProvider = FutureProvider.autoDispose<List<Sale>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  return ref.watch(saleRepositoryProvider).listRecent(storeId, limit: 100);
});

class SalesHistoryScreen extends ConsumerWidget {
  const SalesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(_salesListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Istwa Vant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_salesListProvider),
          ),
        ],
      ),
      body: sales.when(
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('Pa gen vant.'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = list[i];
              return ListTile(
                leading: CircleAvatar(child: Text('#${s.saleNumber}')),
                title: Text(MoneyFormatter.format(s.total)),
                subtitle: Text([
                  DateFormatter.short(s.createdAt),
                  if (s.customerName != null) s.customerName!,
                ].join('  •  ')),
                trailing: Chip(
                  label: Text(s.status.label),
                  visualDensity: VisualDensity.compact,
                ),
                onTap: () => context.push('/sales/${s.id}'),
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
