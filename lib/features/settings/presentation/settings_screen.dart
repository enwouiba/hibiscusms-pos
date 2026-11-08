import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/constants/app_constants.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    // Kesye (cashier) pa gen akse paramèt biznis la — admin sèlman.
    final canManage = auth != null && auth.highestLevel(null) >= 2;
    return Scaffold(
      appBar: AppBar(title: const Text('Paramèt')),
      body: ListView(
        children: [
          if (auth != null) ...[
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(auth.user.name),
              subtitle: Text(auth.user.email),
            ),
            const Divider(),
          ],
          ListTile(
            leading: const Icon(Icons.person, color: Colors.teal),
            title: const Text('Profil Mwen'),
            subtitle: const Text('Chanje imel, telefòn, modpas'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/profile'),
          ),
          if (canManage)
            ListTile(
              leading: const Icon(Icons.business, color: Colors.indigo),
              title: const Text('Paramèt Biznis'),
              subtitle: const Text('Non, adrès, telefòn, NIF, imel'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/business'),
            ),
          ListTile(
            leading: const Icon(Icons.print),
            title: const Text('Konfigirе Printer'),
            subtitle: const Text('SUNMI entegre oswa Bluetooth'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/printer'),
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Chanje Magazen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/choose-store'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('Apa de ${AppConstants.appName}'),
            subtitle: const Text('v1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Dekonekte', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
