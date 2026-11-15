import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/hotel.dart';
import '../../business/data/store_repository.dart';
import '../../printing/data/invoice_pdf.dart';
import '../../printing/data/printer_service.dart';
import '../data/hotel_repository.dart';
import 'hotel_proforma_list_screen.dart';

final _proformaProvider =
    FutureProvider.autoDispose.family<HotelProforma?, String>((ref, id) async {
  return ref.watch(hotelRepositoryProvider).findProforma(id);
});

/// Detay yon POFOMA ki sove: re-enprime (A4), valide → FAKTI, oswa efase.
class HotelProformaDetailScreen extends ConsumerStatefulWidget {
  const HotelProformaDetailScreen({super.key, required this.proformaId, this.autoPrint = false});
  final String proformaId;
  final bool autoPrint;

  @override
  ConsumerState<HotelProformaDetailScreen> createState() => _State();
}

class _State extends ConsumerState<HotelProformaDetailScreen> {
  bool _busy = false;
  bool _autoPrinted = false;

  Future<void> _print(HotelProforma p) async {
    setState(() => _busy = true);
    try {
      final storeId = await ref.read(tokenStoreProvider).activeStoreId();
      final store = storeId != null ? await ref.read(storeRepositoryProvider).findById(storeId) : null;
      final logo = await rootBundle
          .load('assets/images/receipt_logo.png')
          .then((b) => b.buffer.asUint8List())
          .catchError((_) => Uint8List(0));

      final pdfBytes = await InvoicePdf.build(InvoiceData(
        businessName: _pick(store?.name, AppConstants.receiptBusinessName),
        businessAddress: _pick(store?.address, AppConstants.receiptBusinessAddress),
        businessPhone: _pick(store?.phone, AppConstants.receiptBusinessPhone),
        businessNif: _pick(store?.nif, AppConstants.receiptBusinessNif),
        businessEmail: _pick(store?.email, AppConstants.receiptBusinessEmail),
        logoBytes: logo.isNotEmpty ? logo : null,
        number: p.number,
        createdAt: p.createdAt,
        guestName: p.guestName,
        guestPhone: p.guestPhone,
        guestIdDoc: p.guestIdDoc,
        guestEmail: p.guestEmail,
        lines: [
          for (final it in p.items)
            InvoiceLine(
              description: it.mode == HotelRentalMode.hourly
                  ? 'Chanm ${it.roomName} (Moman ${it.duration}h)'
                  : 'Chanm ${it.roomName} (${it.mode.label})',
              qty: (hotelBillableUnits(it.mode, it.duration)).round(),
              unitLabel: it.mode == HotelRentalMode.hourly ? 'moman' : it.mode.unit,
              rate: it.rate,
              total: it.lineTotal,
            ),
        ],
        extra: p.extra,
        discount: p.discount,
        total: p.total,
        footerText: p.validated ? 'Fakti valide. Mèsi!' : 'Devi — valab 7 jou. Mèsi!',
        isProforma: !p.validated,
      ));
      final prefs = await SharedPreferences.getInstance();
      final a4Name = prefs.getString('printer_a4_name');
      final ok = await PrinterService.instance.printPdfSmart(
          pdfBytes, printerName: a4Name, jobName: p.validated ? 'Fakti' : 'Pofoma');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'A4 enprime.' : 'Pa kapab enprime — chwazi enprimant A4 nan Paramèt.'),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  Future<void> _validate(HotelProforma p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Valide pofoma?'),
        content: const Text('Si kliyan aksepte, pofoma a ap vin yon FAKTI ofisyèl. Ou p ap ka chanje l apre.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anile')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valide → Fakti')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await ref.read(hotelRepositoryProvider).markProformaValidated(p.id);
    ref.invalidate(_proformaProvider(p.id));
    ref.invalidate(hotelProformasProvider);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _delete(HotelProforma p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Efase pofoma?'),
        content: Text('Efase ${p.validated ? "FAKTI" : "POFOMA"} #${p.number}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anile')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Efase'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(hotelRepositoryProvider).deleteProforma(p.id);
    ref.invalidate(hotelProformasProvider);
    if (mounted) context.pop();
  }

  String _pick(String? v, String fb) => (v != null && v.trim().isNotEmpty) ? v.trim() : fb;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_proformaProvider(widget.proformaId));
    // Sekretè a (kesye) pa ka efase ni valide — sèlman enprime. Jesyonè >= 2.
    final canManage = (ref.watch(authControllerProvider).valueOrNull?.highestLevel(null) ?? 0) >= 2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detay Pofoma'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => async.whenData((p) { if (p != null) _delete(p); }),
            ),
        ],
      ),
      body: async.when(
        data: (p) {
          if (p == null) return const Center(child: Text('Pa jwenn pofoma a.'));
          // Auto-enprime yon fwa apre sove (?print=1)
          if (widget.autoPrint && !_autoPrinted) {
            _autoPrinted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _print(p); });
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: p.validated ? Colors.teal.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(p.validated ? 'FAKTI #${p.number}' : 'POFOMA #${p.number}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: p.validated ? Colors.teal.shade900 : Colors.orange.shade900)),
                ),
              ]),
              const SizedBox(height: 14),
              Text('Kliyan', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if ((p.guestName ?? '').isNotEmpty) Text('Non: ${p.guestName}'),
              if ((p.guestPhone ?? '').isNotEmpty) Text('Telefòn: ${p.guestPhone}'),
              if ((p.guestIdDoc ?? '').isNotEmpty) Text('NIF/CIN: ${p.guestIdDoc}'),
              if ((p.guestEmail ?? '').isNotEmpty) Text('Imel: ${p.guestEmail}'),
              const Divider(height: 24),
              Text('Chanm (${p.roomCount})', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              for (final it in p.items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Text(it.mode.emoji, style: const TextStyle(fontSize: 18)),
                  title: Text('Chanm ${it.roomName}'),
                  subtitle: Text('${hotelQtyLabel(it.mode, it.duration)} × ${MoneyFormatter.format(it.rate)}'),
                  trailing: Text(MoneyFormatter.format(it.lineTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              const Divider(height: 24),
              _kv('Soustotal', MoneyFormatter.format(p.itemsTotal + p.extra)),
              if (p.extra > 0) _kv('— ladan chaj anplis', MoneyFormatter.format(p.extra)),
              if (p.discount > 0) _kv('Rabè', '- ${MoneyFormatter.format(p.discount)}'),
              const SizedBox(height: 4),
              _kv('TOTAL', MoneyFormatter.format(p.total), bold: true),
              const SizedBox(height: 20),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  icon: const Icon(Icons.print),
                  label: Text(_busy ? 'Ap enprime…' : (p.validated ? 'Re-enprime Fakti (A4)' : 'Enprime Pofoma (A4)')),
                  onPressed: _busy ? null : () => _print(p),
                ),
              ),
              const SizedBox(height: 10),
              if (!p.validated)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.verified),
                    label: const Text('Kliyan aksepte → Valide (Fakti)'),
                    onPressed: _busy ? null : () => _validate(p),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 17 : 14)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: bold ? 17 : 14)),
        ]),
      );
}
