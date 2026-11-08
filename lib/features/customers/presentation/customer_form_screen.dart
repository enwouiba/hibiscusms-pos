import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/customer.dart';
import '../data/customer_repository.dart';

final _customerProvider = FutureProvider.family.autoDispose<Customer?, String>((ref, id) async {
  return ref.watch(customerRepositoryProvider).findById(id);
});

class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, this.customerId});
  final String? customerId;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Customer? _existing;
  bool _saving = false;

  void _populate(Customer c) {
    if (_existing != null) return;
    _existing = c;
    _nameCtrl.text = c.name;
    _phoneCtrl.text = c.phone ?? '';
    _emailCtrl.text = c.email ?? '';
    _addressCtrl.text = c.address ?? '';
    _notesCtrl.text = c.notes ?? '';
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _emailCtrl, _addressCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    if (storeId == null) return;
    final repo = ref.read(customerRepositoryProvider);
    setState(() => _saving = true);
    try {
      if (_existing == null) {
        await repo.create(
          storeId: storeId,
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      } else {
        await repo.update(_existing!.copyWith(
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        ));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kliyan sove.')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addDebt() async {
    if (_existing == null) return;
    final customerId = _existing!.id;
    final customerName = _existing!.name;

    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16, right: 16, top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
            Text('➕ Ajoute Dèt — $customerName',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Kliyan an dwe kob adisyonèl',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
            const SizedBox(height: 20),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Mòn dèt pou ajoute *',
                suffixText: 'HTG',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final v in [100, 200, 500, 1000, 2000])
                ActionChip(label: Text(MoneyFormatter.format(v.toDouble())),
                  onPressed: () => amountCtrl.text = v.toStringAsFixed(2)),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Rezon (obligatwa) *',
                hintText: 'Egzanp: Achte manje, prete kob, elatriye',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLength: 200,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Nòt (opsyonèl)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Anile')),
              )),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: FilledButton.icon(
                icon: const Icon(Icons.add_circle),
                style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
                onPressed: () {
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                  final rez = reasonCtrl.text.trim();
                  if (amt <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Antre yon mòn valab')));
                    return;
                  }
                  if (rez.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Antre yon rezon')));
                    return;
                  }
                  Navigator.pop(ctx, {
                    'amount': amt,
                    'reason': rez,
                    'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  });
                },
                label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Ajoute Dèt')),
              )),
            ]),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    amountCtrl.dispose();
    reasonCtrl.dispose();
    notesCtrl.dispose();
    if (result == null) return;

    try {
      final storeId = await ref.read(tokenStoreProvider).activeStoreId();
      final user = ref.read(authControllerProvider).valueOrNull?.user;
      await ref.read(customerRepositoryProvider).recordDebtAddition(
        customerId: customerId,
        amount: result['amount'] as double,
        reason: result['reason'] as String,
        storeId: storeId,
        userId: user?.id,
        notes: result['notes'] as String?,
      );
      // Rafrechi kliyan
      ref.invalidate(_customerProvider(customerId));
      _existing = null;
      // ignore: unawaited_futures
      ref.read(syncServiceProvider).runOnce();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Dèt ${MoneyFormatter.format(result['amount'] as double)} ajoute'),
          backgroundColor: Colors.orange.shade700,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  Future<void> _recordDebtPayment() async {
    if (_existing == null) return;
    final balance = _existing!.balance;
    if (balance <= 0) return;

    final amountCtrl = TextEditingController(text: balance.toStringAsFixed(2));
    final notesCtrl = TextEditingController();
    String method = 'cash';

    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16, right: 16, top: 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSt) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
              Text('💰 Peye Dèt — ${_existing!.name}',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Dèt aktyèl: ${MoneyFormatter.format(balance)}',
                style: TextStyle(color: Colors.red.shade700, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 20),
              TextField(
                controller: amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mòn kob peye *',
                  suffixText: 'HTG',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                autofocus: true,
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                ActionChip(
                  label: Text('Total (${MoneyFormatter.format(balance)})'),
                  onPressed: () => amountCtrl.text = balance.toStringAsFixed(2),
                ),
                ActionChip(label: const Text('½'), onPressed: () => amountCtrl.text = (balance / 2).toStringAsFixed(2)),
                ActionChip(label: const Text('¼'), onPressed: () => amountCtrl.text = (balance / 4).toStringAsFixed(2)),
              ]),
              const SizedBox(height: 16),
              const Text('Metòd peman', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final m in const [
                  ('cash', '💵 Kach'),
                  ('moncash', '📱 MonCash'),
                  ('natcashpay', '📱 NatCash'),
                  ('card', '💳 Kat'),
                ])
                  ChoiceChip(
                    label: Text(m.$2),
                    selected: method == m.$1,
                    onSelected: (_) => setSt(() => method = m.$1),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Nòt (opsyonèl)', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Anile')),
                )),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: FilledButton.icon(
                  icon: const Icon(Icons.check_circle),
                  onPressed: () {
                    final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                    if (amt <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Antre yon mòn valab')));
                      return;
                    }
                    if (amt > balance) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Mòn depase dèt (${MoneyFormatter.format(balance)})')));
                      return;
                    }
                    Navigator.pop(ctx, {
                      'amount': amt,
                      'method': method,
                      'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                    });
                  },
                  label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Konfime Peman')),
                )),
              ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    amountCtrl.dispose();
    notesCtrl.dispose();
    if (result == null) return;

    try {
      final storeId = await ref.read(tokenStoreProvider).activeStoreId();
      final user = ref.read(authControllerProvider).valueOrNull?.user;
      await ref.read(customerRepositoryProvider).recordPayment(
        customerId: _existing!.id,
        amount: result['amount'] as double,
        storeId: storeId,
        userId: user?.id,
        method: result['method'] as String,
        notes: result['notes'] as String?,
      );
      // Rafrechi kliyan
      ref.invalidate(_customerProvider(_existing!.id));
      _existing = null;
      // Deklanche sync imedyatman (fire-and-forget)
      // ignore: unawaited_futures
      ref.read(syncServiceProvider).runOnce();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Peman ${MoneyFormatter.format(result['amount'] as double)} anrejistre'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  Future<void> _delete() async {
    if (_existing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Efase kliyan sa?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anile')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Efase'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(customerRepositoryProvider).delete(_existing!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.customerId == null;
    if (!isNew) {
      final c = ref.watch(_customerProvider(widget.customerId!));
      c.whenData((v) {
        if (v != null) _populate(v);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nouvo Kliyan' : 'Modifye Kliyan'),
        actions: [
          if (!isNew) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // KAT DÈT + BOUTON PEYE
            if (!isNew && _existing != null && _existing!.balance > 0) ...[
              Card(
                elevation: 2,
                color: Colors.red.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.red.shade300, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Icon(Icons.account_balance_wallet, color: Colors.red.shade700, size: 28),
                        const SizedBox(width: 8),
                        Text('Dèt Aktyèl', style: TextStyle(
                          color: Colors.red.shade700, fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        MoneyFormatter.format(_existing!.balance),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.paid, size: 20),
                          label: const Text('💰 Peye', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          onPressed: _recordDebtPayment,
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.orange.shade700, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: Icon(Icons.add_circle_outline, size: 20, color: Colors.orange.shade700),
                          label: Text('➕ Ajoute',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                          onPressed: _addDebt,
                        )),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (!isNew && _existing != null && _existing!.balance <= 0) ...[
              Card(
                color: Colors.green.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.green.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Row(children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        'Kliyan pa gen dèt',
                        style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600, fontSize: 15),
                      )),
                    ]),
                    const SizedBox(height: 12),
                    // Bouton "Ajoute Dèt" toujou disponib menm si pa gen dèt
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.orange.shade700, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: Icon(Icons.add_circle_outline, size: 20, color: Colors.orange.shade700),
                        label: Text('➕ Ajoute Dèt Manyèl',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                        onPressed: _addDebt,
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
            ],
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Non *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatwa' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Telefòn', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: 'Imel', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Adrès', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Nòt', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                icon: const Icon(Icons.save),
                label: Text(_saving ? 'Ap sove…' : 'Sove'),
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
