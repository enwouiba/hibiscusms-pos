import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/token_store.dart';
import '../../../shared/models/supplier.dart';
import '../data/supplier_repository.dart';

final _supplierProvider = FutureProvider.family.autoDispose<Supplier?, String>((ref, id) {
  return ref.watch(supplierRepositoryProvider).findById(id);
});

class SupplierFormScreen extends ConsumerStatefulWidget {
  const SupplierFormScreen({super.key, this.supplierId});
  final String? supplierId;

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Supplier? _existing;
  bool _saving = false;

  void _populate(Supplier s) {
    if (_existing != null) return;
    _existing = s;
    _nameCtrl.text = s.name;
    _contactCtrl.text = s.contactName ?? '';
    _phoneCtrl.text = s.phone ?? '';
    _emailCtrl.text = s.email ?? '';
    _addressCtrl.text = s.address ?? '';
    _notesCtrl.text = s.notes ?? '';
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _contactCtrl, _phoneCtrl, _emailCtrl, _addressCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    if (storeId == null) return;
    final repo = ref.read(supplierRepositoryProvider);
    setState(() => _saving = true);
    try {
      if (_existing == null) {
        await repo.create(
          storeId: storeId,
          name: _nameCtrl.text.trim(),
          contactName: _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      } else {
        await repo.update(_existing!.copyWith(
          name: _nameCtrl.text.trim(),
          contactName: _contactCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
        ));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Founisè sove.')));
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
    if (_existing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Efase founisè sa?'),
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
    await ref.read(supplierRepositoryProvider).delete(_existing!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.supplierId == null;
    if (!isNew) {
      final s = ref.watch(_supplierProvider(widget.supplierId!));
      s.whenData((v) {
        if (v != null) _populate(v);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nouvo Founisè' : 'Modifye Founisè'),
        actions: [
          if (!isNew) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Non founisè *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatwa' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _contactCtrl,
              decoration: const InputDecoration(labelText: 'Non kontak', border: OutlineInputBorder()),
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
