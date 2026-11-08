import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/cash_session.dart';
import '../data/cash_session_repository.dart';

final _currentSessionProvider = FutureProvider.autoDispose<CashSession?>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  final session = ref.watch(authControllerProvider).valueOrNull;
  if (storeId == null || session == null) return null;
  return ref.watch(cashSessionRepositoryProvider).current(storeId, session.user.id);
});

final _recentSessionsProvider = FutureProvider.autoDispose<List<CashSession>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  return ref.watch(cashSessionRepositoryProvider).recent(storeId);
});

class CashSessionScreen extends ConsumerWidget {
  const CashSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(_currentSessionProvider);
    final recent = ref.watch(_recentSessionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesyon Kès'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(_currentSessionProvider);
              ref.invalidate(_recentSessionsProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          current.when(
            data: (s) {
              if (s == null) {
                return Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Pa gen sesyon ouvri',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Ouvri yon sesyon anvan ou kòmanse vann pou swiv kès la.'),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Ouvri Sesyon'),
                          onPressed: () => _openDialog(context, ref),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock_open, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Sesyon Aktif',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _Row('Ouvèti', DateFormatter.full(s.openedAt)),
                      _Row('Balans ouv.', MoneyFormatter.format(s.openingBalance)),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          icon: const Icon(Icons.lock),
                          label: const Text('Fèmen Sesyon'),
                          onPressed: () => _closeDialog(context, ref, s),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Card(child: ListTile(title: Text('Ap chaje…'))),
            error: (e, _) => Card(child: ListTile(title: Text('Erè: $e'))),
          ),
          const SizedBox(height: 24),
          const Text('Sesyon Resan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          recent.when(
            data: (list) {
              final closed = list.where((s) => !s.isOpen).toList();
              if (closed.isEmpty) {
                return const Card(child: ListTile(title: Text('Pa gen sesyon fèmen.')));
              }
              return Column(
                children: closed.map((s) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(DateFormatter.short(s.openedAt)),
                        subtitle: Text(
                            'Vant: ${MoneyFormatter.format(s.totalSales)} • Kach: ${MoneyFormatter.format(s.totalCash)}'),
                        trailing: Text(
                          s.difference != null && s.difference!.abs() > 0.01
                              ? '${s.difference! >= 0 ? "+" : ""}${MoneyFormatter.formatPlain(s.difference!)}'
                              : 'OK',
                          style: TextStyle(
                            color: s.difference == null || s.difference!.abs() <= 0.01
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Erè: $e'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ouvri Sesyon'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Balans ouvèti', border: OutlineInputBorder(), suffixText: 'HTG'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anile')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ouvri')),
        ],
      ),
    );
    if (ok != true) return;
    final balance = double.tryParse(ctrl.text) ?? 0;
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    final session = ref.read(authControllerProvider).valueOrNull;
    if (storeId == null || session == null) return;
    await ref.read(cashSessionRepositoryProvider).open(
          storeId: storeId,
          userId: session.user.id,
          openingBalance: balance,
        );
    ref.invalidate(_currentSessionProvider);
    ref.invalidate(_recentSessionsProvider);
  }

  Future<void> _closeDialog(BuildContext context, WidgetRef ref, CashSession s) async {
    final ctrl = TextEditingController(text: s.openingBalance.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fèmen Sesyon'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Balans final', border: OutlineInputBorder(), suffixText: 'HTG'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anile')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fèmen')),
        ],
      ),
    );
    if (ok != true) return;
    final balance = double.tryParse(ctrl.text) ?? 0;
    await ref.read(cashSessionRepositoryProvider).close(id: s.id, closingBalance: balance);
    ref.invalidate(_currentSessionProvider);
    ref.invalidate(_recentSessionsProvider);
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
