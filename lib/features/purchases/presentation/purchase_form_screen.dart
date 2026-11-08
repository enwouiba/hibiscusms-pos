import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/supplier.dart';
import '../../products/data/product_repository.dart';
import '../../suppliers/data/supplier_repository.dart';
import '../data/purchase_repository.dart';

class PurchaseFormScreen extends ConsumerStatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  final _invoiceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _paidCtrl = TextEditingController(text: '0');
  Supplier? _supplier;
  final List<PurchaseLineDraft> _lines = [];
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_invoiceCtrl, _notesCtrl, _paidCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total => _lines.fold(0, (s, l) => s + l.subtotal);

  Future<void> _pickSupplier() async {
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    if (storeId == null) return;
    final suppliers = await ref.read(supplierRepositoryProvider).list(storeId);
    if (!mounted) return;
    final s = await showModalBottomSheet<Supplier>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          children: suppliers
              .map((s) => ListTile(
                    title: Text(s.name),
                    subtitle: s.phone != null ? Text(s.phone!) : null,
                    onTap: () => Navigator.pop(context, s),
                  ))
              .toList(),
        ),
      ),
    );
    if (s != null) setState(() => _supplier = s);
  }

  Future<void> _addProduct() async {
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    if (storeId == null) return;
    final products = await ref.read(productRepositoryProvider).listAll(storeId);
    if (!mounted) return;
    final p = await showModalBottomSheet<Product>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          children: products
              .map((p) => ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: Text(p.name),
                    subtitle: Text('Stock: ${p.stock.toStringAsFixed(0)} • Pri acha: ${MoneyFormatter.format(p.cost)}'),
                    onTap: () => Navigator.pop(context, p),
                  ))
              .toList(),
        ),
      ),
    );
    if (p == null) return;
    final result = await _editLineDialog(initialQty: 1, initialCost: p.cost);
    if (result == null) return;
    setState(() {
      _lines.add(PurchaseLineDraft(product: p, quantity: result.$1, cost: result.$2));
    });
  }

  Future<(double, double)?> _editLineDialog({required double initialQty, required double initialCost}) async {
    final qty = TextEditingController(text: initialQty.toString());
    final cost = TextEditingController(text: initialCost.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Detay liy'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qty,
              decoration: const InputDecoration(labelText: 'Kantite', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cost,
              decoration: const InputDecoration(labelText: 'Pri acha', border: OutlineInputBorder(), suffixText: 'HTG'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anile')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return null;
    final q = double.tryParse(qty.text);
    final c = double.tryParse(cost.text);
    if (q == null || c == null || q <= 0) return null;
    return (q, c);
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajoute pwodwi nan acha.')));
      return;
    }
    final session = ref.read(authControllerProvider).valueOrNull;
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    if (session == null || storeId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(purchaseRepositoryProvider).createPurchase(
            storeId: storeId,
            userId: session.user.id,
            supplierId: _supplier?.id,
            supplierName: _supplier?.name,
            invoiceNumber: _invoiceCtrl.text.trim().isEmpty ? null : _invoiceCtrl.text.trim(),
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            amountPaid: double.tryParse(_paidCtrl.text) ?? 0,
            lines: _lines,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acha anrejistre. Stock ajiste.')));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvo Acha')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.local_shipping),
              title: Text(_supplier?.name ?? 'Pa chwazi yon founisè'),
              subtitle: _supplier?.phone != null ? Text(_supplier!.phone!) : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickSupplier,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _invoiceCtrl,
            decoration: const InputDecoration(labelText: 'Numéwo Faktè', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          const Text('Pwodwi yo', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('Pa gen pwodwi nan acha.')),
              ),
            )
          else
            ..._lines.asMap().entries.map((e) {
              final i = e.key;
              final l = e.value;
              return Card(
                child: ListTile(
                  title: Text(l.product.name),
                  subtitle: Text(
                      '${l.quantity.toStringAsFixed(0)} × ${MoneyFormatter.format(l.cost)} = ${MoneyFormatter.format(l.subtotal)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _lines.removeAt(i)),
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Ajoute Pwodwi'),
            onPressed: _addProduct,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _paidCtrl,
            decoration: const InputDecoration(labelText: 'Kantite peye', border: OutlineInputBorder(), suffixText: 'HTG'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Nòt', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              title: const Text('TOTAL'),
              trailing: Text(
                MoneyFormatter.format(_total),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(_saving ? 'Ap sove…' : 'Anrejistre Acha'),
              onPressed: _saving || _lines.isEmpty ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
