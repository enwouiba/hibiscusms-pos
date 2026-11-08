import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/sale.dart';
import '../../../core/sync/sync_service.dart';
import '../../customers/data/customer_repository.dart';
import '../data/sale_repository.dart';
import 'cart_controller.dart';

class CheckoutSheet extends ConsumerStatefulWidget {
  const CheckoutSheet({super.key});

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  PaymentMethod _method = PaymentMethod.cash;
  final _receivedCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _custNameCtrl = TextEditingController();
  final _custPhoneCtrl = TextEditingController();
  bool _saving = false;
  bool _allowDebt = false;
  List<Customer> _customerMatches = const [];

  @override
  void initState() {
    super.initState();
    // Pre-fill from cart if user already picked a customer earlier (in pos_screen)
    final cart = ref.read(cartProvider);
    if (cart.customerName != null) _custNameCtrl.text = cart.customerName!;
    if (cart.customerPhone != null) _custPhoneCtrl.text = cart.customerPhone!;
  }

  @override
  void dispose() {
    _receivedCtrl.dispose();
    _discountCtrl.dispose();
    _custNameCtrl.dispose();
    _custPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchCustomers(String q) async {
    if (q.trim().length < 2) {
      setState(() => _customerMatches = const []);
      return;
    }
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    if (storeId == null) return;
    final list = await ref.read(customerRepositoryProvider).list(storeId, search: q);
    if (mounted) setState(() => _customerMatches = list.take(5).toList());
  }

  void _pickExisting(Customer c) {
    _custNameCtrl.text = c.name;
    _custPhoneCtrl.text = c.phone ?? '';
    ref.read(cartProvider.notifier).setCustomer(id: c.id, name: c.name, phone: c.phone, balance: c.balance);
    setState(() => _customerMatches = const []);
  }

  Future<void> _confirm() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    final session = ref.read(authControllerProvider).valueOrNull;
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    if (session == null || storeId == null) return;

    final received = _method == PaymentMethod.cash
        ? double.tryParse(_receivedCtrl.text.replaceAll(',', '')) ?? cart.grandTotal
        : cart.grandTotal;

    final hasShortfall = received < cart.grandTotal;
    final typedName = _custNameCtrl.text.trim();

    if (hasShortfall && !_allowDebt) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kantite resi pa ase. Aktive "Kite det" si kliyan ap peye rès la pita.')),
      );
      return;
    }
    if (hasShortfall && _allowDebt && typedName.isEmpty && cart.customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yon kliyan oblijatwa pou kreye yon det.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final sale = await ref.read(saleRepositoryProvider).createSale(
            storeId: storeId,
            userId: session.user.id,
            cashierName: session.user.name,
            cart: cart.items,
            paymentMethod: _method,
            amountReceived: received,
            customerId: cart.customerId,
            customerName: typedName.isNotEmpty ? typedName : cart.customerName,
            customerPhone: _custPhoneCtrl.text.trim().isEmpty ? null : _custPhoneCtrl.text.trim(),
            extraDiscount: cart.extraDiscount,
            allowDebt: _allowDebt,
          );
      ref.read(cartProvider.notifier).clear();
      // Deklanche sync imedyatman pou voye vant lan sou sèvè
      // (fire-and-forget — pa bloke UI)
      // ignore: unawaited_futures
      ref.read(syncServiceProvider).runOnce();
      if (mounted) {
        Navigator.of(context).pop();
        context.go('/sales/${sale.id}');
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
    final cart = ref.watch(cartProvider);
    final received = double.tryParse(_receivedCtrl.text.replaceAll(',', '')) ?? 0;
    final change = received - cart.grandTotal;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL', style: TextStyle(fontSize: 18)),
                Text(
                  MoneyFormatter.format(cart.grandTotal),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Mwayen Peman'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: PaymentMethod.values.map((m) {
                final selected = _method == m;
                return ChoiceChip(
                  label: Text(m.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _method = m),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ─── Customer (optional, but required if "Allow debt" is on) ───
            const Text('Kliyan (opsyonèl)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(
              controller: _custNameCtrl,
              decoration: InputDecoration(
                labelText: 'Non kliyan',
                hintText: 'Tape oswa chwazi…',
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(Icons.person_outline),
                suffixIcon: cart.customerId != null
                    ? Tooltip(
                        message: 'Kliyan anrejistre' + (cart.customerBalance > 0 ? ' · det: ${MoneyFormatter.format(cart.customerBalance)}' : ''),
                        child: const Icon(Icons.verified, color: Colors.green),
                      )
                    : (cart.customerName != null ? const Icon(Icons.person_add_alt, color: Colors.orange) : null),
              ),
              onChanged: (v) {
                // Reset selected customer when the name is edited
                if (cart.customerId != null) ref.read(cartProvider.notifier).setCustomer(id: null);
                ref.read(cartProvider.notifier).setNewCustomerName(v, phone: _custPhoneCtrl.text);
                _searchCustomers(v);
              },
            ),
            if (_customerMatches.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: _customerMatches.map((c) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.person, size: 18),
                    title: Text(c.name, style: const TextStyle(fontSize: 13)),
                    subtitle: c.phone != null ? Text(c.phone!, style: const TextStyle(fontSize: 11)) : null,
                    trailing: c.balance > 0
                        ? Text('Det: ${MoneyFormatter.format(c.balance)}',
                            style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600))
                        : null,
                    onTap: () => _pickExisting(c),
                  )).toList(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _custPhoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Telefòn (opsyonèl)',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
            ),

            const SizedBox(height: 16),
            if (_method == PaymentMethod.cash) ...[
              TextField(
                controller: _receivedCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kantite Resi',
                  border: OutlineInputBorder(),
                  suffixText: 'HTG',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(change < 0 ? 'Det' : 'Monnen', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    change > 0
                        ? MoneyFormatter.format(change)
                        : change < 0
                            ? MoneyFormatter.format(-change)
                            : '— —',
                    style: TextStyle(
                      color: change > 0 ? Colors.green : change < 0 ? Colors.red : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (change < 0) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Kite rès la kòm det', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Ajoute ${MoneyFormatter.format(-change)} sou balans kliyan an',
                      style: const TextStyle(fontSize: 11)),
                  value: _allowDebt,
                  onChanged: (v) => setState(() => _allowDebt = v),
                ),
              ],
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Ap sove…' : 'KONFIME'),
                onPressed: _saving ? null : _confirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
