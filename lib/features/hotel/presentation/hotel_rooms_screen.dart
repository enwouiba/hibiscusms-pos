import 'package:flutter/material.dart';
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

final _statsProvider = FutureProvider.autoDispose<Map<String, num>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return {};
  return ref.watch(hotelRepositoryProvider).stats(storeId);
});

// null = Tout
final _statusFilterProvider = StateProvider.autoDispose<HotelRoomStatus?>((_) => null);
final _searchProvider = StateProvider.autoDispose<String>((_) => '');

class HotelRoomsScreen extends ConsumerStatefulWidget {
  const HotelRoomsScreen({super.key});

  @override
  ConsumerState<HotelRoomsScreen> createState() => _HotelRoomsScreenState();
}

class _HotelRoomsScreenState extends ConsumerState<HotelRoomsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(_roomsProvider);
    ref.invalidate(_statsProvider);
  }

  Color _statusColor(HotelRoomStatus s) => switch (s) {
        HotelRoomStatus.available => Colors.green,
        HotelRoomStatus.occupied => Colors.red,
        HotelRoomStatus.cleaning => Colors.orange,
      };

  /// Filtre (rechèch + estati) epi òdone: lib an premye, apre netwayaj, apre okipe.
  List<HotelRoom> _prep(List<HotelRoom> rooms, String q, HotelRoomStatus? status) {
    final ql = q.trim().toLowerCase();
    final list = rooms.where((r) {
      if (ql.isNotEmpty && !r.name.toLowerCase().contains(ql)) return false;
      if (status != null && r.status != status) return false;
      return true;
    }).toList();
    int rank(HotelRoom r) => switch (r.status) {
          HotelRoomStatus.available => 0,
          HotelRoomStatus.cleaning => 1,
          HotelRoomStatus.occupied => 2,
        };
    list.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return list;
  }

  Future<void> _tapRoom(HotelRoom room) async {
    switch (room.status) {
      case HotelRoomStatus.available:
        context.push('/hotel/checkin/${room.id}');
      case HotelRoomStatus.occupied:
        final stay = await ref.read(hotelRepositoryProvider).activeStayForRoom(room.id);
        if (!mounted) return;
        if (stay != null) {
          context.push('/hotel/stay/${stay.id}');
        } else {
          await ref.read(hotelRepositoryProvider).setRoomStatus(room.id, HotelRoomStatus.available);
          _refresh();
        }
      case HotelRoomStatus.cleaning:
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(room.name),
            content: const Text('Chanm sa a nan netwayaj. Make li kòm LIB?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wi, li lib')),
            ],
          ),
        );
        if (ok == true) {
          await ref.read(hotelRepositoryProvider).setRoomStatus(room.id, HotelRoomStatus.available);
          _refresh();
        }
    }
  }

  // Sèlman jesyonè (nivo >= 2) ka jere chanm. Sekretè a ka sèlman klike yon
  // chanm pou bay sèvis (check-in).
  bool get _canManage => (ref.read(authControllerProvider).valueOrNull?.highestLevel(null) ?? 0) >= 2;

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(_roomsProvider);
    final stats = ref.watch(_statsProvider);
    final status = ref.watch(_statusFilterProvider);
    final search = ref.watch(_searchProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chanm Otèl'),
        actions: [
          IconButton(icon: const Icon(Icons.list_alt), tooltip: 'Sejou yo', onPressed: () => context.push('/hotel/stays')),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Estatistik rapid
            stats.maybeWhen(
              data: (s) => Row(children: [
                _stat('🟢 Lib', '${s['available'] ?? 0}', Colors.green),
                _stat('🔴 Okipe', '${s['occupied'] ?? 0}', Colors.red),
                _stat('Jodi a', MoneyFormatter.format((s['today_revenue'] ?? 0).toDouble()), Colors.blue),
              ]),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 10),
            // Rechèch
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Chèche yon chanm…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(_searchProvider.notifier).state = '';
                        },
                      ),
              ),
              onChanged: (v) => ref.read(_searchProvider.notifier).state = v,
            ),
            const SizedBox(height: 10),
            // Filtè estati
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _statusChip('Tout', null, status),
                _statusChip('🟢 Lib', HotelRoomStatus.available, status),
                _statusChip('🔴 Okipe', HotelRoomStatus.occupied, status),
                _statusChip('🧹 Netwayaj', HotelRoomStatus.cleaning, status),
              ]),
            ),
            const SizedBox(height: 8),
            rooms.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Poko gen chanm. Klike « Ajoute Chanm ».')),
                  );
                }
                final prepared = _prep(list, search, status);
                final nwit = prepared.where((r) => !r.isMoman).toList();
                final moman = prepared.where((r) => r.isMoman).toList();
                if (prepared.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(child: Text('Pa gen chanm ki matche.')),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (nwit.isNotEmpty) ...[
                      _sectionHeader('🌙 Nwit / Sejou', nwit.length),
                      _grid(nwit),
                    ],
                    if (moman.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _sectionHeader('⏱️ Moman', moman.length),
                      _grid(moman),
                    ],
                  ],
                );
              },
              loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('Erè: $e'))),
            ),
          ],
        ),
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Ajoute Chanm'),
              onPressed: () => context.push('/hotel/room/new'),
            )
          : null,
    );
  }

  Widget _sectionHeader(String title, int count) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: const TextStyle(fontSize: 12)),
          ),
        ]),
      );

  Widget _grid(List<HotelRoom> list) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: list.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, i) => _roomCard(list[i]),
      );

  Widget _roomCard(HotelRoom r) {
    final c = _statusColor(r.status);
    final price = r.isMoman ? '${MoneyFormatter.format(r.pricePerHour)}/moman (2h)' : '${MoneyFormatter.format(r.pricePerNight)}/nwit';
    return Card(
      color: c.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c, width: 1.5)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _tapRoom(r),
        onLongPress: _canManage ? () => context.push('/hotel/room/${r.id}') : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.hotel, size: 26, color: c),
            const SizedBox(height: 4),
            Text(r.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(price, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 2),
            Text('${r.status.emoji} ${r.status.label}', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _statusChip(String label, HotelRoomStatus? value, HotelRoomStatus? current) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: value == current,
          onSelected: (_) => ref.read(_statusFilterProvider.notifier).state = value,
        ),
      );

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(children: [
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}
