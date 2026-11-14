import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

final _roomsProvider = FutureProvider.autoDispose<List<HotelRoom>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  return ref.watch(hotelRepositoryProvider).listRooms(storeId);
});

/// Ekran POFOMA (devi): fè yon kòt pou yon kliyan AVAN check-in. Li enprime
/// yon pofoma A4, san okipe chanm nan. Si kliyan aksepte → fè check-in nòmal.
class HotelProformaScreen extends ConsumerStatefulWidget {
  const HotelProformaScreen({super.key});

  @override
  ConsumerState<HotelProformaScreen> createState() => _HotelProformaScreenState();
}

class _HotelProformaScreenState extends ConsumerState<HotelProformaScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _extraCtrl = TextEditingController();

  HotelRoom? _room;
  HotelRentalMode _mode = HotelRentalMode.nightly;
  int _duration = 1;
  bool _printing = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _idCtrl, _extraCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _rate =>
      _mode == HotelRentalMode.hourly ? (_room?.pricePerHour ?? 0) : (_room?.pricePerNight ?? 0);
  double get _extra => double.tryParse(_extraCtrl.text.trim()) ?? 0;
  double get _total => (_rate * _duration + _extra).clamp(0, double.infinity).toDouble();

  Future<void> _print() async {
    final room = _room;
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chwazi yon chanm')));
      return;
    }
    setState(() => _printing = true);
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
        number: 0,
        createdAt: DateTime.now(),
        guestName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        guestPhone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        guestIdDoc: _idCtrl.text.trim().isEmpty ? null : _idCtrl.text.trim(),
        roomName: room.name,
        modeLabel: _mode.label,
        unitLabel: _mode.unit,
        duration: _duration,
        rate: _rate,
        roomCharge: _rate * _duration,
        extra: _extra,
        total: _total,
        footerText: 'Devi — valab 7 jou. Mèsi!',
        isProforma: true,
      ));
      final prefs = await SharedPreferences.getInstance();
      final a4Name = prefs.getString('printer_a4_name');
      final ok = isWindowsDesktop
          ? await PrinterService.instance.printPdfViaPrinting(pdfBytes, printerName: a4Name)
          : await PrinterService.instance.printPdfCups(pdfBytes, printerName: a4Name);
      if (!mounted) return;
      setState(() => _printing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Pofoma A4 enprime.' : 'Pa kapab enprime — verifye enprimant A4 nan Paramèt.'),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _printing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  String _pick(String? v, String fb) => (v != null && v.trim().isNotEmpty) ? v.trim() : fb;

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(_roomsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pofoma (Devi)')),
      body: rooms.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Poko gen chanm. Ajoute chanm dabò.'));
          }
          _room ??= list.first;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Fè yon kòt pou yon kliyan anvan check-in. Li pa okipe chanm nan.',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 14),
              DropdownButtonFormField<HotelRoom>(
                initialValue: _room,
                decoration: const InputDecoration(labelText: 'Chanm', border: OutlineInputBorder(), prefixIcon: Icon(Icons.hotel)),
                items: [
                  for (final r in list)
                    DropdownMenuItem(value: r, child: Text(r.name)),
                ],
                onChanged: (r) => setState(() => _room = r),
              ),
              const SizedBox(height: 12),
              SegmentedButton<HotelRentalMode>(
                segments: const [
                  ButtonSegment(value: HotelRentalMode.nightly, label: Text('🌙 Pa nwit')),
                  ButtonSegment(value: HotelRentalMode.hourly, label: Text('⏱️ Pa èdtan')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() { _mode = s.first; _duration = 1; }),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Text('Dire: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton.filledTonal(icon: const Icon(Icons.remove), onPressed: _duration > 1 ? () => setState(() => _duration--) : null),
                Expanded(child: Text('$_duration ${_mode.unit}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton.filledTonal(icon: const Icon(Icons.add), onPressed: () => setState(() => _duration++)),
              ]),
              const SizedBox(height: 10),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Non kliyan', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 10),
              TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Telefòn', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              TextField(controller: _idCtrl, decoration: const InputDecoration(labelText: 'NIF / CIN', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge))),
              const SizedBox(height: 10),
              TextField(
                controller: _extraCtrl,
                decoration: const InputDecoration(labelText: 'Chaj anplis', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('TOTAL (devi)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    Text(MoneyFormatter.format(_total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  icon: const Icon(Icons.description),
                  label: Text(_printing ? 'Ap enprime…' : 'Enprime Pofoma (A4)'),
                  onPressed: _printing ? null : _print,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Kliyan aksepte → Check-in'),
                  onPressed: _room == null ? null : () => context.push('/hotel/checkin/${_room!.id}'),
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
}
