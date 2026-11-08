import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/auth/token_store.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/models/cart_item.dart';
import '../../../shared/models/product.dart';
import '../../products/data/product_repository.dart';
import 'cart_controller.dart';
import 'checkout_sheet.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _BarcodeScannerScreen()),
    );
    if (result == null || !mounted) return;
    final storeId = await ref.read(tokenStoreProvider).activeStoreId();
    if (storeId == null) return;
    final product = await ref.read(productRepositoryProvider).findByBarcode(storeId, result);
    if (!mounted) return;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pa jwenn pwodwi ak barcode: $result')),
      );
    } else {
      ref.read(cartProvider.notifier).addProduct(product);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width > 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouvo Vant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan barcode',
            onPressed: _scanBarcode,
          ),
          if (cart.isEmpty == false)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Vide kart',
              onPressed: () => ref.read(cartProvider.notifier).clear(),
            ),
        ],
      ),
      body: isTablet
          ? Row(
              children: [
                Expanded(flex: 3, child: _ProductGrid(search: _search, ctrl: _searchCtrl, onSearch: (v) => setState(() => _search = v))),
                const VerticalDivider(width: 1),
                Expanded(flex: 2, child: const _CartPanel()),
              ],
            )
          : Column(
              children: [
                Expanded(child: _ProductGrid(search: _search, ctrl: _searchCtrl, onSearch: (v) => setState(() => _search = v))),
                const Divider(height: 1),
                SizedBox(height: 280, child: const _CartPanel()),
              ],
            ),
    );
  }
}

