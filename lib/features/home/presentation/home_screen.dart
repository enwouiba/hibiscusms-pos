import 'dart:io' show stderr;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/store.dart';
import '../../adjustments/data/adjustment_repository.dart';
import '../../business/data/store_repository.dart';

/// Magazen aktif la — pou konnen tip li (retail vs dry cleaning).
final _activeStoreProvider = FutureProvider.autoDispose<Store?>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return null;
  return ref.watch(storeRepositoryProvider).findById(storeId);
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final sync = ref.watch(syncProgressProvider);
    final isDry = ref.watch(_activeStoreProvider).valueOrNull?.isDryCleaning ?? false;

    if (auth == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final tenantName = auth.tenant?.name ?? AppConstants.appName;
    return Scaffold(
      appBar: AppBar(
        title: Text(tenantName),
        backgroundColor: auth.isSystemOwner ? Colors.purple : null,
        actions: [
          if (auth.isSystemOwner)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'System Owner',
              onPressed: () => context.push('/system-owner'),
            )
          else
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Chanje magazen',
              onPressed: () => context.go('/choose-store'),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Dekonekte',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_homeStatsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _UserCard(user: auth.user),
            const SizedBox(height: 8),
            sync.when(
              data: (p) => _SyncBanner(progress: p),
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('Sync erè: $e'),
            ),
            // Kat plan — admin sèlman + sèlman si gen tenant info
            if (auth.highestLevel(null) >= 2 && auth.tenant != null) ...[
              const SizedBox(height: 12),
              _PlanCard(tenant: auth.tenant!),
            ],
            // Kat earnings — admin sèlman
            if (auth.highestLevel(null) >= 2) ...[
              const SizedBox(height: 12),
              const _EarningsCard(),
            ],
            const SizedBox(height: 16),
            _MenuGrid(canManage: auth.highestLevel(null) >= 2, isDryCleaning: isDry),
          ],
        ),
      ),
    );
  }
}

class _LifetimeTotals {
  final double net;    // Vant Nèt — sèl completed
  final double credit; // Vant Kredit — sèl credit
  final double gross;  // Vant Brut — completed + credit
  const _LifetimeTotals({required this.net, required this.credit, required this.gross});
}

