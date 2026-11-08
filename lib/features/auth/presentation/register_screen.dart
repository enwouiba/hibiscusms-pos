import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessName = TextEditingController();
  final _businessPhone = TextEditingController();
  final _storeName = TextEditingController();
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPhone = TextEditingController();
  final _adminPassword = TextEditingController();
  bool _showPassword = false;
  bool _acceptTerms = false;

  @override
  void dispose() {
    for (final c in [_businessName, _businessPhone, _storeName, _adminName, _adminEmail, _adminPhone, _adminPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tanpri aksepte tèm ak kondisyon yo')),
      );
      return;
    }
    await ref.read(authControllerProvider.notifier).register(
          businessName: _businessName.text,
          adminName: _adminName.text,
          adminEmail: _adminEmail.text,
          adminPassword: _adminPassword.text,
          adminPhone: _adminPhone.text,
          businessPhone: _businessPhone.text,
          storeName: _storeName.text,
        );
    final state = ref.read(authControllerProvider);
    state.whenOrNull(
      error: (e, _) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
          );
        }
      },
      data: (session) {
        if (session != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Kont kreye! Ou gen 18 mwa gratis pou itilize app la.'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.green,
            ),
          );
          context.go('/');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kreye Kont Biznis Ou'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Banèr 18 mwa gratis
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.celebration, color: Colors.white, size: 36),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🎁 18 MWA GRATIS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Kreye kont ou kounye a — Tout fonksyonalite disponib',
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Seksyon Biznis
                  const _SectionTitle('🏪 Enfòmasyon Biznis'),
                  TextFormField(
                    controller: _businessName,
                    decoration: const InputDecoration(
                      labelText: 'Non Biznis Ou *',
                      hintText: 'Egz: Kinkayri Robert',
                      prefixIcon: Icon(Icons.business),
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Antre yon non' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _storeName,
                    decoration: const InputDecoration(
                      labelText: 'Non Magazen Prensipal (opsyonèl)',
                      hintText: 'Si vid, ap pran non biznis lan',
                      prefixIcon: Icon(Icons.store),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _businessPhone,
                    decoration: const InputDecoration(
                      labelText: 'Telefòn Biznis',
                      hintText: '+509 0000-0000',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),

                  const SizedBox(height: 24),

                  // Seksyon Admin
                  const _SectionTitle('👤 Kont Admin (Pwòpriyetè)'),
                  TextFormField(
                    controller: _adminName,
                    decoration: const InputDecoration(
                      labelText: 'Non Konplè Ou *',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Antre non ou' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _adminEmail,
                    decoration: const InputDecoration(
                      labelText: 'Imel *',
                      hintText: 'ou@biznis.com',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
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
                    controller: _adminPhone,
                    decoration: const InputDecoration(
                      labelText: 'Telefòn Ou (opsyonèl)',
                      prefixIcon: Icon(Icons.phone_android),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _adminPassword,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'Modpas *',
                      helperText: 'Minimòm 8 karaktè',
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 8) ? 'Minimòm 8 karaktè' : null,
                  ),

                  const SizedBox(height: 20),

                  // Tèm
                  CheckboxListTile(
                    value: _acceptTerms,
                    onChanged: loading ? null : (v) => setState(() => _acceptTerms = v ?? false),
                    title: const Text(
                      'M aksepte tèm ak kondisyon yo',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      '18 mwa gratis. Apre, ou ka renouvle pou kontinye.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),

                  const SizedBox(height: 16),

                  // Bouton soumèt
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      icon: loading
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.rocket_launch),
                      label: Text(
                        loading ? 'Ap kreye…' : 'KREYE KONT MWEN',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      onPressed: loading ? null : _submit,
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: loading ? null : () => context.go('/login'),
                    child: const Text('Ou gen kont deja? Konekte'),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
