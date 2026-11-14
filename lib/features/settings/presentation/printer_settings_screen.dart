import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../printing/data/printer_service.dart';
import '../../printing/presentation/print_controller.dart';

bool get _isDesktop {
  try {
    return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  } catch (_) {
    return false;
  }
}

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
                  if (isWindowsDesktop)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text('Sou Windows: resi/fakti enprime sou sistèm enprimant Windows la. Chwazi enprimant yo anba a.',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  if (!isWindowsDesktop) ...[
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
                  // Transpò desktop (USB / Rezo / CUPS) — sou òdinatè sèlman
                  if (_isDesktop) ...[
                    RadioListTile<PrinterMode>(
                      title: const Text('USB / Aparèy (ESC/POS)'),
                      subtitle: const Text('Enprimant USB dirèk — egz. Epson TM-T20II (/dev/usb/lp0)'),
                      value: PrinterMode.usb,
                      groupValue: state.mode,
                      onChanged: (v) => ref.read(printStateProvider.notifier).setMode(v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<PrinterMode>(
                      title: const Text('Rezo (TCP 9100)'),
                      subtitle: const Text('Enprimant rezo ESC/POS pa IP'),
                      value: PrinterMode.network,
                      groupValue: state.mode,
                      onChanged: (v) => ref.read(printStateProvider.notifier).setMode(v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                    RadioListTile<PrinterMode>(
                      title: const Text('Sistèm / CUPS (lp)'),
                      subtitle: const Text('Nenpòt enprimant ki enstale nan sistèm nan'),
                      value: PrinterMode.cups,
                      groupValue: state.mode,
                      onChanged: (v) => ref.read(printStateProvider.notifier).setMode(v!),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                  ],
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

          // Seksyon konfigirasyon — pa sou Windows (Linux/Android sèlman)
          if (!isWindowsDesktop && state.mode == PrinterMode.bluetooth) ...[
            const SizedBox(height: 16),
            _BluetoothSection(),
          ],
          if (!isWindowsDesktop && state.mode == PrinterMode.usb) ...[
            const SizedBox(height: 16),
            const _UsbSection(),
          ],
          if (!isWindowsDesktop && state.mode == PrinterMode.network) ...[
            const SizedBox(height: 16),
            const _NetworkSection(),
          ],
          if (!isWindowsDesktop && state.mode == PrinterMode.cups) ...[
            const SizedBox(height: 16),
            const _CupsSection(),
          ],
          // Windows: enprimant resi (tèmik)
          if (isWindowsDesktop) ...[
            const SizedBox(height: 16),
            const _WinThermalSection(),
          ],
          // 2èm enprimant A4 (fakti nwit otèl) — toujou montre sou desktop
          if (_isDesktop) ...[
            const SizedBox(height: 16),
            const _A4Section(),
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

/// Konfigirasyon USB / Aparèy: chemen aparèy la (egz. /dev/usb/lp0).
class _UsbSection extends StatefulWidget {
  const _UsbSection();
  @override
  State<_UsbSection> createState() => _UsbSectionState();
}

class _UsbSectionState extends State<_UsbSection> {
  final _ctrl = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _ctrl.text = p.getString('printer_device_path') ?? '/dev/usb/lp0';
        _loaded = true;
      });
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('printer_device_path', _ctrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chemen aparèy la sove')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Enprimant USB', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Chemen aparèy la nan sistèm nan. Sou Linux, yon enprimant USB konekte '
              'parèt kòm /dev/usb/lp0 (oswa lp1…).', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(labelText: 'Chemen aparèy', border: OutlineInputBorder(), hintText: '/dev/usb/lp0'),
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(icon: const Icon(Icons.save), label: const Text('Sove'), onPressed: _save)),
          const SizedBox(height: 8),
          const Text('Nòt: itilizatè a dwe gen dwa ekri sou aparèy la (gwoup « lp » sou Linux).',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }
}

/// Konfigirasyon Rezo: IP + pò.
class _NetworkSection extends StatefulWidget {
  const _NetworkSection();
  @override
  State<_NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends State<_NetworkSection> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '9100');
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _host.text = p.getString('printer_host') ?? '';
        _port.text = (p.getInt('printer_port') ?? 9100).toString();
        _loaded = true;
      });
    });
  }

  @override
  void dispose() { _host.dispose(); _port.dispose(); super.dispose(); }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('printer_host', _host.text.trim());
    await p.setInt('printer_port', int.tryParse(_port.text.trim()) ?? 9100);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enprimant rezo sove')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Enprimant Rezo (ESC/POS)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(flex: 3, child: TextField(controller: _host, decoration: const InputDecoration(labelText: 'Adrès IP', border: OutlineInputBorder(), hintText: '192.168.1.50'))),
            const SizedBox(width: 10),
            Expanded(flex: 1, child: TextField(controller: _port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pò', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(icon: const Icon(Icons.save), label: const Text('Sove'), onPressed: _save)),
        ]),
      ),
    );
  }
}

