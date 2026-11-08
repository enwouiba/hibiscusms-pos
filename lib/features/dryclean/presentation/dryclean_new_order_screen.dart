import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/money_formatter.dart';
import '../../products/data/product_repository.dart';
import '../data/dryclean_repository.dart';

class DrycleanNewOrderScreen extends ConsumerStatefulWidget {
  const DrycleanNewOrderScreen({super.key});

  @override
  ConsumerState<DrycleanNewOrderScreen> createState() => _DrycleanNewOrderScreenState();
}

class _DrycleanNewOrderScreenState extends ConsumerState<DrycleanNewOrderScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final List<DrycleanLineInput> _lines = [];
  DateTime _readyDate = DateTime.now().add(const Duration(days: 1));
  bool _express = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _depositCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _subtotal => _lines.fold(0, (s, l) => s + l.lineTotal);

  Future<void> _addLine() async {
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    final products = storeId == null
        ? <dynamic>[]
        : await ref.read(productRepositoryProvider).listAll(storeId);
    if (!mounted) return;

    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    final condCtrl = TextEditingController();

    final result = await showModalBottomSheet<DrycleanLineInput?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ajoute yon rad / sèvis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (products.isNotEmpty)
              DropdownButtonFormField<dynamic>(
                decoration: const InputDecoration(labelText: 'Chwazi sèvis (opsyonèl)', border: OutlineInputBorder()),
                items: [
                  for (final p in products)
                    DropdownMenuItem(value: p, child: Text('${p.name} — ${MoneyFormatter.format(p.price)}')),
                ],
                onChanged: (p) {
                  if (p != null) {
                    nameCtrl.text = p.name as String;
                    priceCtrl.text = (p.price as num).toStringAsFixed(2);
                  }
                },
              ),
            const SizedBox(height: 10),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Non rad/sèvis *', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(labelText: 'Kantite', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: priceCtrl,
                decoration: const InputDecoration(labelText: 'Pri (chak)', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              )),
            ]),
            const SizedBox(height: 10),
            TextField(controller: tagCtrl, decoration: const InputDecoration(labelText: 'Nimewo etikèt (opsyonèl)', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: condCtrl, decoration: const InputDecoration(labelText: 'Nòt eta (tach, twou...)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final qty = double.tryParse(qtyCtrl.text.trim()) ?? 1;
                final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
                if (name.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Antre yon non')));
                  return;
                }
                Navigator.pop(ctx, DrycleanLineInput(
                  name: name, quantity: qty <= 0 ? 1 : qty, unitPrice: price,
                  tagNumber: tagCtrl.text.trim().isEmpty ? null : tagCtrl.text.trim(),
                  conditionNotes: condCtrl.text.trim().isEmpty ? null : condCtrl.text.trim(),
                ));
              },
              child: const Padding(padding: EdgeInsets.all(12), child: Text('Ajoute')),
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    for (final c in [nameCtrl, qtyCtrl, priceCtrl, tagCtrl, condCtrl]) {
      c.dispose();
    }
    if (result != null) setState(() => _lines.add(result));
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajoute omwen yon rad/sèvis')));
      return;
    }
    setState(() => _saving = true);
    try {
      final storeId = await ref.read(tokenStoreProvider).activeStoreId();
      final auth = ref.read(authControllerProvider).valueOrNull;
      if (storeId == null) throw Exception('Chwazi yon magazen');
      final order = await ref.read(drycleanRepositoryProvider).create(
            storeId: storeId,
            userId: auth?.user.id,
            cashierName: auth?.user.name,
            customerName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
            customerPhone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
            readyDate: _readyDate,
            lines: _lines,
            deposit: double.tryParse(_depositCtrl.text.trim()) ?? 0,
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          );
      // ignore: unawaited_futures
      ref.read(syncServiceProvider).runOnce();
      if (!mounted) return;
      context.pushReplacement('/dryclean/${order.id}');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvo Lòd')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Non kliyan', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
          const SizedBox(height: 12),
          TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Telefòn', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
          const SizedBox(height: 8),
          // Ekspres — pare menm jou a
          SwitchListTile(
            value: _express,
            onChanged: (v) => setState(() {
              _express = v;
              if (v) _readyDate = DateTime.now();
            }),
            secondary: const Icon(Icons.bolt, color: Colors.orange),
            title: const Text('⚡ Ekspres (pare menm jou a)'),
          ),
          const SizedBox(height: 8),
          // Dat pare
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade400)),
            leading: const Icon(Icons.event),
            title: const Text('Dat pare'),
            subtitle: Text('${_readyDate.day.toString().padLeft(2, '0')}/${_readyDate.month.toString().padLeft(2, '0')}/${_readyDate.year}'),
            trailing: const Icon(Icons.edit),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _readyDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d != null) setState(() => _readyDate = d);
            },
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Text('Rad / Sèvis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            TextButton.icon(onPressed: _addLine, icon: const Icon(Icons.add), label: const Text('Ajoute')),
          ]),
          if (_lines.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('Poko gen rad. Klike « Ajoute ».')))
          else
            ..._lines.asMap().entries.map((e) {
              final l = e.value;
              return Card(
                child: ListTile(
                  title: Text('${l.quantity.toStringAsFixed(l.quantity == l.quantity.roundToDouble() ? 0 : 2)} × ${l.name}'),
                  subtitle: Text([
                    if (l.tagNumber != null) 'Etikèt: ${l.tagNumber}',
                    if (l.conditionNotes != null) l.conditionNotes!,
                  ].join(' • ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(MoneyFormatter.format(l.lineTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _lines.removeAt(e.key))),
                  ]),
                ),
              );
            }),
          const SizedBox(height: 12),
          TextField(
            controller: _depositCtrl,
            decoration: const InputDecoration(labelText: 'Depo / Peman kounye a', border: OutlineInputBorder(), prefixIcon: Icon(Icons.payments)),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          ),
          const SizedBox(height: 12),
          TextField(controller: _notesCtrl, decoration: const InputDecoration(labelText: 'Nòt (opsyonèl)', border: OutlineInputBorder()), maxLines: 2),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text(MoneyFormatter.format(_subtotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              icon: const Icon(Icons.save),
              label: Text(_saving ? 'Ap sove…' : 'Kreye Lòd'),
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
