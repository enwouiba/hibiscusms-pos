import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FilteringTextInputFormatter, TextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/hotel.dart';
import '../../business/data/store_repository.dart';
import '../../printing/data/invoice_pdf.dart';
import '../../printing/data/printer_service.dart';
import '../../printing/presentation/print_controller.dart';
import '../data/hotel_repository.dart';

final _stayProvider = FutureProvider.autoDispose.family<HotelStay?, String>((ref, id) async {
  return ref.watch(hotelRepositoryProvider).findStay(id);
});

class HotelStayDetailScreen extends ConsumerWidget {
  const HotelStayDetailScreen({super.key, required this.stayId});
  final String stayId;

  String _pick(String? v, String fb) => (v != null && v.trim().isNotEmpty) ? v.trim() : fb;

  static String _dt(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _addPayment(BuildContext context, WidgetRef ref, HotelStay s) async {
    final ctrl = TextEditingController(text: s.amountDue > 0 ? s.amountDue.toStringAsFixed(2) : '');
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
    await ref.read(hotelRepositoryProvider).addPayment(s.id, amt);
    ref.invalidate(_stayProvider(s.id));
  }

  Future<void> _checkout(BuildContext context, WidgetRef ref, HotelStay s) async {
    final durCtrl = TextEditingController(text: '${s.duration}');
    final extraCtrl = TextEditingController(text: s.extra > 0 ? s.extra.toStringAsFixed(2) : '');
    final discCtrl = TextEditingController(text: s.discount > 0 ? s.discount.toStringAsFixed(2) : '');
    final payCtrl = TextEditingController(text: s.amountDue > 0 ? s.amountDue.toStringAsFixed(2) : '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final dur = int.tryParse(durCtrl.text.trim()) ?? s.duration;
          final extra = double.tryParse(extraCtrl.text.trim()) ?? 0;
          final disc = double.tryParse(discCtrl.text.trim()) ?? 0;
          final total = (s.rate * dur + extra - disc).clamp(0, double.infinity).toDouble();
          final due = (total - s.amountPaid).clamp(0, double.infinity).toDouble();
          return AlertDialog(
            title: const Text('Check-out'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: durCtrl,
                  decoration: InputDecoration(labelText: 'Dire final (${s.mode.unit})', border: const OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(
                    controller: extraCtrl,
                    decoration: const InputDecoration(labelText: 'Chaj anplis', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                    onChanged: (_) => setLocal(() {}),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: discCtrl,
                    decoration: const InputDecoration(labelText: 'Rabè', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                    onChanged: (_) => setLocal(() {}),
                  )),
                ]),
                const SizedBox(height: 12),
                _dialogRow('Total', MoneyFormatter.format(total), bold: true),
                _dialogRow('Deja peye', MoneyFormatter.format(s.amountPaid)),
                _dialogRow('Rès pou peye', MoneyFormatter.format(due), color: due > 0 ? Colors.red : Colors.green),
                const SizedBox(height: 10),
                TextField(
                  controller: payCtrl,
                  decoration: const InputDecoration(labelText: 'Peman kounye a', border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anile')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Konfime check-out')),
            ],
          );
        },
      ),
    );

    final dur = int.tryParse(durCtrl.text.trim());
    final extra = double.tryParse(extraCtrl.text.trim());
    final disc = double.tryParse(discCtrl.text.trim());
    final pay = double.tryParse(payCtrl.text.trim()) ?? 0;
    durCtrl.dispose();
    extraCtrl.dispose();
    discCtrl.dispose();
    payCtrl.dispose();

    if (confirmed != true) return;
    final repo = ref.read(hotelRepositoryProvider);
    if (pay > 0) await repo.addPayment(s.id, pay);
    await repo.checkOut(s.id, finalDuration: dur, finalExtra: extra, finalDiscount: disc);
    ref.invalidate(_stayProvider(s.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-out fèt. Chanm nan nan netwayaj.')));
    }
  }

