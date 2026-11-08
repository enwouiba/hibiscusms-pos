import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';

class StorePickerScreen extends ConsumerWidget {
  const StorePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Chwazi yon magazen')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: auth.stores.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final s = auth.stores[i];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.store)),
              title: Text(s.name),
              subtitle: Text('Kòd: ${s.code} • ${s.currency}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await ref.read(authControllerProvider.notifier).setActiveStore(s.id);
                if (context.mounted) context.go('/');
              },
            ),
          );
        },
      ),
    );
  }
}
