import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/store.dart';
import '../data/store_repository.dart';
import '../data/tenant_repository.dart';

final _activeStoreProvider = FutureProvider.autoDispose<Store?>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return null;
  return ref.watch(storeRepositoryProvider).findById(storeId);
});

class BusinessSettingsScreen extends ConsumerStatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  ConsumerState<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends ConsumerState<BusinessSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  Store? _store;
  bool _saving = false;
  bool _uploadingLogo = false;
  File? _pickedLogo;
  String? _remoteLogoUrl;

  void _populateStore(Store s) {
    if (_store != null) return;
    _store = s;
    _nameCtrl.text = s.name;
    _addressCtrl.text = s.address ?? '';
    _phoneCtrl.text = s.phone ?? '';
    _emailCtrl.text = s.email ?? '';
    _footerCtrl.text = s.footerText ?? 'Mèsi paske w achte lakay nou!';
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _addressCtrl, _phoneCtrl, _emailCtrl, _footerCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pickedLogo = File(picked.path);
      _uploadingLogo = true;
    });
    try {
      final url = await ref.read(tenantRepositoryProvider).uploadLogo(File(picked.path));
      if (mounted) {
        setState(() => _remoteLogoUrl = url);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo upload ak siksè!'), backgroundColor: Colors.green),
        );
        ref.invalidate(currentTenantProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erè upload logo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _offerRebuildApk(bool nameChanged, bool logoChanged) async {
    final messenger = ScaffoldMessenger.of(context);
    final changes = <String>[];
    if (nameChanged) changes.add('non');
    if (logoChanged) changes.add('logo');
    final what = changes.join(' + ');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎨 Mete ajou Launcher?'),
        content: Text(
          'Ou chanje $what biznis ou. Pou non + ikon nan launcher Android lan reflè '
          'sa, sistèm nan dwe bati yon nouvo APK ki gen non + logo ou ladan.\n\n'
          'Sa pran ~10 minit. Lè li pare, w ap jwenn yon notifikasyon pou enstale l.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Pita')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bati Kounya')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/api/tenant/mobile-build/request', data: {});
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ Demann APK soumèt. Gade nan "APK Pèsonalize" pou estati.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Pa kapab mande APK: $e')));
    }
  }

  Future<void> _save() async {
    if (_store == null || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final newSettings = Map<String, dynamic>.from(_store!.settings);
      newSettings['footer_text'] = _footerCtrl.text.trim();
      if (_emailCtrl.text.trim().isNotEmpty) {
        newSettings['email'] = _emailCtrl.text.trim();
      } else {
        newSettings.remove('email');
      }
      final updated = _store!.copyWith(
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        settings: newSettings,
      );
      await ref.read(storeRepositoryProvider).update(updated);

      // Sync nivo Tenant tou — non, imel, telefòn
      try {
        await ref.read(tenantRepositoryProvider).update(
              name: _nameCtrl.text.trim(),
              email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
              phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
            );
        ref.invalidate(currentTenantProvider);
      } catch (_) {
        // Si pa Super Admin, paka. Pa bloke save.
      }

      ref.invalidate(_activeStoreProvider);

      // Detekte si non oswa logo chanje → ofri rebati APK
      final nameChanged = _nameCtrl.text.trim() != (_store?.name ?? '');
      final logoChanged = _pickedLogo != null || _remoteLogoUrl != null;

      if (mounted) {
        if (nameChanged || logoChanged) {
          await _offerRebuildApk(nameChanged, logoChanged);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Paramèt biznis sove. Pwochen resi yo ap montre l.')),
          );
        }
        if (mounted) context.pop();
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
    final storeAsync = ref.watch(_activeStoreProvider);
    final tenantAsync = ref.watch(currentTenantProvider);
    storeAsync.whenData((v) {
      if (v != null) _populateStore(v);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Paramèt Biznis')),
      body: storeAsync.when(
        data: (store) {
          if (store == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.store_mall_directory_outlined, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Magazen ou poko sinkronize.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tann kèk segond apre login pou done biznis ou desann.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reye'),
                      onPressed: () => ref.invalidate(_activeStoreProvider),
                    ),
                  ],
                ),
              ),
            );
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _logoCard(tenantAsync),
                const SizedBox(height: 16),
                tenantAsync.maybeWhen(
                  data: (t) => _planCard(t),
                  orElse: () => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Non Biznis *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store),
                    helperText: 'Sa k ap parèt nan tèt resi a',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatwa' : null,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Adrès',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                    hintText: 'Egz: Ri Capois 25, Pòtoprens',
                  ),
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
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
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Imel (opsyonèl)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _footerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mo Remèsiman',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.message),
                    helperText: 'Mesaj ki ap parèt anba chak resi',
                  ),
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),
                _ReceiptPreview(
                  businessName: _nameCtrl.text,
                  address: _addressCtrl.text,
                  phone: _phoneCtrl.text,
                  email: _emailCtrl.text,
                  footer: _footerCtrl.text,
                  remoteLogoUrl: _remoteLogoUrl,
                  pickedLogo: _pickedLogo,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: Text(_saving ? 'Ap sove…' : 'Sove Paramèt'),
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
    );
  }

  Widget _logoCard(AsyncValue<TenantProfile> tenantAsync) {
    final tenantLogoUrl = tenantAsync.valueOrNull?.logoUrl;
    final effectiveUrl = _remoteLogoUrl ?? tenantLogoUrl;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _pickedLogo != null
                  ? Image.file(_pickedLogo!, width: 96, height: 96, fit: BoxFit.cover)
                  : (effectiveUrl != null && effectiveUrl.isNotEmpty)
                      ? Image.network(
                          effectiveUrl,
                          width: 96, height: 96, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Image.asset('assets/images/app_icon.png', width: 96, height: 96),
                        )
                      : Image.asset('assets/images/app_icon.png', width: 96, height: 96),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: _uploadingLogo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload),
              label: Text(_uploadingLogo ? 'Ap upload…' : 'Chanje Logo'),
              onPressed: _uploadingLogo ? null : _pickLogo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _planCard(TenantProfile t) {
    final isLifetime = t.expiresAt == null;
    final color = isLifetime
        ? Colors.orange
        : t.daysRemaining < 5
            ? Colors.red
            : t.daysRemaining < 30
                ? Colors.amber
                : Colors.green;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(isLifetime ? Icons.diamond : Icons.access_time, color: color),
        ),
        title: Text(
          'Plan: ${t.plan.toUpperCase()}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          isLifetime
              ? '👑 Pou tout vi — pa janm ekspire'
              : '${t.daysRemaining} jou rete${t.isExpired ? " (EKSPIRE)" : ""}',
        ),
        trailing: Chip(
          label: Text(t.status.toUpperCase(), style: const TextStyle(fontSize: 10)),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({
    required this.businessName,
    required this.address,
    required this.phone,
    required this.email,
    required this.footer,
    this.remoteLogoUrl,
    this.pickedLogo,
  });
  final String businessName;
  final String address;
  final String phone;
  final String email;
  final String footer;
  final String? remoteLogoUrl;
  final File? pickedLogo;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('PREVI RESI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            pickedLogo != null
                ? Image.file(pickedLogo!, width: 60, height: 60, fit: BoxFit.cover)
                : (remoteLogoUrl != null && remoteLogoUrl!.isNotEmpty)
                    ? Image.network(remoteLogoUrl!, width: 60, height: 60,
                        errorBuilder: (_, __, ___) => Image.asset('assets/images/app_icon.png', width: 60, height: 60))
                    : Image.asset('assets/images/app_icon.png', width: 60, height: 60),
            const SizedBox(height: 4),
            Text(
              businessName.isEmpty ? '(Non Biznis)' : businessName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            if (phone.isNotEmpty)
              Text('Tel: $phone', style: const TextStyle(fontSize: 11)),
            if (address.isNotEmpty)
              Text(address, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
            if (email.isNotEmpty)
              Text(email, style: const TextStyle(fontSize: 11)),
            const Divider(),
            const Text(
              'Resi #001 — 28/05/2026 14:30',
              style: TextStyle(fontSize: 11),
            ),
            const Text('Sak Sement × 2     1,700 HTG', style: TextStyle(fontSize: 10)),
            const Text('Mato 16oz × 1        750 HTG', style: TextStyle(fontSize: 10)),
            const Divider(),
            const Text('TOTAL: 2,450 HTG', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              footer.isEmpty ? 'Mèsi paske w achte lakay nou!' : footer,
              style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
