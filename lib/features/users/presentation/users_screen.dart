import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/utils/date_formatter.dart';
import '../data/user_repository.dart';

final _usersListProvider = FutureProvider.autoDispose<List<ManagedUser>>((ref) async {
  // Scope sou magazen aktif la — yon kesye yon magazen pa parèt nan lòt la.
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  return ref.watch(userRepositoryProvider).list(storeId: storeId);
});

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(_usersListProvider);
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final canManage = auth != null && auth.highestLevel(null) >= 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jere Itilizatè'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_usersListProvider),
          ),
        ],
      ),
      body: users.when(
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('Pa gen itilizatè.'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final u = list[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _roleColor(u.primaryRoleName).withValues(alpha: 0.2),
                  child: Icon(_roleIcon(u.primaryRoleName), color: _roleColor(u.primaryRoleName)),
                ),
                title: Row(
                  children: [
                    Expanded(child: Text(u.name)),
                    if (!u.isActive)
                      const Chip(
                        label: Text('Dezaktive', style: TextStyle(fontSize: 10)),
                        backgroundColor: Color(0xFFFFEBEE),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.email, style: const TextStyle(fontSize: 12)),
                    Text(
                      u.primaryRoleLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: _roleColor(u.primaryRoleName),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (u.lastLoginAt != null)
                      Text(
                        'Dènye konekte: ${DateFormatter.short(u.lastLoginAt!)}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                  ],
                ),
                isThreeLine: u.lastLoginAt != null,
                trailing: canManage ? const Icon(Icons.chevron_right) : null,
                onTap: canManage ? () => context.push('/users/${u.id}') : null,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.person_add),
              label: const Text('Nouvo Kèsye'),
              onPressed: () => context.push('/users/new'),
            )
          : null,
    );
  }

  Color _roleColor(String role) => switch (role) {
        'super_admin' => Colors.purple,
        'admin' => Colors.blue,
        'cashier' => Colors.green,
        _ => Colors.grey,
      };

  IconData _roleIcon(String role) => switch (role) {
        'super_admin' => Icons.workspace_premium,
        'admin' => Icons.shield,
        'cashier' => Icons.point_of_sale,
        _ => Icons.person,
      };
}
