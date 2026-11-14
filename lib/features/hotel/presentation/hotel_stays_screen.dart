import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/hotel.dart';
import '../data/hotel_repository.dart';

final _filterProvider = StateProvider<HotelStayStatus?>((_) => null);

final _staysProvider = FutureProvider.autoDispose<List<HotelStay>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  final status = ref.watch(_filterProvider);
  return ref.watch(hotelRepositoryProvider).listStays(storeId, status: status);
});

class HotelStaysScreen extends ConsumerWidget {
  const HotelStaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stays = ref.watch(_staysProvider);
    final filter = ref.watch(_filterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sejou yo'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_staysProvider)),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _chip(ref, 'Tout', null, filter),
                for (final s in HotelStayStatus.values) _chip(ref, '${s.emoji} ${s.label}', s, filter),
              ],
            ),
          ),
          Expanded(
            child: stays.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('Pa gen sejou pou kounye a.'));
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = list[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text('${s.stayNumber}')),
                      title: Text(s.guestName?.isNotEmpty == true ? s.guestName! : 'Sejou #${s.stayNumber}'),
                      subtitle: Text([
                        '🚪 ${s.roomNameSnapshot}',
                        '${s.status.emoji} ${s.status.label}',
                        if (s.amountDue > 0) 'Dèt: ${MoneyFormatter.format(s.amountDue)}',
                      ].join('  •  ')),
                      trailing: Text(MoneyFormatter.format(s.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () => context.push('/hotel/stay/${s.id}'),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erè: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(WidgetRef ref, String label, HotelStayStatus? value, HotelStayStatus? current) {
    final sel = value == current;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => ref.read(_filterProvider.notifier).state = value,
      ),
    );
  }
}