  Future<void> _validateProforma(BuildContext context, WidgetRef ref, HotelStay s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Valide pofoma'),
        content: const Text('Kliyan an aksepte? Pofoma a ap vin yon FAKTI ofisyèl.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wi, valide')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(hotelRepositoryProvider).validateProforma(s.id);
    ref.invalidate(_stayProvider(s.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pofoma valide → Fakti. Ou ka enprime fakti a kounye a.')),
      );
    }
  }

  Future<void> _printReceipt(BuildContext context, WidgetRef ref, HotelStay s) async {
    final prefs = await SharedPreferences.getInstance();
    final printerAddr = prefs.getString('printer_address');
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    final store = storeId != null ? await ref.read(storeRepositoryProvider).findById(storeId) : null;
    final logo = await rootBundle
        .load('assets/images/receipt_logo.png')
        .then((b) => b.buffer.asUint8List())
        .catchError((_) => Uint8List(0));

    // Woutaj otomatik: sejou NWIT -> fakti A4 (PDF) sou enprimant A4;
    // sejou MOMAN -> resi tèmik sou Epson (ESC/POS).
    if (s.mode == HotelRentalMode.nightly) {
      final pdfBytes = await InvoicePdf.build(InvoiceData(
        businessName: _pick(store?.name, AppConstants.receiptBusinessName),
        businessAddress: _pick(store?.address, AppConstants.receiptBusinessAddress),
        businessPhone: _pick(store?.phone, AppConstants.receiptBusinessPhone),
        businessNif: _pick(store?.nif, AppConstants.receiptBusinessNif),
        businessEmail: _pick(store?.email, AppConstants.receiptBusinessEmail),
        logoBytes: logo.isNotEmpty ? logo : null,
        number: s.stayNumber,
        createdAt: s.createdAt,
        checkOutAt: s.checkOutAt,
        guestName: s.guestName,
        guestPhone: s.guestPhone,
        guestIdDoc: s.guestIdDoc,
        roomName: s.roomNameSnapshot,
        modeLabel: s.mode.label,
        unitLabel: s.mode.unit,
        duration: s.duration,
        rate: s.rate,
        roomCharge: s.roomCharge,
        extra: s.extra,
        discount: s.discount,
        total: s.total,
        amountPaid: s.amountPaid,
        amountDue: s.amountDue,
        footerText: 'Mèsi pou vizit ou!',
        isProforma: !s.proformaValidated, // POFOMA toutan li poko valide
      ));
      final a4Name = prefs.getString('printer_a4_name');
      final ok = await PrinterService.instance.printPdfCups(pdfBytes, printerName: a4Name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Fakti A4 voye sou enprimant A4 la.'
            : 'Pa kapab enprime A4 — verifye CUPS / enprimant A4 nan Paramèt.'),
      ));
      return;
    }

    final data = ReceiptData(
      receiptWidth: 576, // 80mm — menm lajè ak Epson TM-T20II (kolòn aliyen, pi konpak)
      saleNumber: s.stayNumber,
      createdAt: s.createdAt,
      items: [
        ReceiptItem(
          name: '${s.roomNameSnapshot} · ${s.mode.unit}',
          quantity: s.duration.toDouble(),
          subtotal: s.roomCharge,
        ),
        if (s.extra > 0) ReceiptItem(name: 'Chaj anplis', quantity: 1, subtotal: s.extra),
      ],
      subtotal: s.roomCharge + s.extra,
      discount: s.discount,
      tax: 0,
      total: s.total,
      paymentMethodLabel: 'Kach',
      amountReceived: s.amountPaid,
      amountDue: s.amountDue,
      businessName: _pick(store?.name, AppConstants.receiptBusinessName),
      businessAddress: _pick(store?.address, AppConstants.receiptBusinessAddress),
      businessPhone: _pick(store?.phone, AppConstants.receiptBusinessPhone),
      businessNif: _pick(store?.nif, AppConstants.receiptBusinessNif),
      businessEmail: _pick(store?.email, AppConstants.receiptBusinessEmail),
      logoBytes: logo.isNotEmpty ? logo : null,
      ticketTitle: 'RESI OTÈL',
      numberLabel: 'Sejou',
      customerName: s.guestName,
      customerPhone: s.guestPhone,
      customerIdDoc: s.guestIdDoc,
      footerText: 'Mèsi pou vizit ou!',
    );

    final ok = await ref.read(printStateProvider.notifier).printReceipt(data, savedAddress: printerAddr);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Resi voye sou printer.' : 'Pa kapab enprime — verifye printer/Bluetooth.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_stayProvider(stayId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detay Sejou'),
        actions: [
          async.maybeWhen(
            data: (s) => s == null
                ? const SizedBox.shrink()
                : IconButton(icon: const Icon(Icons.print), tooltip: 'Enprime resi', onPressed: () => _printReceipt(context, ref, s)),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        data: (s) {
          if (s == null) return const Center(child: Text('Sejou pa jwenn.'));
          final active = s.status == HotelStayStatus.active;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Sejou #${s.stayNumber}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Chip(label: Text('${s.status.emoji} ${s.status.label}')),
                    ]),
                    Text('🚪 ${s.roomNameSnapshot}', style: const TextStyle(fontSize: 16)),
                    Text('${s.mode.emoji} ${s.mode.label} · ${s.duration} ${s.mode.unit}'),
                    if (s.mode == HotelRentalMode.nightly)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: s.proformaValidated
                            ? const Text('🧾 Fakti valide', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                            : const Text('📄 Pofoma (devi) — poko valide', style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                      ),
                    if (s.guestName?.isNotEmpty == true) Text('👤 ${s.guestName}'),
                    if (s.guestPhone?.isNotEmpty == true) Text('📞 ${s.guestPhone}'),
                    if (s.guestIdDoc?.isNotEmpty == true) Text('🪪 NIF/CIN: ${s.guestIdDoc}'),
                    Text('📥 Check-in: ${_dt(s.checkInAt)}'),
                    if (active) Text('⏳ Dwe fini: ${_dt(s.plannedEndAt)}'),
                    if (s.checkOutAt != null) Text('📤 Check-out: ${_dt(s.checkOutAt!)}'),
                    if (s.notes?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 4), child: Text('📝 ${s.notes}')),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _row('${MoneyFormatter.format(s.rate)} × ${s.duration} ${s.mode.unit}', MoneyFormatter.format(s.roomCharge)),
              if (s.extra > 0) _row('Chaj anplis', MoneyFormatter.format(s.extra)),
              if (s.discount > 0) _row('Rabè', '- ${MoneyFormatter.format(s.discount)}'),
              const Divider(),
              _row('TOTAL', MoneyFormatter.format(s.total), bold: true),
              _row('Peye', MoneyFormatter.format(s.amountPaid)),
              if (s.amountDue > 0) _row('Dèt pou peye', MoneyFormatter.format(s.amountDue), bold: true, color: Colors.red),
              const SizedBox(height: 20),
              if (active) ...[
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.logout),
                    label: const Text('Check-out & Peye'),
                    onPressed: () => _checkout(context, ref, s),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.payments), label: const Text('Ajoute peman'), onPressed: () => _addPayment(context, ref, s))),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.print), label: const Text('Enprime resi'), onPressed: () => _printReceipt(context, ref, s))),
                ]),
              ] else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(icon: const Icon(Icons.print), label: const Text('Enprime resi'), onPressed: () => _printReceipt(context, ref, s)),
                ),
              // Pofoma → Fakti (sejou nwit sèlman)
              if (s.mode == HotelRentalMode.nightly && !s.proformaValidated) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.verified),
                    label: const Text('Valide pofoma → Fakti'),
                    onPressed: () => _validateProforma(context, ref, s),
                  ),
                ),
              ],
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

  static Widget _dialogRow(String l, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
        ]),
      );
}
