import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/token_store.dart';
import '../data/hotel_repository.dart';

class HotelRoomFormScreen extends ConsumerStatefulWidget {
  const HotelRoomFormScreen({super.key, this.roomId});
  final String? roomId;

  @override
  ConsumerState<HotelRoomFormScreen> createState() => _HotelRoomFormScreenState();
}

class _HotelRoomFormScreenState extends ConsumerState<HotelRoomFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _nightCtrl = TextEditingController();
  final _hourCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loading = false;
  bool _saving = false;

  bool get _isEdit => widget.roomId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final room = await ref.read(hotelRepositoryProvider).findRoom(widget.roomId!);
    if (room != null && mounted) {
      _nameCtrl.text = room.name;
      _typeCtrl.text = room.roomType ?? '';
      _nightCtrl.text = room.pricePerNight.toStringAsFixed(2);
      _hourCtrl.text = room.pricePerHour.toStringAsFixed(2);
      _notesCtrl.text = room.notes ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _typeCtrl, _nightCtrl, _hourCtrl, _notesCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final storeId = await ref.read(tokenStoreProvider).activeStoreId();
      if (storeId == null) throw Exception('Chwazi yon magazen');
      final repo = ref.read(hotelRepositoryProvider);
      final name = _nameCtrl.text.trim();
      final type = _typeCtrl.text.trim().isEmpty ? null : _typeCtrl.text.trim();
      final night = double.tryParse(_nightCtrl.text.trim()) ?? 0;
      final hour = double.tryParse(_hourCtrl.text.trim()) ?? 0;
      final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

      if (_isEdit) {
        await repo.updateRoom(
          id: widget.roomId!, name: name, roomType: type,
          pricePerNight: night, pricePerHour: hour, notes: notes,
        );
      } else {
        await repo.createRoom(
          storeId: storeId, name: name, roomType: type,
          pricePerNight: night, pricePerHour: hour, notes: notes,
        );
      }
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erè: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Efase chanm'),
        content: Text('Efase « ${_nameCtrl.text} » ? Sejou ki pase yo rete.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Efase'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(hotelRepositoryProvider).deleteRoom(widget.roomId!);
    if (mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    const money = TextInputType.numberWithOptions(decimal: true);
    final moneyFmt = <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))];
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Modifye Chanm' : 'Nouvo Chanm'),
        actions: [
          if (_isEdit)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _saving ? null : _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Non / Nimewo chanm *',
                      hintText: 'Chanm 101',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.hotel),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Antre yon non' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _typeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tip chanm (opsyonèl)',
                      hintText: 'Standard, VIP, Doub...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nightCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Pri pa nwit *', border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.nightlight_round),
                        ),
                        keyboardType: money, inputFormatters: moneyFmt,
                        validator: (v) => (double.tryParse(v?.trim() ?? '') == null) ? 'Pri' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _hourCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Pri pa moman (2h) *', border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.schedule),
                        ),
                        keyboardType: money, inputFormatters: moneyFmt,
                        validator: (v) => (double.tryParse(v?.trim() ?? '') == null) ? 'Pri' : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nòt (opsyonèl)', border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: Text(_saving ? 'Ap sove…' : 'Sove'),
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
