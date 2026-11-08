import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/customer.dart';
import '../data/customer_repository.dart';

final _searchProvider = StateProvider<String>((_) => '');
final _debtOnlyProvider = StateProvider<bool>((_) => false);

final _customersListProvider = FutureProvider.autoDispose<List<Customer>>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  final search = ref.watch(_searchProvider);
  final debtOnly = ref.watch(_debtOnlyProvider);
  if (debtOnly) return repo.listWithDebt(storeId);
  return repo.list(storeId, search: search);
});

final _totalDebtProvider = FutureProvider.autoDispose<double>((ref) async {
  final repo = ref.watch(customerRepositoryProvider);
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return 0;
  return repo.totalOutstandingDebt(storeId);
});

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(_customersListProvider);
    final totalDebt = ref.watch(_totalDebtProvider);
    final debtOnly = ref.watch(_debtOnlyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Kliyan')),
      body: Column(
        children: [
          // Total outstanding debt banner
          totalDebt.maybeWhen(
            data: (d) => d > 0
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Total det kliyan: ${MoneyFormatter.format(d)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.red))),
                        TextButton(
                          onPressed: () => ref.read(_debtOnlyProvider.notifier).state = !debtOnly,
                          child: Text(debtOnly ? 'Tout' : 'Wè det yo'),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Chèche kliyan',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => ref.read(_searchProvider.notifier).state = v,
            ),
          ),
          Expanded(
            child: customers.when(
              data: (list) {
                if (list.isEmpty) return Center(child: Text(debtOnly ? 'Pa gen okenn kliyan ki dwe.' : 'Pa gen kliyan.'));
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = list[i];
                    final hasDebt = c.balance > 0;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: hasDebt ? Colors.red.shade100 : null,
                        child: Text(c.name.isNotEmpty ? c.name[0] : '?',
                          style: TextStyle(color: hasDebt ? Colors.red.shade900 : null)),
                      ),
                      title: Text(c.name),
                      subtitle: Text([
                        if (c.phone != null) c.phone!,
                        if (hasDebt) 'Dwe: ${MoneyFormatter.format(c.balance)}',
                      ].join(' · '), style: TextStyle(color: hasDebt ? Colors.red : null, fontWeight: hasDebt ? FontWeight.w600 : null)),
                      trailing: hasDebt
                          ? FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade100, foregroundColor: Colors.green.shade900),
                              icon: const Icon(Icons.payments_outlined, size: 18),
                              label: const Text('Peye'),
                              onPressed: () => _payDebtDialog(context, ref, c),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: () => context.push('/customers/${c.id}'),
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
        onPressed: () => context.push('/customers/new'),
      ),
    );
  }

  Future<void> _payDebtDialog(BuildContext context, WidgetRef ref, Customer c) async {
    final ctrl = TextEditingController(text: c.balance.toStringAsFixed(2));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Peman det · ${c.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dwe kounye a: ${MoneyFormatter.format(c.balance)}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Kantite resi',
                border: OutlineInputBorder(),
                suffixText: 'HTG',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Anile')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.replaceAll(',', '')) ?? 0;
              Navigator.of(ctx).pop(v);
            },
            child: const Text('Konfime'),
          ),
        ],
      ),
    );
    if (result == null || result <= 0) return;
    try {
      final session = ref.read(authControllerProvider).valueOrNull;
      final storeId = await ref.read(tokenStoreProvider).activeStoreId();
      await ref.read(customerRepositoryProvider).recordPayment(
        customerId: c.id,
        amount: result.clamp(0, c.balance).toDouble(),
        storeId: storeId,
        userId: session?.user.id,
      );
      ref.invalidate(_customersListProvider);
      ref.invalidate(_totalDebtProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Peman ${MoneyFormatter.format(result)} anrejistre.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }
}
