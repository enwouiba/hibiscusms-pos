import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

class HotelRoomsScreen extends ConsumerWidget {
  const HotelRoomsScreen({super.key});

  Color _statusColor(HotelRoomStatus s, BuildContext ctx) => switch (s) {
        HotelRoomStatus.available => Colors.green,
        HotelRoomStatus.occupied => Colors.red,
        HotelRoomStatus.cleaning => Colors.orange,
      };

  Future<void> _tapRoom(BuildContext context, WidgetRef ref, HotelRoom room) async {
    switch (room.status) {
      case HotelRoomStatus.available:
        context.push('/hotel/checkin/${room.id}');
      case HotelRoomStatus.occupied:
        final stay = await ref.read(hotelRepositoryProvider).activeStayForRoom(room.id);
        if (!context.mounted) return;
        if (stay != null) {
          context.push('/hotel/stay/${stay.id}');
        } else {
          // Enkoyerans: chanm make okipe men pa gen sejou — remèt li lib.
          await ref.read(hotelRepositoryProvider).setRoomStatus(room.id, HotelRoomStatus.available);
          ref.invalidate(_roomsProvider);
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
          ref.invalidate(_roomsProvider);
          ref.invalidate(_statsProvider);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(_roomsProvider);
    final stats = ref.watch(_statsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chanm Otèl'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Sejou yo',
            onPressed: () => context.push('/hotel/stays'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(_roomsProvider);
              ref.invalidate(_statsProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_roomsProvider);
          ref.invalidate(_statsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Estatistik rapid
            stats.maybeWhen(
              data: (s) => Row(
                children: [
                  _stat('🟢 Lib', '${s['available'] ?? 0}', Colors.green),
                  _stat('🔴 Okipe', '${s['occupied'] ?? 0}', Colors.red),
                  _stat('Jodi a', MoneyFormatter.format((s['today_revenue'] ?? 0).toDouble()), Colors.blue),
                ],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            rooms.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Poko gen chanm. Klike « Ajoute Chanm ».')),
                  );
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: list.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.0,
                  ),
                  itemBuilder: (context, i) {
                    final r = list[i];
                    final c = _statusColor(r.status, context);
                    return Card(
                      color: c.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: c, width: 1.5),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _tapRoom(context, ref, r),
                        onLongPress: () => context.push('/hotel/room/${r.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.hotel, size: 30, color: c),
                              const SizedBox(height: 6),
                              Text(r.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (r.roomType?.isNotEmpty == true)
                                Text(r.roomType!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text('${r.status.emoji} ${r.status.label}',
                                  style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('Erè: $e'))),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Ajoute Chanm'),
        onPressed: () => context.push('/hotel/room/new'),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              children: [
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
}
