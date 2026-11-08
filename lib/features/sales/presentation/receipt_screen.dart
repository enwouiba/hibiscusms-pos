import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/sale.dart';
import '../../business/data/store_repository.dart';
import '../../printing/presentation/print_controller.dart';
import '../data/sale_repository.dart';

final _saleProvider = FutureProvider.family.autoDispose<Sale?, String>((ref, id) {
  return ref.watch(saleRepositoryProvider).findById(id);
});

class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({super.key, required this.saleId});
  final String saleId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Sale sale) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Efase Vant Sa?'),
        content: Text(
          'Resi #${sale.saleNumber} — ${MoneyFormatter.format(sale.total)}\n\n'
          'Stock pwodwi yo ap retounen otomatik. Aksyon pa reveni.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anile')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Efase'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(saleRepositoryProvider).deleteSale(sale.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vant efase. Stock retounen.')),
        );
        context.pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  Future<void> _print(BuildContext context, WidgetRef ref, Sale sale) async {
    final prefs = await SharedPreferences.getInstance();
    final printerAddr = prefs.getString('printer_address');
    final auth = ref.read(authControllerProvider).valueOrNull;

    // Chaje detay magazen soti nan SQLite lokal (gen adrès, telefòn, settings)
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    final localStore = storeId != null
        ? await ref.read(storeRepositoryProvider).findById(storeId)
        : null;

    // Chaje logo a soti nan assets
    final logoBytes = await rootBundle
        .load('assets/images/receipt_logo.png')
        .then((b) => b.buffer.asUint8List())
        .catchError((_) => Uint8List(0));

    final data = ReceiptData(
      saleNumber: sale.saleNumber,
      createdAt: sale.createdAt,
      items: sale.items.map((i) => ReceiptItem(
            name: i.nameSnapshot,
            quantity: i.quantity,
            subtotal: i.subtotal,
          )).toList(),
      subtotal: sale.subtotal,
      discount: sale.discount,
      tax: sale.tax,
      total: sale.total,
      paymentMethodLabel: sale.primaryPaymentMethod.label,
      amountReceived: sale.amountReceived,
      changeDue: sale.changeDue,
      amountDue: sale.amountDue,
      businessName: AppConstants.receiptBusinessName,
      businessAddress: AppConstants.receiptBusinessAddress,
      businessPhone: AppConstants.receiptBusinessPhone,
      businessNif: AppConstants.receiptBusinessNif,
      businessEmail: AppConstants.receiptBusinessEmail,
      logoBytes: logoBytes.isNotEmpty ? logoBytes : null,
      footerText: localStore?.footerText ?? 'Mèsi paske w achte lakay nou!',
      customerName: sale.customerName,
      cashierName: sale.cashierName ?? auth?.user.name,
    );

    final ok = await ref.read(printStateProvider.notifier).printReceipt(
          data,
          savedAddress: printerAddr,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Resi voye sou printer.' : 'Pa kapab enprime — verifye Bluetooth.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saleAsync = ref.watch(_saleProvider(saleId));
    final storeAsync = ref.watch(_localStoreProvider);
    final auth = ref.watch(authControllerProvider).valueOrNull;

    final canDelete = auth != null && auth.highestLevel(null) >= 2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resi'),
        actions: [
          saleAsync.maybeWhen(
            data: (sale) {
              if (sale == null) return const SizedBox.shrink();
              return Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.print),
                  tooltip: 'Enprime',
                  onPressed: () => _print(context, ref, sale),
                ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Efase vant',
                    onPressed: () => _delete(context, ref, sale),
                  ),
              ]);
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: saleAsync.when(
        data: (sale) {
          if (sale == null) return const Center(child: Text('Vant pa jwenn.'));
          final store = storeAsync.valueOrNull;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Logo
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Non Biznis
                      Text(
                        AppConstants.receiptBusinessName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      // Adrès
                      Text(
                        AppConstants.receiptBusinessAddress,
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),

                      // NIF
                      Text(
                        'NIF: ${AppConstants.receiptBusinessNif}',
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),

                      // Telefòn
                      Text(
                        'Tel: ${AppConstants.receiptBusinessPhone}',
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),

                      // Email
                      Text(
                        AppConstants.receiptBusinessEmail,
                        style: const TextStyle(fontSize: 12),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 12),
                      const Divider(),

                      // Numéwo resi + dat
                      Text('Resi #${sale.saleNumber}',
                          style: Theme.of(context).textTheme.headlineSmall),
                      Text(DateFormatter.full(sale.createdAt)),
                      const SizedBox(height: 8),

                      // Kèsye
                      if (sale.cashierName != null)
                        Text('Sekretè: ${sale.cashierName}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),

                      // Kliyan
                      if (sale.customerName != null)
                        Text('Kliyan: ${sale.customerName}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),

                      const Divider(),

                      // Atik yo
                      ...sale.items.map((i) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(i.nameSnapshot),
                            subtitle: Text('${i.quantity.toStringAsFixed(0)} × ${MoneyFormatter.format(i.priceSnapshot)}'),
                            trailing: Text(MoneyFormatter.format(i.subtotal)),
                          )),

                      const Divider(),
                      _Row('Soustotal', sale.subtotal),
                      if (sale.discount > 0) _Row('Rabè', -sale.discount),
                      if (sale.tax > 0) _Row('TCA', sale.tax),
                      const Divider(),
                      _Row('TOTAL', sale.total, bold: true),
                      const SizedBox(height: 8),

                      Text('Peman: ${sale.primaryPaymentMethod.label}'),
                      if (sale.amountReceived != null)
                        Text('Resi: ${MoneyFormatter.format(sale.amountReceived!)}'),
                      if (sale.changeDue != null && sale.changeDue! > 0)
                        Text('Monnen: ${MoneyFormatter.format(sale.changeDue!)}'),
                      if (sale.amountDue > 0) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('DET POU PEYE',
                                style: TextStyle(fontWeight: FontWeight.w900, color: Colors.red)),
                              Text(MoneyFormatter.format(sale.amountDue),
                                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.red, fontSize: 16)),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      const Divider(),

                      // Mo Remèsiman
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Text(
                          store?.footerText ?? 'Mèsi paske w achte lakay nou!',
                          style: const TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
      // Bar aksyon anba: Fini san enprime + Enprime
      bottomNavigationBar: saleAsync.maybeWhen(
        data: (sale) {
          if (sale == null) return const SizedBox.shrink();
          return SafeArea(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Fè bak — retounen nan POS screen
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/');
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Fini — Nouvo Vant'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _print(context, ref, sale),
                    icon: const Icon(Icons.print),
                    label: const Text('Enprime Resi'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }
}

final _localStoreProvider = FutureProvider.autoDispose((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return null;
  return ref.watch(storeRepositoryProvider).findById(storeId);
});

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});
  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : null,
      fontSize: bold ? 18 : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(MoneyFormatter.format(value), style: style)],
      ),
    );
  }
}
