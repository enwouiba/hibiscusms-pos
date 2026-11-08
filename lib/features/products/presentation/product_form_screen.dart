import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../shared/models/category.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/unit.dart';
import '../data/category_repository.dart';
import '../data/product_repository.dart';

final _productProvider = FutureProvider.family.autoDispose<Product?, String>((ref, id) async {
  final repo = ref.watch(productRepositoryProvider);
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return null;
  return repo.findById(storeId, id);
});

final _unitsProvider = FutureProvider.autoDispose<List<Unit>>((ref) async {
  return ref.watch(productRepositoryProvider).listUnits();
});

final _categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  return ref.watch(productRepositoryProvider).listCategories(storeId);
});

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});
  final String? productId;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '0');
  final _stockCtrl = TextEditingController(text: '0');
  final _alertCtrl = TextEditingController(text: '5');
  String? _categoryId;
  String? _unitId;
  bool _trackStock = true;
  bool _saving = false;
  Product? _existing;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _skuCtrl, _barcodeCtrl, _priceCtrl, _costCtrl, _taxCtrl, _stockCtrl, _alertCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _populate(Product p) {
    if (_existing != null) return;
    _existing = p;
    _nameCtrl.text = p.name;
    _skuCtrl.text = p.sku ?? '';
    _barcodeCtrl.text = p.barcode ?? '';
    _priceCtrl.text = p.price.toStringAsFixed(2);
    _costCtrl.text = p.cost.toStringAsFixed(2);
    _taxCtrl.text = p.taxRate.toStringAsFixed(2);
    _stockCtrl.text = p.stock.toStringAsFixed(0);
    _alertCtrl.text = p.lowStockAlert.toStringAsFixed(0);
    _categoryId = p.categoryId;
    _unitId = p.unitId;
    _trackStock = p.trackStock;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_unitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chwazi yon inite.')));
      return;
    }
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    if (storeId == null) return;
    final repo = ref.read(productRepositoryProvider);
    setState(() => _saving = true);
    try {
      if (_existing == null) {
        await repo.create(
          storeId: storeId,
          name: _nameCtrl.text.trim(),
          unitId: _unitId!,
          categoryId: _categoryId,
          sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
          barcode: _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
          price: double.parse(_priceCtrl.text.replaceAll(',', '')),
          cost: double.parse(_costCtrl.text.isEmpty ? '0' : _costCtrl.text.replaceAll(',', '')),
          taxRate: double.parse(_taxCtrl.text.isEmpty ? '0' : _taxCtrl.text),
          trackStock: _trackStock,
          initialStock: double.parse(_stockCtrl.text.isEmpty ? '0' : _stockCtrl.text),
          lowStockAlert: double.parse(_alertCtrl.text.isEmpty ? '5' : _alertCtrl.text),
        );
      } else {
        final updated = _existing!.copyWith(
          name: _nameCtrl.text.trim(),
          categoryId: _categoryId,
          unitId: _unitId,
          sku: _skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim(),
          barcode: _barcodeCtrl.text.trim().isEmpty ? null : _barcodeCtrl.text.trim(),
          price: double.parse(_priceCtrl.text.replaceAll(',', '')),
          cost: double.parse(_costCtrl.text.isEmpty ? '0' : _costCtrl.text.replaceAll(',', '')),
          taxRate: double.parse(_taxCtrl.text.isEmpty ? '0' : _taxCtrl.text),
          trackStock: _trackStock,
        );
        await repo.update(updated);
        final newStock = double.parse(_stockCtrl.text.isEmpty ? '0' : _stockCtrl.text);
        final newAlert = double.parse(_alertCtrl.text.isEmpty ? '5' : _alertCtrl.text);
        if (newStock != _existing!.stock || newAlert != _existing!.lowStockAlert) {
          await repo.updateStock(
            storeId: storeId,
            productId: _existing!.id,
            newStock: newStock,
            lowStockAlert: newAlert,
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pwodwi sove.')));
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

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Efase pwodwi sa?'),
        content: const Text('Aksyon sa pap reveni.'),
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
    await ref.read(productRepositoryProvider).delete(_existing!.id);
    if (mounted) context.pop();
  }

  Future<void> _addCategoryDialog() async {
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouvo Kategori'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Non kategori',
            border: OutlineInputBorder(),
            hintText: 'Egz: Pent, Tib, Vis',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anile')),
          FilledButton(
            onPressed: () {
              final v = nameCtrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            child: const Text('Kreye'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (result == null) return;
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    if (storeId == null) return;
    try {
      final cat = await ref.read(categoryRepositoryProvider).create(
            storeId: storeId,
            name: result,
          );
      ref.invalidate(_categoriesProvider);
      setState(() => _categoryId = cat.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kategori "${cat.name}" kreye!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  Future<void> _addUnitDialog() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    int decimals = 0;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nouvo Inite'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Kòd (egz: bk, doz)',
                  border: OutlineInputBorder(),
                  hintText: 'Mwens ke 10 lèt',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Non konplè',
                  border: OutlineInputBorder(),
                  hintText: 'Egz: Bokal, Douzèn',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Dezimal:'),
                  const Spacer(),
                  DropdownButton<int>(
                    value: decimals,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('0 (1, 2, 3...)')),
                      DropdownMenuItem(value: 1, child: Text('1 (0.5, 1.5)')),
                      DropdownMenuItem(value: 2, child: Text('2 (0.25, 0.50)')),
                      DropdownMenuItem(value: 3, child: Text('3 (0.125)')),
                    ],
                    onChanged: (v) => setDialogState(() => decimals = v ?? 0),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anile')),
            FilledButton(
              onPressed: () {
                final c = codeCtrl.text.trim().toLowerCase();
                final n = nameCtrl.text.trim();
                if (c.isNotEmpty && n.isNotEmpty) {
                  Navigator.pop(context, {'code': c, 'name': n, 'decimals': decimals});
                }
              },
              child: const Text('Kreye'),
            ),
          ],
        ),
      ),
    );
    codeCtrl.dispose();
    nameCtrl.dispose();
    if (result == null) return;
    try {
      final unit = await ref.read(categoryRepositoryProvider).createUnit(
            code: result['code'] as String,
            name: result['name'] as String,
            decimals: result['decimals'] as int,
          );
      ref.invalidate(_unitsProvider);
      setState(() => _unitId = unit.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Inite "${unit.name}" kreye!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.productId == null;
    // Sekretè (cashier) pa ka ajoute/modifye/efase pwodwi — lekti sèlman.
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final canManage = auth != null && auth.highestLevel(null) >= 2;

    if (!isNew) {
      final p = ref.watch(_productProvider(widget.productId!));
      p.whenData((value) {
        if (value != null) _populate(value);
      });
    }

    final unitsAsync = ref.watch(_unitsProvider);
    final categoriesAsync = ref.watch(_categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nouvo Pwodwi' : (canManage ? 'Modifye Pwodwi' : 'Detay Pwodwi')),
        actions: [
          if (!isNew && canManage)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Non pwodwi *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatwa' : null,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _skuCtrl,
                    decoration: const InputDecoration(labelText: 'SKU', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _barcodeCtrl,
                    decoration: const InputDecoration(labelText: 'Barcode', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            unitsAsync.when(
              data: (units) => Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _unitId,
                      decoration: const InputDecoration(labelText: 'Inite *', border: OutlineInputBorder()),
                      items: units.map((u) => DropdownMenuItem(value: u.id, child: Text('${u.name} (${u.code})'))).toList(),
                      onChanged: (v) => setState(() => _unitId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.add),
                    tooltip: 'Nouvo inite',
                    onPressed: () => _addUnitDialog(),
                  ),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erè inite: $e'),
            ),
            const SizedBox(height: 12),
            categoriesAsync.when(
              data: (cats) => Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _categoryId,
                      decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem(value: null, child: Text('Pa gen kategori')),
                        ...cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.add),
                    tooltip: 'Nouvo kategori',
                    onPressed: () => _addCategoryDialog(),
                  ),
                ],
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erè kategori: $e'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceCtrl,
                    decoration: const InputDecoration(labelText: 'Pri vant *', border: OutlineInputBorder(), suffixText: 'HTG'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                    validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '')) == null) ? 'Pri envalid' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _costCtrl,
                    decoration: const InputDecoration(labelText: 'Pri acha', border: OutlineInputBorder(), suffixText: 'HTG'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _taxCtrl,
              decoration: const InputDecoration(labelText: 'TCA %', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Swiv stock'),
              value: _trackStock,
              onChanged: (v) => setState(() => _trackStock = v),
              contentPadding: EdgeInsets.zero,
            ),
            if (_trackStock) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stockCtrl,
                      decoration: const InputDecoration(labelText: 'Stock', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _alertCtrl,
                      decoration: const InputDecoration(labelText: 'Alèt si anba', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            if (canManage)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: Text(_saving ? 'Ap sove…' : 'Sove'),
                  onPressed: _saving ? null : _save,
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lekti sèlman — ou pa gen dwa modifye stock/pwodwi.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
