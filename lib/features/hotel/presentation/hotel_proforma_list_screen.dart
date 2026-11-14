import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/hotel.dart';
import '../data/hotel_repository.dart';

final hotelProformasProvider = FutureProvider.autoDispose<List<HotelProforma>>((ref) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  return ref.watch(hotelRepositoryProvider).listProformas(storeId);
});

/// Lis POFOMA ki sove — ou ka re-ouvri yo pou enprime oswa valide.
class HotelProformaListScreen extends ConsumerWidget {
  const HotelProformaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proformas = ref.watch(hotelProformasProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pofoma yo'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(hotelProformasProvider)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nouvo Pofoma'),
        onPressed: () => context.push('/hotel/proforma'),
      ),
      body: proformas.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Poko gen pofoma. Peze « Nouvo Pofoma » pou fè yon kòt.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(hotelProformasProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final p = list[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: p.validated ? Colors.teal.shade100 : Colors.orange.shade100,
                      child: Icon(p.validated ? Icons.check : Icons.description,
                          color: p.validated ? Colors.teal.shade800 : Colors.orange.shade800),
                    ),
                    title: Text('${p.validated ? "FAKTI" : "POFOMA"} #${p.number} — ${p.guestName ?? "San non"}'),
                    subtitle: Text('${p.roomCount} chanm • ${_date(p.createdAt)}'),
                    trailing: Text(MoneyFormatter.format(p.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () => context.push('/hotel/proforma/${p.id}'),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erè: $e')),
      ),
    );
  }

  static String _date(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}
