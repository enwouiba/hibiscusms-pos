import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../printing/data/printer_service.dart';
import '../../printing/presentation/print_controller.dart';

final _pairedProvider = FutureProvider.autoDispose<List<BluetoothPrinterDevice>>((ref) async {
  return ref.watch(printStateProvider.notifier).scanPaired();
});

final _savedAddressProvider = FutureProvider.autoDispose<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('printer_address');
});

class PrinterSettingsScreen extends ConsumerWidget {
  const PrinterSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(printStateProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_pairedProvider),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Selektè mòd
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mòd Printer', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (state.isSunmiDetected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 16),
                          const SizedBox(width: 6),
                          const Text('Machin SUNMI detekte', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  RadioListTile<PrinterMode>(
                    title: const Text('SUNMI Entegre'),
                    subtitle: const Text('Imprimant ki nan tèt machin nan'),
                    value: PrinterMode.sunmiIntegrated,
                    groupValue: state.mode,
                    onChanged: (v) => ref.read(printStateProvider.notifier).setMode(v!),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<PrinterMode>(
                    title: const Text('Bluetooth ESC/POS'),
                    subtitle: const Text('Imprimant ekstèn Bluetooth (HL-1203, etc.)'),
                    value: PrinterMode.bluetooth,
                    groupValue: state.mode,
                    onChanged: (v) => ref.read(printStateProvider.notifier).setMode(v!),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.print),
                      label: Text(state.isPrinting ? 'Ap enprime…' : 'Tès Enprime'),
                      onPressed: state.isPrinting
                          ? null
                          : () async {
                              final savedAddress = ref.read(_savedAddressProvider).valueOrNull;
                              final ok = await ref
                                  .read(printStateProvider.notifier)
                                  .testPrint(savedAddress: savedAddress);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(ok ? 'Tès reyisi!' : 'Pa kapab enprime — verifye konfigirasyon'),
                                ));
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bluetooth seksyon — sèlman si mòd bluetooth
          if (state.mode == PrinterMode.bluetooth) ...[
            const SizedBox(height: 16),
            _BluetoothSection(),
          ],

          if (state.lastError != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: const Icon(Icons.error, color: Colors.red),
                title: const Text('Dènye erè'),
                subtitle: Text(state.lastError!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BluetoothSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paired = ref.watch(_pairedProvider);
    final saved = ref.watch(_savedAddressProvider).valueOrNull;
    final state = ref.watch(printStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (saved != null)
          Card(
            color: Colors.green.shade50,
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Printer sove'),
              subtitle: Text(saved),
            ),
          ),
        const SizedBox(height: 16),
        const Text('Aparèy Bluetooth peyè', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        paired.when(
          data: (devices) {
            if (devices.isEmpty) {
              return const Card(
                child: ListTile(
                  leading: Icon(Icons.bluetooth_disabled),
                  title: Text('Pa gen aparèy peyè'),
                  subtitle: Text('Peyè printer ou nan paramèt sistèm Android premye.'),
                ),
              );
            }
            return Column(
              children: devices.map((d) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(d.name),
                      subtitle: Text(d.address),
                      trailing: FilledButton(
                        onPressed: state.isPrinting
                            ? null
                            : () async {
                                final ok = await ref.read(printStateProvider.notifier).connect(d);
                                if (ok) {
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setString('printer_address', d.address);
                                  await prefs.setString('printer_name', d.name);
                                  ref.invalidate(_savedAddressProvider);
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(ok ? 'Konekte ak ${d.name}' : 'Pa kapab konekte'),
                                  ));
                                }
                              },
                        child: const Text('Konekte'),
                      ),
                    ),
                  )).toList(),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Erè: $e'),
        ),
      ],
    );
  }
}
