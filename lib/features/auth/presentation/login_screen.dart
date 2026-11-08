import 'dart:io' show stderr;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/constants/app_constants.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    try { stderr.writeln('[login] target=${AppConstants.apiBaseUrl} email=${_emailCtrl.text}'); } catch (_) {}
    await ref.read(authControllerProvider.notifier).login(
          email: _emailCtrl.text,
          password: _passwordCtrl.text,
        );
    try { stderr.writeln('[login] state=${ref.read(authControllerProvider)}'); } catch (_) {}
    final state = ref.read(authControllerProvider);
    state.whenOrNull(
      error: (e, _) async {
        if (!mounted) return;
        final msg = e.toString().toLowerCase();
        final isNetworkFail = msg.contains('timeout') ||
            msg.contains('connection') ||
            msg.contains('socketexception') ||
            msg.contains('failed host lookup') ||
            msg.contains('network is unreachable');
        if (isNetworkFail) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sèvè pa disponib — n ap kòmanse ofline...'),
              duration: Duration(seconds: 2),
            ),
          );
          await ref.read(authControllerProvider.notifier).loginOffline(
                storeName: AppConstants.appName,
                adminName: 'Admin',
                adminEmail: _emailCtrl.text,
              );
          final s2 = ref.read(authControllerProvider);
          s2.whenOrNull(
            data: (session) {
              if (session != null && mounted) context.go('/');
            },
            error: (err, _) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Erè ofline: $err')),
                );
              }
            },
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pa kapab konekte: $e')),
        );
      },
      data: (session) {
        if (session == null || !mounted) return;
        if (session.stores.length == 1) {
          context.go('/');
        } else if (session.stores.length > 1) {
          context.go('/choose-store');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ou pa gen aksè ak okenn magazen.')),
          );
        }
      },
    );
  }

  Future<void> _startOffline() async {
    final storeCtrl = TextEditingController(text: AppConstants.appName);
    final nameCtrl = TextEditingController(text: 'Admin');
    final emailCtrl = TextEditingController(text: _emailCtrl.text);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Kòmanse san entènèt'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ou pral itilize aplikasyon an lokalman.\n\nDone yo ap sove sou tablèt la. Lè entènèt tounen, ou ka migre yo sou sèvè a.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: storeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Non biznis / boutik',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Non ou',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Imel (opsyonèl)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Kanselle'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Kòmanse'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).loginOffline(
          storeName: storeCtrl.text,
          adminName: nameCtrl.text,
          adminEmail: emailCtrl.text,
        );
    final state = ref.read(authControllerProvider);
    state.whenOrNull(
      error: (e, _) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erè: $e')),
          );
        }
      },
      data: (session) {
        if (session != null && mounted) context.go('/');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.isLoading;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppConstants.appName,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  Text(AppConstants.appTagline, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    'Konekte pou kòmanse',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Imel',
                      prefixIcon: Icon(Icons.mail_outline),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enabled: !loading,
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Imel envalid' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: InputDecoration(
                      labelText: 'Modpas',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: _obscurePassword,
                    enabled: !loading,
                    validator: (v) =>
                        (v == null || v.length < 4) ? 'Antre modpas' : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: loading ? null : _submit,
                      child: loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Konekte'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: loading ? null : _startOffline,
                      icon: const Icon(Icons.cloud_off, size: 18),
                      label: const Text('Kòmanse san entènèt'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Pa gen kont? Ale sou pos.stann.store',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
