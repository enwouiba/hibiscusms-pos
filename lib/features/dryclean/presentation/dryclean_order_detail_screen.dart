import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FilteringTextInputFormatter, TextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/dryclean_order.dart';
import '../../business/data/store_repository.dart';
import '../../printing/data/printer_service.dart';
import '../../printing/presentation/print_controller.dart';
import '../data/dryclean_repository.dart';

final _orderProvider = FutureProvider.autoDispose.family<DrycleanOrder?, String>((ref, id) async {
  return ref.watch(drycleanRepositoryProvider).findById(id);
});

class DrycleanOrderDetailScreen extends ConsumerWidget {
  const DrycleanOrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  String _pick(String? v, String fb) => (v != null && v.trim().isNotEmpty) ? v.trim() : fb;

  Future<void> _printTicket(BuildContext context, WidgetRef ref, DrycleanOrder o) async {
    final prefs = await SharedPreferences.getInstance();
    final printerAddr = prefs.getString('printer_address');
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    final store = storeId != null ? await ref.read(storeRepositoryProvider).findById(storeId) : null;
    final logo = await rootBundle
        .load('assets/images/receipt_logo.png')
        .then((b) => b.buffer.asUint8List())
        .catchError((_) => Uint8List(0));

    final data = ReceiptData(
      saleNumber: o.orderNumber,
      createdAt: o.createdAt,
      items: o.items
          .map((i) => ReceiptItem(
                name: i.tagNumber != null ? '${i.nameSnapshot} [${i.tagNumber}]' : i.nameSnapshot,
                quantity: i.quantity,
                subtotal: i.lineTotal,
              ))
          .toList(),
      subtotal: o.subtotal,
      discount: o.discount,
      tax: 0,
      total: o.total,
      paymentMethodLabel: 'Kach',
      amountReceived: o.amountPaid,
      amountDue: o.amountDue,
      businessName: _pick(store?.name, AppConstants.receiptBusinessName),
      businessAddress: _pick(store?.address, AppConstants.receiptBusinessAddress),
      businessPhone: _pick(store?.phone, AppConstants.receiptBusinessPhone),
      businessNif: _pick(store?.nif, AppConstants.receiptBusinessNif),
      businessEmail: _pick(store?.email, AppConstants.receiptBusinessEmail),
      logoBytes: logo.isNotEmpty ? logo : null,
      ticketTitle: 'TIKE REKLAMASYON',
      numberLabel: 'Lod',
      readyDate: o.readyDate,
      customerName: o.customerName,
      footerText: 'Kenbe tike sa a pou ranmase rad ou.',
    );

    final ok = await ref.read(printStateProvider.notifier).printReceipt(data, savedAddress: printerAddr);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Tikè voye sou printer.' : 'Pa kapab enprime — verifye printer/Bluetooth.')),
    );
  }

  Future<void> _addPayment(BuildContext context, WidgetRef ref, DrycleanOrder o) async {
    final ctrl = TextEditingController(text: o.amountDue > 0 ? o.amountDue.toStringAsFixed(2) : '');
    final amt = await showDialog<double?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajoute peman'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Mòn', border: OutlineInputBorder()),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anile')),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.trim())), child: const Text('Ajoute')),
        ],
      ),
    );
    ctrl.dispose();
    if (amt == null || amt <= 0) return;
    await ref.read(drycleanRepositoryProvider).addPayment(o.id, amt);
    ref.invalidate(_orderProvider(o.id));
  }

  Future<String?> _askRack(BuildContext context, String? current) async {
    final ctrl = TextEditingController(text: current ?? '');
    final r = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kote / Rack'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nimewo rack / kote rad yo', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Sote')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    return r;
  }

  Future<void> _advance(BuildContext context, WidgetRef ref, DrycleanOrder o) async {
    final next = o.status.next;
    if (next == null) return;
    String? rack;
    if (next == DrycleanStatus.ready) {
      rack = await _askRack(context, o.rackLocation);
    }
    await ref.read(drycleanRepositoryProvider).updateStatus(o.id, next, rackLocation: rack);
    ref.invalidate(_orderProvider(o.id));
    // Lè lòd la vin PARE, pwopoze avize kliyan an otomatikman.
    if (next == DrycleanStatus.ready && context.mounted && (o.customerPhone?.trim().isNotEmpty ?? false)) {
      await _notify(context, DrycleanOrder.fromMap({
        'id': o.id, 'store_id': o.storeId, 'order_number': o.orderNumber, 'status': 'ready',
        'customer_name': o.customerName, 'customer_phone': o.customerPhone,
        'subtotal': o.subtotal, 'total': o.total, 'amount_paid': o.amountPaid,
        'created_at': o.createdAt.toIso8601String(),
      }));
    }
  }

  String _digits(String p) {
    var d = p.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 8) d = '509$d'; // Ayiti
    return d;
  }

  Future<void> _notify(BuildContext context, DrycleanOrder o) async {
    final phone = o.customerPhone?.trim();
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pa gen telefòn pou kliyan an.')));
      return;
    }
    final greet = o.customerName != null && o.customerName!.isNotEmpty ? ' ${o.customerName}' : '';
    final msg = o.status == DrycleanStatus.ready
        ? 'Bonjou$greet, lòd #${o.orderNumber} ou an PARE. Ou ka vin ranmase l. Mèsi!'
        : 'Bonjou$greet, nou resevwa lòd #${o.orderNumber} ou an. Mèsi!';
    final d = _digits(phone);
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.chat, color: Colors.green),
            title: const Text('WhatsApp'),
            onTap: () { Navigator.pop(ctx); _open('https://wa.me/$d?text=${Uri.encodeComponent(msg)}'); },
          ),
          ListTile(
            leading: const Icon(Icons.sms, color: Colors.blue),
            title: const Text('SMS'),
            onTap: () { Navigator.pop(ctx); _open('sms:$phone?body=${Uri.encodeComponent(msg)}'); },
          ),
        ]),
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_orderProvider(orderId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detay Lòd'),
        actions: [
          async.maybeWhen(
            data: (o) => o == null
                ? const SizedBox.shrink()
                : IconButton(icon: const Icon(Icons.print), tooltip: 'Enprime tikè', onPressed: () => _printTicket(context, ref, o)),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        data: (o) {
          if (o == null) return const Center(child: Text('Lòd pa jwenn.'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Lòd #${o.orderNumber}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Chip(label: Text('${o.status.emoji} ${o.status.label}')),
                    ]),
                    if (o.customerName?.isNotEmpty == true) Text('👤 ${o.customerName}'),
                    if (o.customerPhone?.isNotEmpty == true) Text('📞 ${o.customerPhone}'),
                    if (o.readyDate != null) Text('📅 Pare: ${_d(o.readyDate!)}'),
                    if (o.rackLocation?.isNotEmpty == true) Text('📍 Rack: ${o.rackLocation}'),
                    if (o.notes?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 4), child: Text('📝 ${o.notes}')),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Rad / Sèvis', style: TextStyle(fontWeight: FontWeight.bold)),
              ...o.items.map((i) => ListTile(
                    dense: true,
                    title: Text('${i.quantity.toStringAsFixed(i.quantity == i.quantity.roundToDouble() ? 0 : 2)} × ${i.nameSnapshot}'),
                    subtitle: Text([
                      if (i.tagNumber != null) 'Etikèt: ${i.tagNumber}',
                      if (i.conditionNotes != null) i.conditionNotes!,
                    ].join(' • ')),
                    trailing: Text(MoneyFormatter.format(i.lineTotal)),
                  )),
              const Divider(),
              _row('Soustotal', MoneyFormatter.format(o.subtotal)),
              if (o.discount > 0) _row('Rabè', '- ${MoneyFormatter.format(o.discount)}'),
              _row('TOTAL', MoneyFormatter.format(o.total), bold: true),
              _row('Peye', MoneyFormatter.format(o.amountPaid)),
              if (o.amountDue > 0) _row('Dèt pou peye', MoneyFormatter.format(o.amountDue), bold: true, color: Colors.red),
              const SizedBox(height: 20),
              if (o.status.next != null)
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.arrow_forward),
                    label: Text('Pase nan: ${o.status.next!.emoji} ${o.status.next!.label}'),
                    onPressed: () => _advance(context, ref, o),
                  ),
                ),
              const SizedBox(height: 10),
              if (o.customerPhone?.trim().isNotEmpty ?? false)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_active, color: Colors.green),
                    label: const Text('Avize kliyan (WhatsApp / SMS)'),
                    onPressed: () => _notify(context, o),
                  ),
                ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.payments), label: const Text('Ajoute peman'), onPressed: () => _addPayment(context, ref, o))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.print), label: const Text('Enprime tikè'), onPressed: () => _printTicket(context, ref, o))),
              ]),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
        ]),
      );

  static String _d(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
