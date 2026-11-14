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

  HotelRoom? _room;
  bool _loading = true;
  bool _saving = false;
  HotelRentalMode _mode = HotelRentalMode.nightly;
  int _duration = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final room = await ref.read(hotelRepositoryProvider).findRoom(widget.roomId);
    if (mounted) {
      setState(() {
        _room = room;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _idCtrl, _depositCtrl, _extraCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _rate =>
      _mode == HotelRentalMode.hourly ? (_room?.pricePerHour ?? 0) : (_room?.pricePerNight ?? 0);
  double get _extra => double.tryParse(_extraCtrl.text.trim()) ?? 0;
  double get _total => (_rate * _duration + _extra).clamp(0, double.infinity).toDouble();

  Future<void> _save() async {
    final room = _room;
    if (room == null) return;
    // Obligatwa: non, telefòn, NIF/CIN
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
      final stay = await ref.read(hotelRepositoryProvider).checkIn(
            storeId: storeId,
            room: room,
            userId: auth?.user.id,
            cashierName: auth?.user.name,
            guestName: name,
            guestPhone: phone,
            guestIdDoc: idDoc,
            mode: _mode,
            duration: _duration,
            extra: _extra,
            deposit: double.tryParse(_depositCtrl.text.trim()) ?? 0,
            notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          );
      // ignore: unawaited_futures
      ref.read(syncServiceProvider).runOnce();
      if (!mounted) return;
      context.pushReplacement('/hotel/stay/${stay.id}');
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
    final room = _room;
    if (room == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Chanm pa jwenn.')));
    }
    return Scaffold(
      appBar: AppBar(title: Text('Check-in · ${room.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Mòd lwaye
          const Text('Mòd lwaye', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<HotelRentalMode>(
            segments: const [
              ButtonSegment(value: HotelRentalMode.nightly, label: Text('🌙 Pa nwit')),
              ButtonSegment(value: HotelRentalMode.hourly, label: Text('⏱️ Pa èdtan')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              _duration = 1;
            }),
          ),
          const SizedBox(height: 16),
          // Dire
          Text('Dire (${_mode.unit})', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.remove),
                onPressed: _duration > 1 ? () => setState(() => _duration--) : null,
              ),
              Expanded(
                child: Text(
                  '$_duration ${_mode.unit}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton.filledTonal(
                icon: const Icon(Icons.add),
                onPressed: () => setState(() => _duration++),
              ),
            ],
          ),
          // Rakousi rapid
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final n in (_mode == HotelRentalMode.hourly ? const [1, 2, 3, 4, 6, 12] : const [1, 2, 3, 7]))
                ChoiceChip(
                  label: Text('$n'),
                  selected: _duration == n,
                  onSelected: (_) => setState(() => _duration = n),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Non kliyan *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            decoration: const InputDecoration(
              labelText: 'Telefòn *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _idCtrl,
            decoration: const InputDecoration(
              labelText: 'NIF / CIN *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.badge)),
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
                _row('${MoneyFormatter.format(_rate)} × $_duration ${_mode.unit}',
                    MoneyFormatter.format(_rate * _duration)),
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
              label: Text(_saving ? 'Ap sove…' : 'Check-in'),
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String l, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(l, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 17 : null)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 17 : null)),
        ]),
      );
}
