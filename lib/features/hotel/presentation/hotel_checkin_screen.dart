import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/token_store.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/hotel.dart';
import '../data/hotel_repository.dart';

/// Yon chanm nan yon check-in milti-chanm: chak chanm gen pwòp mòd + dire.
class _RoomBooking {
  _RoomBooking(this.room, this.mode, this.duration);
  HotelRoom room;
  HotelRentalMode mode;
  int duration;

  double get rate => mode == HotelRentalMode.hourly ? room.pricePerHour : room.pricePerNight;
  double get charge => rate * duration;
}

/// Check-in: bay yon KLIYAN youn OSWA PLIZYÈ chanm an menm tan — chak chanm ak
/// pwòp kantite nwit/èdtan pa l (egz: 3 chanm, youn 1 nwit, youn 3 nwit…).
/// Chak chanm fè pwòp sejou l epi li vin okipe.
class HotelCheckinScreen extends ConsumerStatefulWidget {
  const HotelCheckinScreen({super.key, required this.roomId});
  final String roomId;

  @override
  ConsumerState<HotelCheckinScreen> createState() => _HotelCheckinScreenState();
}

class _HotelCheckinScreenState extends ConsumerState<HotelCheckinScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _extraCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final List<_RoomBooking> _bookings = [];
  List<HotelRoom> _availableRooms = []; // chanm lib (pou ajoute plis)
  HotelRoom? _pendingRoom; // chanm k ap pral ajoute
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(hotelRepositoryProvider);
    final room = await repo.findRoom(widget.roomId);
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    final all = storeId != null ? await repo.listRooms(storeId) : <HotelRoom>[];
    if (!mounted) return;
    setState(() {
      if (room != null) {
        _bookings.add(_RoomBooking(room, HotelRentalMode.nightly, 1));
      }
      _availableRooms = all.where((r) => r.isAvailable).toList();
      _loading = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _idCtrl, _depositCtrl, _extraCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _extra => double.tryParse(_extraCtrl.text.trim()) ?? 0;
  double get _roomsTotal => _bookings.fold(0.0, (s, b) => s + b.charge);
  double get _total => (_roomsTotal + _extra).clamp(0, double.infinity).toDouble();

  // Chanm ki lib epi ki poko nan lis la
  List<HotelRoom> get _addableRooms {
    final taken = _bookings.map((b) => b.room.id).toSet();
    return _availableRooms.where((r) => !taken.contains(r.id)).toList();
  }

  void _addPendingRoom() {
    final r = _pendingRoom;
    if (r == null) return;
    setState(() {
      _bookings.add(_RoomBooking(r, HotelRentalMode.nightly, 1));
      _pendingRoom = null;
    });
  }

  Future<void> _save() async {
    if (_bookings.isEmpty) return;
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final idDoc = _idCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty || idDoc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Non kliyan, Telefòn ak NIF/CIN yo obligatwa')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final storeId = await ref.read(tokenStoreProvider).activeStoreId();
      final auth = ref.read(authControllerProvider).valueOrNull;
      if (storeId == null) throw Exception('Chwazi yon magazen');
      final repo = ref.read(hotelRepositoryProvider);
      final deposit = double.tryParse(_depositCtrl.text.trim()) ?? 0;
      final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

      HotelStay? firstStay;
      for (int i = 0; i < _bookings.length; i++) {
        final b = _bookings[i];
        // Chaj anplis + depo yo ale sou PREMYE chanm nan (total sinkronize bon).
        final stay = await repo.checkIn(
          storeId: storeId,
          room: b.room,
          userId: auth?.user.id,
          cashierName: auth?.user.name,
          guestName: name,
          guestPhone: phone,
          guestIdDoc: idDoc,
          mode: b.mode,
          duration: b.duration,
          extra: i == 0 ? _extra : 0,
          deposit: i == 0 ? deposit : 0,
          notes: notes,
        );
        firstStay ??= stay;
      }
      // ignore: unawaited_futures
      ref.read(syncServiceProvider).runOnce();
      if (!mounted) return;
      // 1 chanm → detay sejou a; plizyè → lis sejou yo
      if (_bookings.length == 1 && firstStay != null) {
        context.pushReplacement('/hotel/stay/${firstStay.id}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_bookings.length} chanm bay $name')),
        );
        context.pushReplacement('/hotel/stays');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_bookings.isEmpty) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Chanm pa jwenn.')));
    }
    final addable = _addableRooms;
    return Scaffold(
      appBar: AppBar(title: Text(_bookings.length == 1 ? 'Check-in · ${_bookings.first.room.name}' : 'Check-in · ${_bookings.length} chanm')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('CHANM KLIYAN AN AP PRAN', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          // ── Chak chanm ak pwòp mòd + dire ──
          for (int i = 0; i < _bookings.length; i++) _roomCard(i),

          // ── Ajoute yon lòt chanm ──
          if (addable.isNotEmpty) ...[
            const SizedBox(height: 4),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<HotelRoom>(
                      initialValue: _pendingRoom,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Lòt chanm', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.add_home)),
                      items: [for (final r in addable) DropdownMenuItem(value: r, child: Text(r.name))],
                      onChanged: (r) => setState(() => _pendingRoom = r),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _pendingRoom == null ? null : _addPendingRoom,
                    child: const Text('Ajoute'),
                  ),
                ]),
              ),
            ),
          ],

          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Non kliyan *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(labelText: 'Telefòn *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _idCtrl,
            decoration: const InputDecoration(labelText: 'NIF / CIN *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _extraCtrl,
                decoration: const InputDecoration(labelText: 'Chaj anplis', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _depositCtrl,
                decoration: const InputDecoration(labelText: 'Depo / Peman', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Nòt (opsyonèl)', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                for (final b in _bookings)
                  _row('Chanm ${b.room.name} · ${b.duration} ${b.mode.unit}',
                      MoneyFormatter.format(b.charge)),
                if (_extra > 0) _row('Chaj anplis', MoneyFormatter.format(_extra)),
                const Divider(),
                _row('TOTAL', MoneyFormatter.format(_total), bold: true),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              icon: const Icon(Icons.login),
              label: Text(_saving ? 'Ap sove…' : (_bookings.length == 1 ? 'Check-in' : 'Check-in ${_bookings.length} chanm')),
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomCard(int i) {
    final b = _bookings[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.hotel, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text('Chanm ${b.room.name}', style: const TextStyle(fontWeight: FontWeight.bold))),
            Text(MoneyFormatter.format(b.charge), style: const TextStyle(fontWeight: FontWeight.bold)),
            if (_bookings.length > 1)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _bookings.removeAt(i)),
              ),
          ]),
          const SizedBox(height: 6),
          SegmentedButton<HotelRentalMode>(
            segments: const [
              ButtonSegment(value: HotelRentalMode.nightly, label: Text('🌙 Nwit')),
              ButtonSegment(value: HotelRentalMode.hourly, label: Text('⏱️ Èdtan')),
            ],
            selected: {b.mode},
            onSelectionChanged: (s) => setState(() { b.mode = s.first; b.duration = 1; }),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text('Dire: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton.filledTonal(
              icon: const Icon(Icons.remove),
              visualDensity: VisualDensity.compact,
              onPressed: b.duration > 1 ? () => setState(() => b.duration--) : null,
            ),
            Expanded(child: Text('${b.duration} ${b.mode.unit}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            IconButton.filledTonal(
              icon: const Icon(Icons.add),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => b.duration++),
            ),
          ]),
          Wrap(
            spacing: 6,
            children: [
              for (final n in (b.mode == HotelRentalMode.hourly ? const [1, 2, 3, 4, 6, 12] : const [1, 2, 3, 7]))
                ChoiceChip(
                  label: Text('$n'),
                  selected: b.duration == n,
                  onSelected: (_) => setState(() => b.duration = n),
                ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _row(String l, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(l, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 17 : null))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 17 : null)),
        ]),
      );
}
