import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/hotel.dart';
import '../data/hotel_repository.dart';

final _roomsProvider = FutureProvider.autoDispose<List<HotelRoom>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  return ref.watch(hotelRepositoryProvider).listRooms(storeId);
});

/// Ekran NOUVO POFOMA (devi): fè yon kòt pou yon kliyan AVAN check-in.
/// Li ka gen PLIZYÈ chanm (kliyan ka pran plizyè chanm pou diferan nwit).
/// Lè w sove l, li ale nan detay la kote w ka re-enprime oswa valide l.
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
  final _discountCtrl = TextEditingController();

  // Liy chanm yo ki deja ajoute
  final List<HotelProformaItem> _items = [];

  // Zòn "ajoute yon chanm"
  HotelRoom? _pendingRoom;
  HotelRentalMode _pendingMode = HotelRentalMode.nightly;
  int _pendingDuration = 1;

  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _idCtrl, _extraCtrl, _discountCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _extra => double.tryParse(_extraCtrl.text.trim()) ?? 0;
  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0;
  double get _itemsTotal => _items.fold(0.0, (s, i) => s + i.lineTotal);
  double get _total => (_itemsTotal + _extra - _discount).clamp(0, double.infinity).toDouble();

  double _pendingRate(HotelRoom r) =>
      _pendingMode == HotelRentalMode.hourly ? r.pricePerHour : r.pricePerNight;

  void _addRoom() {
    final r = _pendingRoom;
    if (r == null) return;
    setState(() {
      _items.add(HotelProformaItem(
        roomId: r.id,
        roomName: r.name,
        mode: _pendingMode,
        duration: _pendingDuration,
        rate: _pendingRate(r),
      ));
      _pendingDuration = 1;
    });
  }

  Future<void> _save({required bool thenPrint}) async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ajoute omwen yon chanm')));
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Non kliyan obligatwa')));
      return;
    }
    setState(() => _saving = true);
    try {
      final storeId = await ref.read(tokenStoreProvider).activeStoreId();
      if (storeId == null) throw 'Pa gen magazen aktif';
      final session = ref.read(authControllerProvider).valueOrNull;
      final proforma = await ref.read(hotelRepositoryProvider).createProforma(
            storeId: storeId,
            userId: session?.user.id,
            cashierName: session?.user.name,
            guestName: _nameCtrl.text.trim(),
            guestPhone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
            guestIdDoc: _idCtrl.text.trim().isEmpty ? null : _idCtrl.text.trim(),
            items: _items,
            extra: _extra,
            discount: _discount,
          );
      if (!mounted) return;
      setState(() => _saving = false);
      // Ale nan detay la — kote w ka re-enprime / valide (+ enprime otomatik)
      context.pushReplacement('/hotel/proforma/${proforma.id}${thenPrint ? '?print=1' : ''}');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(_roomsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvo Pofoma (Devi)')),
      body: rooms.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Poko gen chanm. Ajoute chanm dabò.'));
          }
          _pendingRoom ??= list.first;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Fè yon kòt pou yon kliyan anvan check-in. Ou ka mete plizyè chanm.',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 14),

              // ── Kliyan ──
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Non kliyan *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
              const SizedBox(height: 10),
              TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Telefòn', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              TextField(controller: _idCtrl, decoration: const InputDecoration(labelText: 'NIF / CIN', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge))),

              const SizedBox(height: 18),
              const Text('CHANM YO', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              // ── Lis chanm ki deja ajoute ──
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Poko gen chanm ajoute.', style: TextStyle(color: Colors.grey)),
                ),
              for (int i = 0; i < _items.length; i++)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: Text(_items[i].mode.emoji, style: const TextStyle(fontSize: 20)),
                    title: Text('Chanm ${_items[i].roomName}'),
                    subtitle: Text('${_items[i].duration} ${_items[i].mode.unit} × ${MoneyFormatter.format(_items[i].rate)}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(MoneyFormatter.format(_items[i].lineTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _items.removeAt(i))),
                    ]),
                  ),
                ),

              // ── Zòn ajoute yon chanm ──
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    DropdownButtonFormField<HotelRoom>(
                      initialValue: _pendingRoom,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Chanm', border: OutlineInputBorder(), prefixIcon: Icon(Icons.hotel), isDense: true),
                      items: [for (final r in list) DropdownMenuItem(value: r, child: Text(r.name))],
                      onChanged: (r) => setState(() => _pendingRoom = r),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<HotelRentalMode>(
                      segments: const [
                        ButtonSegment(value: HotelRentalMode.nightly, label: Text('🌙 Pa nwit')),
                        ButtonSegment(value: HotelRentalMode.hourly, label: Text('⏱️ Pa èdtan')),
                      ],
                      selected: {_pendingMode},
                      onSelectionChanged: (s) => setState(() { _pendingMode = s.first; _pendingDuration = 1; }),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Dire: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      IconButton.filledTonal(icon: const Icon(Icons.remove), onPressed: _pendingDuration > 1 ? () => setState(() => _pendingDuration--) : null),
                      Expanded(child: Text('$_pendingDuration ${_pendingMode.unit}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                      IconButton.filledTonal(icon: const Icon(Icons.add), onPressed: () => setState(() => _pendingDuration++)),
                    ]),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.add),
                        label: Text(_pendingRoom == null
                            ? 'Ajoute chanm'
                            : 'Ajoute chanm (${MoneyFormatter.format(_pendingRate(_pendingRoom!) * _pendingDuration)})'),
                        onPressed: _pendingRoom == null ? null : _addRoom,
                      ),
                    ),
                  ]),
                ),
              ),

              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextField(
                  controller: _extraCtrl,
                  decoration: const InputDecoration(labelText: 'Chaj anplis', border: OutlineInputBorder(), isDense: true),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  onChanged: (_) => setState(() {}),
                )),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: _discountCtrl,
                  decoration: const InputDecoration(labelText: 'Rabè', border: OutlineInputBorder(), isDense: true),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                  onChanged: (_) => setState(() {}),
                )),
              ]),

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
                  icon: const Icon(Icons.save),
                  label: Text(_saving ? 'Ap sove…' : 'Sove & Enprime Pofoma (A4)'),
                  onPressed: _saving ? null : () => _save(thenPrint: true),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.bookmark_add),
                  label: const Text('Sove sèlman (san enprime)'),
                  onPressed: _saving ? null : () => _save(thenPrint: false),
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
