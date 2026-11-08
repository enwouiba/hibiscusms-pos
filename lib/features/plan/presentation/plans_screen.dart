import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/utils/money_formatter.dart';
import '../data/plan_repository.dart';

final _plansProvider = FutureProvider.autoDispose<List<PlanPricing>>((ref) async {
  return ref.watch(planRepositoryProvider).listPlans();
});

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(_plansProvider);
    final auth = ref.watch(authControllerProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Plan ak Tarif')),
      body: plans.when(
        data: (list) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (auth?.tenant != null) ...[
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Plan Aktyèl Ou', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(auth!.tenant!.planLabel,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('${auth.tenant!.daysRemaining} jou rete'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text('Plan Disponib', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ...list.map((p) => _PlanCard(plan: p, isCurrent: p.code == auth?.tenant?.plan)),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan, required this.isCurrent});
  final PlanPricing plan;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFree = plan.price == 0;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: isCurrent ? 4 : 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(plan.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                if (isCurrent)
                  const Chip(
                    label: Text('Aktyèl', style: TextStyle(fontSize: 10)),
                    backgroundColor: Color(0xFFE3F2FD),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isFree
                  ? 'Gratis'
                  : plan.isLifetime
                      ? '${MoneyFormatter.format(plan.price, currency: plan.currency)} • Pou tout vi'
                      : '${MoneyFormatter.format(plan.price, currency: plan.currency)} / ${plan.durationMonths} mwa',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (plan.maxStores != null)
                  _Chip('🏪 ${plan.maxStores} magazen'),
                if (plan.maxUsers != null)
                  _Chip('👤 ${plan.maxUsers} itilizatè'),
                if (plan.maxProducts != null)
                  _Chip('📦 ${plan.maxProducts} pwodwi'),
                if (plan.maxStores == null && plan.maxUsers == null)
                  const _Chip('♾️ Ilimite'),
              ],
            ),
            if (!isFree) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _showRenewalDialog(context, ref, plan),
                  child: const Text('Soumèt Demann'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRenewalDialog(BuildContext context, WidgetRef ref, PlanPricing plan) async {
    String method = 'moncash';
    final refCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          title: Text('Soumèt: ${plan.label}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                plan.isLifetime
                    ? '${MoneyFormatter.format(plan.price, currency: plan.currency)} • Pou tout vi'
                    : '${MoneyFormatter.format(plan.price, currency: plan.currency)} pou ${plan.durationMonths} mwa',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(
                  labelText: 'Mwayen peman',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'moncash', child: Text('MonCash')),
                  DropdownMenuItem(value: 'natcash', child: Text('NatCash')),
                  DropdownMenuItem(value: 'bank_transfer', child: Text('Vire Bank')),
                  DropdownMenuItem(value: 'cash', child: Text('Kach')),
                ],
                onChanged: (v) => setSt(() => method = v ?? 'moncash'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                  labelText: 'Referans tranzaksyon',
                  hintText: 'Egz: ID MonCash, # vire',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anile')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Soumèt'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    try {
      await ref.read(planRepositoryProvider).requestRenewal(
            planCode: plan.code,
            paymentMethod: method,
            paymentReference: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Demann soumèt! System Owner ap apwouve l byento.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}