/// Windows: enprimant RESI (tèmik). Resi/moman enprime isit la via motè
/// `printing`. Pref `printer_win_thermal`.
class _WinThermalSection extends StatefulWidget {
  const _WinThermalSection();
  @override
  State<_WinThermalSection> createState() => _WinThermalSectionState();
}

class _WinThermalSectionState extends State<_WinThermalSection> {
  final _ctrl = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _ctrl.text = p.getString('printer_win_thermal') ?? '';
        _loaded = true;
      });
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('printer_win_thermal', _ctrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enprimant resi sove')));
    }
  }

  Future<void> _list() async {
    final printers = await PrinterService.instance.listSystemPrinters();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enprimant yo'),
        content: printers.isEmpty
            ? const Text('Pa gen enprimant jwenn.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: printers
                      .map((p) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.print, size: 18),
                            title: Text(p),
                            onTap: () { _ctrl.text = p; Navigator.pop(ctx); },
                          ))
                      .toList(),
                ),
              ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fèmen'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Enprimant Resi (tèmik)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Resi moman/vant enprime sou enprimant sa a. Chwazi enprimant tèmik ou (egz. Epson TM-T20II) nan lis Windows la.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(labelText: 'Non enprimant resi', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.search), label: const Text('Gade enprimant yo'), onPressed: _list)),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(icon: const Icon(Icons.save), label: const Text('Sove'), onPressed: _save)),
          ]),
        ]),
      ),
    );
  }
}

/// 2èm enprimant: fakti A4 (PDF) pou resi NWIT otèl yo. Separe de enprimant
/// tèmik la (moman → Epson). Itilize CUPS (`lp`) sou Linux, `printing` sou Windows.
class _A4Section extends StatefulWidget {
  const _A4Section();
  @override
  State<_A4Section> createState() => _A4SectionState();
}

class _A4SectionState extends State<_A4Section> {
  final _ctrl = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _ctrl.text = p.getString('printer_a4_name') ?? '';
        _loaded = true;
      });
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('printer_a4_name', _ctrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enprimant A4 sove')));
    }
  }

  Future<void> _listPrinters() async {
    // Motè `printing` — mache sou Windows ak Linux
    final printers = await PrinterService.instance.listSystemPrinters();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enprimant yo'),
        content: printers.isEmpty
            ? const Text('Pa gen enprimant jwenn. Verifye enprimant lan enstale nan sistèm nan.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: printers
                      .map((p) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.print, size: 18),
                            title: Text(p),
                            onTap: () {
                              _ctrl.text = p;
                              Navigator.pop(ctx);
                            },
                          ))
                      .toList(),
                ),
              ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fèmen'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Card(
      color: Colors.indigo.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Icon(Icons.description, size: 18),
            SizedBox(width: 6),
            Text('Enprimant A4 — Fakti Nwit (Otèl)', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          const Text('Resi sejou NWIT yo ap enprime kòm fakti A4 sou enprimant sa a '
              '(moman yo rete sou enprimant tèmik la). Mete non enprimant CUPS la.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(labelText: 'Non enprimant A4 (CUPS)', border: OutlineInputBorder(), hintText: 'HP_LaserJet'),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.search), label: const Text('Gade enprimant yo'), onPressed: _listPrinters)),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(icon: const Icon(Icons.save), label: const Text('Sove'), onPressed: _save)),
          ]),
        ]),
      ),
    );
  }
}

/// Konfigirasyon CUPS: non enprimant sistèm (opsyonèl).
class _CupsSection extends StatefulWidget {
  const _CupsSection();
  @override
  State<_CupsSection> createState() => _CupsSectionState();
}

class _CupsSectionState extends State<_CupsSection> {
  final _ctrl = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _ctrl.text = p.getString('printer_cups_name') ?? '';
        _loaded = true;
      });
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('printer_cups_name', _ctrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enprimant sistèm sove')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Enprimant Sistèm (CUPS)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Voye resi a sou nenpòt enprimant ki enstale nan sistèm nan via « lp -o raw ». '
              'Kite vid pou itilize enprimant default la.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            decoration: const InputDecoration(labelText: 'Non enprimant (opsyonèl)', border: OutlineInputBorder(), hintText: 'EPSON_TM_T20II'),
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton.icon(icon: const Icon(Icons.save), label: const Text('Sove'), onPressed: _save)),
          const SizedBox(height: 8),
          const Text('Mande CUPS aktif epi enprimant lan enstale (lpstat -p pou lis la).',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }
}