class _ProductGrid extends ConsumerWidget {
  const _ProductGrid({required this.search, required this.ctrl, required this.onSearch});
  final String search;
  final TextEditingController ctrl;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(_posProductsProvider(search));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              hintText: 'Chèche pwodwi…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: ctrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        ctrl.clear();
                        onSearch('');
                      },
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: onSearch,
          ),
        ),
        Expanded(
          child: productsAsync.when(
            data: (products) {
              if (products.isEmpty) {
                return const Center(child: Text('Pa jwenn pwodwi.'));
              }
              return GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.95,
                ),
                itemCount: products.length,
                itemBuilder: (context, i) {
                  final p = products[i];
                  return Card(
                    clipBehavior: Clip.hardEdge,
                    child: InkWell(
                      onTap: () => ref.read(cartProvider.notifier).addProduct(p),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(Icons.inventory_2, size: 32, color: Theme.of(context).colorScheme.primary),
                            Text(
                              p.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Column(
                              children: [
                                Text(MoneyFormatter.format(p.price),
                                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                                if (p.trackStock)
                                  Text('Stock: ${p.stock.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: p.isLowStock ? Colors.red : Colors.grey,
                                      )),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erè: $e')),
          ),
        ),
      ],
    );
  }
}

final _posProductsProvider = FutureProvider.family.autoDispose<List<Product>, String>((ref, search) async {
  final storeId = await ref.watch(tokenStoreProvider).activeStoreId();
  if (storeId == null) return [];
  return ref.watch(productRepositoryProvider).listAll(storeId, search: search);
});

class _CartPanel extends ConsumerWidget {
  const _CartPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    return Column(
      children: [
        Expanded(
          child: cart.items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Kart vid', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: cart.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = cart.items[i];
                    return _CartLine(item: item);
                  },
                ),
        ),
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Soustotal'),
                  Text(MoneyFormatter.format(cart.subtotal)),
                ],
              ),
              if (cart.taxTotal > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TCA'),
                    Text(MoneyFormatter.format(cart.taxTotal)),
                  ],
                ),
              if (cart.extraDiscount > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Rabè'),
                    Row(children: [
                      Text('- ${MoneyFormatter.format(cart.extraDiscount)}'),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ref.read(cartProvider.notifier).setDiscount(0),
                      ),
                    ]),
                  ],
                ),
              // Bouton pou ajoute/modifye rabè (visible sèl si gen atik nan panye)
              if (!cart.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.local_offer_outlined, size: 18),
                    label: Text(cart.extraDiscount > 0 ? 'Modifye Rabè' : 'Ajoute Rabè'),
                    onPressed: () => _showDiscountDialog(context, ref, cart.subtotal, cart.extraDiscount),
                  ),
                ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    MoneyFormatter.format(cart.grandTotal),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Konfime Vant'),
                  onPressed: cart.isEmpty
                      ? null
                      : () async {
                          await showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => const CheckoutSheet(),
                          );
                        },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartLine extends ConsumerWidget {
  const _CartLine({required this.item});
  final CartItem item;

  Future<bool> _confirmDelete(BuildContext context) async {
    if (item.quantity <= 1) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Efase pwodwi sa nan kart?'),
        content: Text(
          '${item.product.name} (×${item.quantity.toStringAsFixed(0)}) ap retire nan kart la.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anile')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Efase'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _editQty(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: item.quantity.toStringAsFixed(0));
    final result = await showDialog<double?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item.product.name),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Kantite', border: OutlineInputBorder()),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anile')),
          FilledButton(
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text) ?? item.quantity),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) {
      ref.read(cartProvider.notifier).setQuantity(item.product.id, result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('cart_${item.product.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.delete, color: Colors.white),
            SizedBox(width: 8),
            Text('Efase', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => ref.read(cartProvider.notifier).remove(item.product.id),
      child: ListTile(
        onTap: () => _editQty(context, ref),
        title: Text(item.product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${MoneyFormatter.format(item.product.price)}  •  Soustotal: ${MoneyFormatter.formatPlain(item.subtotal)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle, color: Colors.orange),
              tooltip: 'Mwen 1',
              onPressed: () {
                final newQty = item.quantity - 1;
                if (newQty <= 0) {
                  _confirmDelete(context).then((ok) {
                    if (ok) ref.read(cartProvider.notifier).remove(item.product.id);
                  });
                } else {
                  ref.read(cartProvider.notifier).setQuantity(item.product.id, newQty);
                }
              },
            ),
            SizedBox(
              width: 32,
              child: Text(item.quantity.toStringAsFixed(0),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.green),
              tooltip: 'Plis 1',
              onPressed: () => ref.read(cartProvider.notifier).setQuantity(item.product.id, item.quantity + 1),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              tooltip: 'Efase',
              onPressed: () async {
                if (await _confirmDelete(context)) {
                  ref.read(cartProvider.notifier).remove(item.product.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BarcodeScannerScreen extends StatelessWidget {
  const _BarcodeScannerScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan barcode')),
      body: MobileScanner(
        onDetect: (capture) {
          final value = capture.barcodes.firstOrNull?.rawValue;
          if (value != null) {
            Navigator.of(context).pop(value);
          }
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 🏷️ DISCOUNT DIALOG — % oswa Fiks
// ══════════════════════════════════════════════════════════════════
Future<void> _showDiscountDialog(BuildContext context, WidgetRef ref, double subtotal, double currentDiscount) async {
  bool isPercent = false;  // Fiks pa defo
  // Si gen yon rabè aktyèl, kalkile % ekivalan pou pre-populate
  final initialValue = currentDiscount > 0 ? currentDiscount.toStringAsFixed(0) : '';
  final ctrl = TextEditingController(text: initialValue);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        left: 16, right: 16, top: 16,
      ),
      child: StatefulBuilder(
        builder: (ctx, setSt) {
          final entered = double.tryParse(ctrl.text.trim()) ?? 0;
          final calculatedDiscount = isPercent
              ? (subtotal * entered / 100).clamp(0, subtotal).toDouble()
              : entered.clamp(0, subtotal).toDouble();
          final newTotal = (subtotal - calculatedDiscount).clamp(0, double.infinity).toDouble();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
              )),
              Row(children: [
                const Icon(Icons.local_offer, color: Colors.orange, size: 26),
                const SizedBox(width: 8),
                Text('Ajoute Rabè',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 6),
              Text('Soustotal: ${MoneyFormatter.format(subtotal)}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 15)),
              const SizedBox(height: 20),
              // Toggle % ↔ Fiks
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('💰 Fiks (HTG)'), icon: Icon(Icons.attach_money)),
                  ButtonSegment(value: true, label: Text('% Pousantaj'), icon: Icon(Icons.percent)),
                ],
                selected: {isPercent},
                onSelectionChanged: (s) => setSt(() {
                  isPercent = s.first;
                  ctrl.text = '';
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: isPercent ? 'Pousantaj rabè' : 'Mòn rabè',
                  suffixText: isPercent ? '%' : 'HTG',
                  border: const OutlineInputBorder(),
                  prefixIcon: Icon(isPercent ? Icons.percent : Icons.attach_money),
                  helperText: isPercent
                    ? 'Egzanp: 10 = 10% off'
                    : 'Egzanp: 100 = 100 HTG off',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                autofocus: true,
                onChanged: (_) => setSt(() {}),
              ),
              const SizedBox(height: 8),
              // Rapid shortcuts
              Wrap(spacing: 6, children: [
                if (isPercent)
                  ...[5, 10, 15, 20, 25, 50].map((p) =>
                    ActionChip(
                      label: Text('$p%'),
                      onPressed: () { ctrl.text = p.toString(); setSt(() {}); },
                    ),
                  )
                else
                  ...[50, 100, 200, 500].map((p) =>
                    ActionChip(
                      label: Text(MoneyFormatter.format(p.toDouble())),
                      onPressed: () { ctrl.text = p.toString(); setSt(() {}); },
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              // Preview
              if (entered > 0) Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Rabè:', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('- ${MoneyFormatter.format(calculatedDiscount)}',
                      style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Nouvo Total:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(MoneyFormatter.format(newTotal),
                      style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 20)),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                if (currentDiscount > 0)
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () {
                      ref.read(cartProvider.notifier).setDiscount(0);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Retire', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Colors.red),
                    ),
                  )),
                if (currentDiscount > 0) const SizedBox(width: 8),
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Anile')),
                )),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: FilledButton.icon(
                  icon: const Icon(Icons.check_circle),
                  onPressed: entered <= 0 ? null : () {
                    ref.read(cartProvider.notifier).setDiscount(calculatedDiscount);
                    Navigator.pop(ctx);
                  },
                  label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Aplike')),
                )),
              ]),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    ),
  );
  ctrl.dispose();
}