// Total lifetime — 3 chif klè:
//  NÈT   = kob KI REYÈLMAN ANTRE (sales.amount_received + customer_payments)
//  KREDIT = dèt ki rete (total - amount_received sou vant kredit)
//  BRUT  = valè total tout vant ki fèt (SUM(total))
final _lifetimeSalesProvider = FutureProvider.autoDispose<_LifetimeTotals>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  try { stderr.writeln('[home] lifetimeSales storeId=$storeId'); } catch (_) {}
  if (storeId == null) return const _LifetimeTotals(net: 0, credit: 0, gross: 0);
  final db = ref.watch(databaseProvider).requireValue;
  try {
    final probe = await db.rawQuery('SELECT COUNT(*) AS n FROM sales WHERE store_id = ?', [storeId]);
    stderr.writeln('[home] sales.count(storeId=$storeId) = ${probe.first['n']}');
  } catch (_) {}

  // 1) Sales — kob peye + dèt rete + total brut
  final salesRow = await db.rawQuery('''
    SELECT
      COALESCE(SUM(amount_received), 0) AS received,
      COALESCE(SUM(CASE WHEN status = 'credit' THEN (total - amount_received) ELSE 0 END), 0) AS debt_left,
      COALESCE(SUM(total), 0) AS gross
    FROM sales
    WHERE store_id = ?
      AND deleted_at IS NULL
      AND status IN ('completed', 'credit')
  ''', [storeId]);

  // 2) Peman dèt yo — SÈLMAN kredit `type='payment'`, PA dèt ajoute manyèl
  final paymentsRow = await db.rawQuery('''
    SELECT COALESCE(SUM(amount), 0) AS paid_debt
    FROM customer_payments
    WHERE (store_id = ? OR store_id IS NULL)
      AND type = 'payment'
  ''', [storeId]);

  // 3) Dèt aktyèl kliyan yo (source la verite: customers.balance)
  //    Sa enkli dèt manyèl ki fèk ajoute yo tou
  final debtNowRow = await db.rawQuery('''
    SELECT COALESCE(SUM(balance), 0) AS total_debt
    FROM customers
    WHERE (store_id = ? OR store_id IS NULL) AND deleted_at IS NULL
      AND balance > 0
  ''', [storeId]);

  // 4) Ajisteman manyèl (v6) — +/- sou VANT NÈT ak KREDIT
  final adjRow = await db.rawQuery('''
    SELECT
      COALESCE(SUM(CASE WHEN target='net' AND operation='add' THEN amount ELSE 0 END), 0) AS net_add,
      COALESCE(SUM(CASE WHEN target='net' AND operation='subtract' THEN amount ELSE 0 END), 0) AS net_sub,
      COALESCE(SUM(CASE WHEN target='credit' AND operation='add' THEN amount ELSE 0 END), 0) AS credit_add,
      COALESCE(SUM(CASE WHEN target='credit' AND operation='subtract' THEN amount ELSE 0 END), 0) AS credit_sub
    FROM manual_adjustments
    WHERE (store_id = ? OR store_id IS NULL)
      AND (deleted_at IS NULL OR deleted_at = '')
  ''', [storeId]);

  final received = (salesRow.first['received'] as num?)?.toDouble() ?? 0;
  final gross = (salesRow.first['gross'] as num?)?.toDouble() ?? 0;
  final paidDebt = (paymentsRow.first['paid_debt'] as num?)?.toDouble() ?? 0;
  final actualDebt = (debtNowRow.first['total_debt'] as num?)?.toDouble() ?? 0;
  final netAdj = (adjRow.first['net_add'] as num).toDouble() - (adjRow.first['net_sub'] as num).toDouble();
  final creditAdj = (adjRow.first['credit_add'] as num).toDouble() - (adjRow.first['credit_sub'] as num).toDouble();

  // NÈT = kob ki REYÈLMAN antre + ajisteman
  final net = received + paidDebt + netAdj;
  // KREDIT = dèt aktyèl + ajisteman
  final credit = (actualDebt + creditAdj).clamp(0, double.infinity).toDouble();
  // BRUT = NET + KREDIT (invaryan)
  return _LifetimeTotals(net: net, credit: credit, gross: net + credit);
});

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user});
  final AuthUser user;

  Widget _statTile(String label, double amount, Color color, {VoidCallback? onAdd, VoidCallback? onSub}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            MoneyFormatter.format(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        if (onAdd != null || onSub != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onAdd != null)
                InkWell(
                  onTap: onAdd,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.add, size: 14, color: Colors.green.shade800),
                  ),
                ),
              const SizedBox(width: 4),
              if (onSub != null)
                InkWell(
                  onTap: onSub,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.remove, size: 14, color: Colors.red.shade800),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _openAdjustDialog(BuildContext context, WidgetRef ref,
      {required String target, required String operation}) async {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final isAdd = operation == 'add';
    final targetLabel = target == 'net' ? 'VANT NÈT' : 'KREDIT';
    final actionLabel = isAdd ? '➕ Ajoute' : '➖ Retire';
    final color = isAdd ? Colors.green.shade700 : Colors.red.shade700;

    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16, right: 16, top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            )),
            Text('$actionLabel — $targetLabel',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 6),
            Text(
              isAdd
                ? 'Ajoute yon mòn manyèl nan $targetLabel'
                : 'Retire yon mòn manyèl nan $targetLabel',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Mòn *',
                suffixText: 'HTG',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final v in [100, 200, 500, 1000, 2000])
                ActionChip(label: Text(MoneyFormatter.format(v.toDouble())),
                  onPressed: () => amountCtrl.text = v.toStringAsFixed(2)),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Rezon (obligatwa) *',
                hintText: 'Egzanp: Kob boss met nan kès, retire pou peye, elt.',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLength: 200,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Nòt (opsyonèl)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Anile')),
              )),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: FilledButton.icon(
                icon: Icon(isAdd ? Icons.add_circle : Icons.remove_circle),
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: () {
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                  final rez = reasonCtrl.text.trim();
                  if (amt <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Antre yon mòn valab')));
                    return;
                  }
                  if (rez.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Antre yon rezon')));
                    return;
                  }
                  Navigator.pop(ctx, {
                    'amount': amt,
                    'reason': rez,
                    'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  });
                },
                label: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(isAdd ? 'Ajoute' : 'Retire')),
              )),
            ]),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    amountCtrl.dispose();
    reasonCtrl.dispose();
    notesCtrl.dispose();
    if (result == null) return;

    try {
      final storeId = await ref.read(tokenStoreProvider).activeStoreId();
      final user = ref.read(authControllerProvider).valueOrNull?.user;
      await ref.read(adjustmentRepositoryProvider).recordAdjustment(
        target: target,
        operation: operation,
        amount: result['amount'] as double,
        reason: result['reason'] as String,
        storeId: storeId,
        userId: user?.id,
        notes: result['notes'] as String?,
      );
      ref.invalidate(_lifetimeSalesProvider);
      // ignore: unawaited_futures
      ref.read(syncServiceProvider).runOnce();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ $actionLabel ${MoneyFormatter.format(result['amount'] as double)} sou $targetLabel'),
          backgroundColor: color,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifetimeAsync = ref.watch(_lifetimeSalesProvider);
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Won 1: avatar + non/email
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            // Won 2: 3 statistik (Vant Nèt · Kredit · Brut) — +/- sou NÈT ak KREDIT
            lifetimeAsync.when(
              data: (t) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _statTile('VANT NÈT', t.net, primary,
                    onAdd: () => _openAdjustDialog(context, ref, target: 'net', operation: 'add'),
                    onSub: () => _openAdjustDialog(context, ref, target: 'net', operation: 'subtract'),
                  )),
                  Container(width: 1, height: 60, color: Colors.grey.shade300),
                  Expanded(child: _statTile('KREDIT', t.credit, Colors.orange.shade700,
                    onAdd: () => _openAdjustDialog(context, ref, target: 'credit', operation: 'add'),
                    onSub: () => _openAdjustDialog(context, ref, target: 'credit', operation: 'subtract'),
                  )),
                  Container(width: 1, height: 60, color: Colors.grey.shade300),
                  Expanded(child: _statTile('VANT BRUT', t.gross, Colors.green.shade700)),
                ],
              ),
              loading: () => const SizedBox(
                height: 30,
                child: Center(child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )),
              ),
              error: (_, __) => const SizedBox(
                height: 30,
                child: Center(child: Icon(Icons.error_outline, color: Colors.grey, size: 20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncBanner extends ConsumerWidget {
  const _SyncBanner({required this.progress});
  final SyncProgress progress;

  Future<void> _forceFullSync(BuildContext context, WidgetRef ref) async {
    // Konfimasyon
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cloud_sync, color: Colors.blue, size: 40),
        title: const Text('Fose Sync Konplè?'),
        content: const Text(
          'Sa ap:\n\n'
          '• Rale TOUT done ki sou sèvè an ankò\n'
          '• Retisi vant/pwodwi ki mankan lokal\n'
          '• Ka pran 30-60 sekonn\n\n'
          'Ale nan avan?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anile')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Fose Sync')),
        ],
      ),
    );
    if (ok != true) return;

    // Reset local cursor + trigger fresh pull
    try {
      final sync = ref.read(syncServiceProvider);
      await sync.forceFullPull();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sync konplè fèt — done rafrechi'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erè: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color, text) = switch (progress.status) {
      SyncStatus.idle => (Icons.cloud_done, Colors.green, 'Sync OK'),
      SyncStatus.pushing => (Icons.cloud_upload, Colors.blue, 'Voye chanjman…'),
      SyncStatus.pulling => (Icons.cloud_download, Colors.blue, 'Rale chanjman…'),
      SyncStatus.offline => (Icons.cloud_off, Colors.orange, 'Pa gen entènèt'),
      SyncStatus.error => (Icons.error_outline, Colors.red, 'Sync erè: ${progress.lastError ?? ""}'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
          if (progress.pendingOutbox > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: Text('${progress.pendingOutbox} ap tann'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          // Bouton "Fose Sync Konplè"
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Fose Sync Konplè',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
            onPressed: () => _forceFullSync(context, ref),
          ),
        ],
      ),
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid({required this.canManage, this.isDryCleaning = false});
  final bool canManage;
  final bool isDryCleaning;

  @override
  Widget build(BuildContext context) {
    final items = isDryCleaning
        ? <_MenuItem>[
            _MenuItem('Nouvo Lòd', Icons.add_box, '/dryclean/new', primary: true),
            _MenuItem('Lòd yo', Icons.local_laundry_service, '/dryclean'),
            _MenuItem('Sèvis', Icons.checkroom, '/products'),
            _MenuItem('Kliyan', Icons.people, '/customers'),
            _MenuItem('Kès', Icons.account_balance_wallet, '/cash-sessions'),
            if (canManage) _MenuItem('Rapò', Icons.bar_chart, '/dryclean/reports'),
            if (canManage) _MenuItem('Itilizatè', Icons.people_alt, '/users'),
            if (canManage) _MenuItem('Plan', Icons.workspace_premium, '/plans'),
            if (canManage) _MenuItem('APK Pa Mwen', Icons.android, '/my-apk'),
            _MenuItem('Paramèt', Icons.settings, '/settings'),
          ]
        : <_MenuItem>[
            _MenuItem('Nouvo Vant', Icons.point_of_sale, '/pos', primary: true),
            _MenuItem('Istwa Vant', Icons.receipt_long, '/sales'),
            _MenuItem('Pwodwi', Icons.inventory_2, '/products'),
            _MenuItem('Kliyan', Icons.people, '/customers'),
            _MenuItem('Kès', Icons.account_balance_wallet, '/cash-sessions'),
            if (canManage) _MenuItem('Founisè', Icons.local_shipping, '/suppliers'),
            if (canManage) _MenuItem('Acha', Icons.shopping_cart, '/purchases'),
            _MenuItem('Mouvman Stock', Icons.swap_vert, '/stock-movements'),
            if (canManage) _MenuItem('Rapò', Icons.bar_chart, '/reports'),
            if (canManage) _MenuItem('Itilizatè', Icons.people_alt, '/users'),
            if (canManage) _MenuItem('Plan', Icons.workspace_premium, '/plans'),
            if (canManage) _MenuItem('APK Pa Mwen', Icons.android, '/my-apk'),
            _MenuItem('Paramèt', Icons.settings, '/settings'),
          ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (context, i) {
        final it = items[i];
        return Card(
          color: it.primary ? Theme.of(context).colorScheme.primaryContainer : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push(it.route),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(it.icon, size: 40),
                  const SizedBox(height: 8),
                  Text(it.label, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuItem {
  final String label;
  final IconData icon;
  final String route;
  final bool primary;
  _MenuItem(this.label, this.icon, this.route, {this.primary = false});
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.tenant});
  final TenantInfo tenant;

  @override
  Widget build(BuildContext context) {
    final days = tenant.daysRemaining;
    final months = (days / 30).floor();
    final expiringSoon = tenant.isExpiringSoon;
    final color = tenant.isExpired
        ? Colors.red
        : expiringSoon
            ? Colors.orange
            : Colors.green;
    final bgColor = tenant.isExpired
        ? Colors.red.shade50
        : expiringSoon
            ? Colors.orange.shade50
            : Colors.green.shade50;

    return Card(
      color: bgColor,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(
                tenant.isExpired
                    ? Icons.warning
                    : expiringSoon
                        ? Icons.timer
                        : Icons.workspace_premium,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tenant.planLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tenant.isExpired
                        ? '⚠️ Plan ekspire — renouvle pou kontinye'
                        : '$days jou rete (~$months mwa)',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
            if (expiringSoon || tenant.isExpired)
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Kontakte sipò pou renouvle plan ou')),
                  );
                },
                child: Text(
                  'Renouvle',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Earnings card (admin sèlman)
// ============================================================

class HomeStats {
  final double todayRevenue;
  final int todayCount;
  final int lowStockCount;
  final int pendingSyncCount;

  HomeStats({
    required this.todayRevenue,
    required this.todayCount,
    required this.lowStockCount,
    required this.pendingSyncCount,
  });
}

final _homeStatsProvider = FutureProvider.autoDispose<HomeStats>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  final db = ref.watch(databaseProvider).requireValue;
  if (storeId == null) {
    return HomeStats(todayRevenue: 0, todayCount: 0, lowStockCount: 0, pendingSyncCount: 0);
  }
  final n = DateTime.now();
  final startOfDay = DateTime(n.year, n.month, n.day).toUtc().toIso8601String();
  final endOfDay = DateTime(n.year, n.month, n.day, 23, 59, 59).toUtc().toIso8601String();

  // Vant jodi a — kob KI REYÈLMAN antre nan kès (vant + peman dèt)
  final salesRow = await db.rawQuery('''
    SELECT
      COALESCE(SUM(amount_received), 0) AS revenue,
      COUNT(*) AS cnt
    FROM sales
    WHERE store_id = ?
      AND status IN ('completed', 'credit')
      AND deleted_at IS NULL
      AND created_at >= ?
      AND created_at <= ?
  ''', [storeId, startOfDay, endOfDay]);

  // Peman dèt jodi a — SÈL type='payment' (dèt manyèl PA konte kòm vant)
  final debtPaymentsRow = await db.rawQuery('''
    SELECT COALESCE(SUM(amount), 0) AS paid
    FROM customer_payments
    WHERE (store_id = ? OR store_id IS NULL)
      AND type = 'payment'
      AND created_at >= ?
      AND created_at <= ?
  ''', [storeId, startOfDay, endOfDay]);
  final debtPaidToday = (debtPaymentsRow.first['paid'] as num?)?.toDouble() ?? 0;
  final rawRevenue = (salesRow.first['revenue'] as num?)?.toDouble() ?? 0;
  final totalToday = rawRevenue + debtPaidToday;

  // Stock ba — SÈLMAN pwodwi magazen aktif la (oswa pataje ak store_id NULL).
  final lowStockRow = await db.rawQuery('''
    SELECT COUNT(*) AS cnt
    FROM products p
    JOIN product_stocks ps ON ps.product_id = p.id AND ps.store_id = ?
    WHERE p.is_active = 1 AND p.track_stock = 1
      AND (p.store_id = ? OR p.store_id IS NULL)
      AND ps.stock <= ps.low_stock_alert
  ''', [storeId, storeId]);

  // Sync ki tann
  final pendingRow = await db.rawQuery('SELECT COUNT(*) AS cnt FROM sync_outbox');

  return HomeStats(
    todayRevenue: totalToday,
    todayCount: ((salesRow.first['cnt'] as num?) ?? 0).toInt(),
    lowStockCount: ((lowStockRow.first['cnt'] as num?) ?? 0).toInt(),
    pendingSyncCount: ((pendingRow.first['cnt'] as num?) ?? 0).toInt(),
  );
});

class _EarningsCard extends ConsumerWidget {
  const _EarningsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_homeStatsProvider);
    return statsAsync.when(
      data: (s) => _buildCard(context, s),
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (e, _) => Card(
        color: Colors.red.shade50,
        child: ListTile(
          leading: const Icon(Icons.error, color: Colors.red),
          title: const Text('Pa kapab chaje rezime'),
          subtitle: Text(e.toString(), style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, HomeStats s) {
    final primary = Theme.of(context).colorScheme.primary;
    final hasAlerts = s.lowStockCount > 0 || s.pendingSyncCount > 0;

    return Card(
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/reports'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tit
              Row(
                children: [
                  Icon(Icons.trending_up, color: primary),
                  const SizedBox(width: 8),
                  Text(
                    'Vant Jodi a',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.bar_chart, size: 16),
                    label: const Text('Detay', style: TextStyle(fontSize: 12)),
                    onPressed: () => context.push('/reports'),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Total
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    MoneyFormatter.format(s.todayRevenue),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${s.todayCount} vant',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              // Alerts
              if (hasAlerts) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (s.lowStockCount > 0)
                      Expanded(
                        child: _AlertChip(
                          icon: Icons.warning_amber,
                          color: Colors.orange,
                          count: s.lowStockCount,
                          label: 'Stock ba',
                          onTap: () => context.push('/products'),
                        ),
                      ),
                    if (s.lowStockCount > 0 && s.pendingSyncCount > 0)
                      const SizedBox(width: 8),
                    if (s.pendingSyncCount > 0)
                      Expanded(
                        child: _AlertChip(
                          icon: Icons.cloud_upload,
                          color: Colors.blue,
                          count: s.pendingSyncCount,
                          label: 'Tann sync',
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertChip extends StatelessWidget {
  const _AlertChip({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final int count;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              count.toString(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 11, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
