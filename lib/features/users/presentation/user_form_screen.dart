import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../data/user_repository.dart';

final _userProvider = FutureProvider.family.autoDispose<ManagedUser?, String>((ref, id) async {
  final users = await ref.watch(userRepositoryProvider).list();
  return users.where((u) => u.id == id).firstOrNull;
});

class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key, this.userId, this.selfEdit = false});
  final String? userId;
  final bool selfEdit; // true si w ap edite pwòp profil ou

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _role = 'cashier';
  bool _isActive = true;
  bool _saving = false;
  bool _showPassword = false;
  ManagedUser? _existing;

  void _populate(ManagedUser u) {
    if (_existing != null) return;
    _existing = u;
    _nameCtrl.text = u.name;
    _emailCtrl.text = u.email;
    _phoneCtrl.text = u.phone ?? '';
    _role = u.primaryRoleName.isEmpty ? 'cashier' : u.primaryRoleName;
    _isActive = u.isActive;
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _emailCtrl, _phoneCtrl, _passwordCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(userRepositoryProvider);
      if (_existing == null) {
        final storeId = await ref.read(tokenStoreProvider).activeStoreId();
        await repo.create(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          roleName: _role,
          storeId: _role == 'super_admin' ? null : storeId,
        );
      } else {
        await repo.update(
          _existing!.id,
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim() != _existing!.email ? _emailCtrl.text.trim() : null,
          phone: _phoneCtrl.text.trim(),
          password: _passwordCtrl.text.trim().isEmpty ? null : _passwordCtrl.text,
          isActive: widget.selfEdit ? null : _isActive,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_existing == null ? 'Itilizatè kreye!' : 'Itilizatè mete ajou!')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<ManagedUser?> _loadSelf() async {
    return await ref.read(userRepositoryProvider).me();
  }

  Future<void> _delete() async {
    if (_existing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Efase itilizatè sa?'),
        content: Text('${_existing!.name} (${_existing!.email}) ap dezaktive.'),
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
    try {
      await ref.read(userRepositoryProvider).delete(_existing!.id);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.userId == null && !widget.selfEdit;
    final currentAuth = ref.watch(authControllerProvider).valueOrNull;
    final canCreateSuperAdmin = currentAuth?.isSuperAdmin ?? false;

    if (widget.selfEdit) {
      if (_existing == null) {
        _loadSelf().then((u) {
          if (u != null && mounted) {
            setState(() => _populate(u));
          }
        });
      }
    } else if (!isNew) {
      final user = ref.watch(_userProvider(widget.userId!));
      user.whenData((u) {
        if (u != null) _populate(u);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selfEdit ? 'Profil Mwen' : (isNew ? 'Nouvo Itilizatè' : 'Modifye Itilizatè')),
        actions: [
          if (!isNew && !widget.selfEdit && _existing != null && _existing!.id != currentAuth?.user.id)
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
              decoration: const InputDecoration(
                labelText: 'Non konplè *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatwa' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Imel *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              validator: (v) {
                if (v == null || !v.contains('@')) return 'Imel envalid';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Telefòn',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
                hintText: '+509 0000-0000',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            if (!widget.selfEdit)
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Wòl *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.shield),
                ),
                items: [
                  const DropdownMenuItem(value: 'cashier', child: Text('Kèsye (fè vant)')),
                  const DropdownMenuItem(value: 'admin', child: Text('Admin (modifye pwodwi, wè rapò)')),
                  if (canCreateSuperAdmin)
                    const DropdownMenuItem(value: 'super_admin', child: Text('Super Admin (kontwòl total)')),
                ],
                onChanged: isNew ? (v) => setState(() => _role = v ?? 'cashier') : null,
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: isNew ? 'Modpas *' : 'Nouvo Modpas (kite vid pou kenbe)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                helperText: isNew ? 'Minimòm 8 karaktè' : 'Sèlman si w vle chanje',
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) {
                if (isNew && (v == null || v.length < 8)) return 'Minimòm 8 karaktè';
                if (!isNew && v != null && v.isNotEmpty && v.length < 8) return 'Minimòm 8 karaktè';
                return null;
              },
            ),
            if (!isNew && !widget.selfEdit) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Kont aktif'),
                subtitle: Text(_isActive ? 'Itilizatè ka konekte' : 'Bloke — pa ka konekte'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                icon: const Icon(Icons.save),
                label: Text(_saving ? 'Ap sove…' : (isNew ? 'Kreye Itilizatè' : 'Sove Chanjman')),
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
