import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money_formatter.dart';
import '../data/system_owner_repository.dart';

final _tenantsProvider = FutureProvider.autoDispose<List<TenantSummary>>((ref) async {
  return ref.watch(systemOwnerRepositoryProvider).listTenants();
});

final _renewalsProvider = FutureProvider.autoDispose<List<RenewalReq>>((ref) async {
  return ref.watch(systemOwnerRepositoryProvider).listRenewals();
});

class SystemOwnerScreen extends ConsumerStatefulWidget {
  const SystemOwnerScreen({super.key});

  @override
  ConsumerState<SystemOwnerScreen> createState() => _SystemOwnerScreenState();
}

class _SystemOwnerScreenState extends ConsumerState<SystemOwnerScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Owner'),
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(icon: Icon(Icons.business), text: 'Tenants'),
          Tab(icon: Icon(Icons.payment), text: 'Renewals'),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(_tenantsProvider);
              ref.invalidate(_renewalsProvider);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_TenantsTab(), _RenewalsTab()],
      ),
    );
  }
}

class _TenantsTab extends ConsumerWidget {
  const _TenantsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenants = ref.watch(_tenantsProvider);
    return tenants.when(
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('Pa gen tenant.'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final t = list[i];
            final color = t.isExpired
                ? Colors.red
                : t.daysRemaining <= 30
                    ? Colors.orange
                    : Colors.green;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.2),
                  child: Icon(Icons.business, color: color),
                ),
                title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.email ?? '—', style: const TextStyle(fontSize: 12)),
                    Row(
                      children: [
                        Chip(
                          label: Text(t.plan, style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        const SizedBox(width: 4),
                        Chip(
                          label: Text('${t.storesCount}🏪 ${t.usersCount}👤',
                              style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${t.daysRemaining}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const Text('jou', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                isThreeLine: true,
                onTap: () => _showTenantActions(context, ref, t),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('Erè: $e'))),
    );
  }

  Future<void> _showTenantActions(BuildContext context, WidgetRef ref, TenantSummary t) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text(t.email ?? '—', style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Text(t.expiresAt != null ? 'Ekspire: ${DateFormat('dd/MM/yyyy').format(t.expiresAt!)}' : ''),
                Text('${t.daysRemaining} jou rete'),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.green),
            title: const Text('Etann 1 Mwa'),
            onTap: () async {
              Navigator.pop(context);
              await _doExtend(context, ref, t, 1);
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.green),
            title: const Text('Etann 6 Mwa'),
            onTap: () async {
              Navigator.pop(context);
              await _doExtend(context, ref, t, 6);
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.green),
            title: const Text('Etann 12 Mwa'),
            onTap: () async {
              Navigator.pop(context);
              await _doExtend(context, ref, t, 12);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.workspace_premium, color: Colors.purple),
            title: const Text('Bay yon Plan'),
            subtitle: const Text('Granti yon plan dirèkteman (san peman)'),
            onTap: () async {
              Navigator.pop(context);
              await _doGrantPlan(context, ref, t);
            },
          ),
          const Divider(height: 1),
          if (t.status == 'active')
            ListTile(
              leading: const Icon(Icons.pause_circle, color: Colors.orange),
              title: const Text('Sispann'),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(systemOwnerRepositoryProvider).setStatus(t.id, 'suspended');
                ref.invalidate(_tenantsProvider);
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.play_circle, color: Colors.green),
              title: const Text('Aktive'),
              onTap: () async {
                Navigator.pop(context);
                await ref.read(systemOwnerRepositoryProvider).setStatus(t.id, 'active');
                ref.invalidate(_tenantsProvider);
              },
            ),
          const SafeArea(child: SizedBox(height: 8)),
        ],
      ),
    );
  }

  Future<void> _doGrantPlan(BuildContext context, WidgetRef ref, TenantSummary t) async {
    try {
      final plans = await ref.read(systemOwnerRepositoryProvider).listPlans();
      if (!context.mounted) return;

      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bay yon Plan — ${t.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text('Plan ap aktive imedyatman, san peman necessè.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: plans.length,
                  itemBuilder: (context, i) {
                    final p = plans[i];
                    final isLifetime = p['code'] == 'lifetime' || p['duration_months'] == null;
                    final price = double.tryParse(p['price'].toString()) ?? 0;
                    final isFree = price == 0;
                    final months = p['duration_months'];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      color: isLifetime
                          ? Colors.orange.shade50
                          : isFree
                              ? Colors.green.shade50
                              : null,
                      child: ListTile(
                        leading: Icon(
                          isLifetime
                              ? Icons.diamond
                              : isFree
                                  ? Icons.card_giftcard
                                  : Icons.subscriptions,
                          color: isLifetime
                              ? Colors.orange
                              : isFree
                                  ? Colors.green
                                  : Colors.blue,
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(p['label'] as String)),
                            if (isLifetime)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('👑 RÈN',
                                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          isFree
                              ? 'Gratis · ${months ?? "?"} ${months != null ? "mwa" : "jou"}'
                              : '${price.toStringAsFixed(0)} HTG · '
                                  '${isLifetime ? "Tout tan" : "$months mwa"}',
                        ),
                        onTap: () => Navigator.pop(context, p),
                      ),
                    );
                  },
                ),
              ),
              const SafeArea(child: SizedBox(height: 8)),
            ],
          ),
        ),
      );

      if (selected == null || !context.mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Konfime'),
          content: Text(
            'Bay tenant "${t.name}" plan "${selected['label']}"?\n\n'
            '${selected['code'] == 'lifetime' ? '⚠️ Pa janm ekspire.' : ''}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anile')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Konfime'),
            ),
          ],
        ),
      );
      if (confirm != true || !context.mounted) return;

      await ref.read(systemOwnerRepositoryProvider).grantPlan(
            t.id,
            planCode: selected['code'] as String,
          );
      ref.invalidate(_tenantsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plan "${selected['label']}" bay ${t.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  Future<void> _doExtend(BuildContext context, WidgetRef ref, TenantSummary t, int months) async {
    try {
      await ref.read(systemOwnerRepositoryProvider).extendTenant(t.id, months: months);
      ref.invalidate(_tenantsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t.name} etann pa $months mwa.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }
}

class _RenewalsTab extends ConsumerWidget {
  const _RenewalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renewals = ref.watch(_renewalsProvider);
    return renewals.when(
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('Pa gen demann renouvèlman.'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = list[i];
            final tname = r.tenant?['name'] as String? ?? r.tenantId;
            final isPending = r.status == 'pending';
            return Card(
              color: isPending ? Colors.amber.shade50 : null,
              child: ListTile(
                leading: Icon(
                  isPending ? Icons.pending : (r.status == 'approved' ? Icons.check_circle : Icons.cancel),
                  color: isPending ? Colors.orange : (r.status == 'approved' ? Colors.green : Colors.red),
                ),
                title: Text(tname),
                subtitle: Text(
                  '${r.plan} • ${MoneyFormatter.format(r.amount)} ${r.currency}\n'
                  '${r.paymentMethod ?? "—"} • ${r.paymentReference ?? ""}',
                ),
                isThreeLine: true,
                trailing: isPending
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () async {
                              await ref.read(systemOwnerRepositoryProvider).approveRenewal(r.id);
                              ref.invalidate(_renewalsProvider);
                              ref.invalidate(_tenantsProvider);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () async {
                              await ref.read(systemOwnerRepositoryProvider).rejectRenewal(r.id);
                              ref.invalidate(_renewalsProvider);
                            },
                          ),
                        ],
                      )
                    : Chip(label: Text(r.status), visualDensity: VisualDensity.compact),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('Erè: $e'))),
    );
  }
}
