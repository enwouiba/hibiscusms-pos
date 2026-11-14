import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';

class BluetoothPrinterDevice {
  const BluetoothPrinterDevice({required this.name, required this.address});
  final String name;
  final String address;
}

/// Done resi a, dekonekte de model biznis espesifik yo.
class ReceiptData {
  ReceiptData({
    required this.saleNumber,
    required this.createdAt,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paymentMethodLabel,
    this.businessName,
    this.businessPhone,
    this.businessAddress,
    this.businessNif,
    this.businessEmail,
    this.logoPath,
    this.logoBytes,
    this.footerText,
    this.customerName,
    this.customerPhone,
    this.customerIdDoc,
    this.cashierName,
    this.amountReceived,
    this.changeDue,
    this.amountDue = 0,
    this.receiptWidth = 384,
    this.ticketTitle,
    this.numberLabel = 'Resi',
    this.readyDate,
  });

  final int saleNumber;
  final DateTime createdAt;
  final List<ReceiptItem> items;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String paymentMethodLabel;
  final String? businessName;
  final String? businessPhone;
  final String? businessAddress;
  final String? businessNif;
  final String? businessEmail;
  final String? logoPath;
  final Uint8List? logoBytes; // pou logo nan assets/
  final String? footerText;
  final String? customerName;
  final String? customerPhone;
  final String? customerIdDoc; // NIF/CIN kliyan
  final String? cashierName;
  final double? amountReceived;
  final double amountDue;
  final double? changeDue;
  final int receiptWidth;
  final String? ticketTitle; // egz. "TIKÈ REKLAMASYON" pou dry cleaning
  final String numberLabel; // "Resi" oswa "Lòd"
  final DateTime? readyDate; // dat pare pou dry cleaning
}

class ReceiptItem {
  ReceiptItem({
    required this.name,
    required this.quantity,
    required this.subtotal,
    this.unitDecimals = 0,
  });
  final String name;
  final double quantity;
  final double subtotal;
  final int unitDecimals;
}

class PrinterService {
  PrinterService._();
  static final PrinterService instance = PrinterService._();

  /// Netwaye karaktè ki pa kòmpatib ak ESC/POS CP437.
  static String _sanitize(String input) {
    const replacements = <int, int>{
      0x00A0: 0x20,
      0x00E0: 0x61, 0x00E2: 0x61, 0x00E4: 0x61, 0x00E1: 0x61,
      0x00E8: 0x65, 0x00E9: 0x65, 0x00EA: 0x65, 0x00EB: 0x65,
      0x00EC: 0x69, 0x00EE: 0x69, 0x00EF: 0x69, 0x00ED: 0x69,
      0x00F2: 0x6F, 0x00F4: 0x6F, 0x00F6: 0x6F, 0x00F3: 0x6F,
      0x00F9: 0x75, 0x00FB: 0x75, 0x00FC: 0x75, 0x00FA: 0x75,
      0x00E7: 0x63, 0x00F1: 0x6E,
      0x00C0: 0x41, 0x00C2: 0x41, 0x00C4: 0x41, 0x00C1: 0x41,
      0x00C8: 0x45, 0x00C9: 0x45, 0x00CA: 0x45, 0x00CB: 0x45,
      0x00CC: 0x49, 0x00CE: 0x49, 0x00CF: 0x49, 0x00CD: 0x49,
      0x00D2: 0x4F, 0x00D4: 0x4F, 0x00D6: 0x4F, 0x00D3: 0x4F,
      0x00D9: 0x55, 0x00DB: 0x55, 0x00DC: 0x55, 0x00DA: 0x55,
      0x00C7: 0x43, 0x00D1: 0x4E,
    };
    final out = StringBuffer();
    for (final c in input.codeUnits) {
      if (replacements.containsKey(c)) {
        out.writeCharCode(replacements[c]!);
      } else if (c == 10 || c == 13 || (c >= 32 && c <= 126)) {
        out.writeCharCode(c);
      }
    }
    return out.toString();
  }

  static String _money(double v) {
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '\$${buf.toString()}.${parts[1]}';
  }

  static String _shortDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<bool> isBluetoothEnabled() async {
    return PrintBluetoothThermal.bluetoothEnabled;
  }

  Future<List<BluetoothPrinterDevice>> pairedDevices() async {
    final list = await PrintBluetoothThermal.pairedBluetooths;
    return list
        .map((d) => BluetoothPrinterDevice(name: d.name, address: d.macAdress))
        .toList();
  }

  Future<bool> isConnected() async {
    return PrintBluetoothThermal.connectionStatus;
  }

  Future<bool> connect(String macAddress) async {
    final connected = await PrintBluetoothThermal.connectionStatus;
    if (connected) {
      await PrintBluetoothThermal.disconnect;
    }
    return PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }

  Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
  }

  /// Byte ESC/POS yon tès senp (san voye yo).
  Future<List<int>> buildTestBytes({String text = 'WalCash POS - Tès enprime'}) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];
    bytes.addAll(generator.text(
      text,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
      ),
    ));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }

  Future<bool> printTest({String text = 'WalCash POS - Tès enprime'}) async {
    if (!await isConnected()) return false;
    return PrintBluetoothThermal.writeBytes(await buildTestBytes(text: text));
  }

  /// Bati byte ESC/POS resi a SAN voye yo — konsa nenpòt transpò
  /// (Bluetooth, USB, rezo, CUPS) ka sèvi ak menm resi a.
  Future<List<int>> buildReceiptBytes(ReceiptData data) async {
    final profile = await CapabilityProfile.load();
    final paperSize = data.receiptWidth >= 576 ? PaperSize.mm80 : PaperSize.mm58;
    final gen = Generator(paperSize, profile);
    final bytes = <int>[];

    // Logo: priyorite bytes (asset) sou path (fichye)
    Uint8List? rawLogo;
    if (data.logoBytes != null) {
      rawLogo = data.logoBytes;
    } else if (data.logoPath != null) {
      try {
        rawLogo = await File(data.logoPath!).readAsBytes();
      } catch (_) {}
    }
    if (rawLogo != null) {
      try {
        final decoded = img.decodeImage(rawLogo);
        if (decoded != null) {
          final maxWidth = paperSize == PaperSize.mm80 ? 360 : 240;
          final resized = img.copyResize(
            decoded,
            width: decoded.width > maxWidth ? maxWidth : decoded.width,
          );
          bytes.addAll(gen.image(resized, align: PosAlign.center));
        }
      } catch (_) {}
    }

    if (data.businessName != null) {
      bytes.addAll(gen.text(
        _sanitize(data.businessName!),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ));
    }

    if (data.businessPhone != null) {
      bytes.addAll(gen.text(
        _sanitize('Tel: ${data.businessPhone}'),
        styles: const PosStyles(align: PosAlign.center),
      ));
    }
    if (data.businessAddress != null) {
      bytes.addAll(gen.text(
        _sanitize(data.businessAddress!),
        styles: const PosStyles(align: PosAlign.center),
      ));
    }
    if (data.businessNif != null && data.businessNif!.trim().isNotEmpty) {
      bytes.addAll(gen.text(
        _sanitize('NIF: ${data.businessNif}'),
        styles: const PosStyles(align: PosAlign.center),
      ));
    }
    if (data.businessEmail != null && data.businessEmail!.trim().isNotEmpty) {
      bytes.addAll(gen.text(
        _sanitize(data.businessEmail!),
        styles: const PosStyles(align: PosAlign.center),
      ));
    }

    if (data.ticketTitle != null) {
      bytes.addAll(gen.text(
        _sanitize(data.ticketTitle!),
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2),
      ));
    }

    bytes.addAll(gen.hr());
    bytes.addAll(gen.row([
      PosColumn(text: '${data.numberLabel} #${data.saleNumber}', width: 6),
      PosColumn(
        text: _shortDate(data.createdAt.toLocal()),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]));
    if (data.readyDate != null) {
      bytes.addAll(gen.text(
        _sanitize('Pare: ${_shortDate(data.readyDate!.toLocal())}'),
        styles: const PosStyles(bold: true),
      ));
    }
    if (data.customerName != null && data.customerName!.trim().isNotEmpty) {
      bytes.addAll(gen.text(
        _sanitize('Kliyan: ${data.customerName}'),
        styles: const PosStyles(bold: true),
      ));
    }
    if (data.customerPhone != null && data.customerPhone!.trim().isNotEmpty) {
      bytes.addAll(gen.text(_sanitize('Tel: ${data.customerPhone}')));
    }
    if (data.customerIdDoc != null && data.customerIdDoc!.trim().isNotEmpty) {
      bytes.addAll(gen.text(_sanitize('NIF/CIN: ${data.customerIdDoc}')));
    }
    if (data.cashierName != null) {
      bytes.addAll(gen.text(_sanitize('Sekretè: ${data.cashierName}')));
    }
    bytes.addAll(gen.hr());

    bytes.addAll(gen.row([
      PosColumn(text: 'Atik', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: 'Qty', width: 2, styles: const PosStyles(bold: true, align: PosAlign.center)),
      PosColumn(text: 'Total', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]));
    bytes.addAll(gen.hr(ch: '-'));

    for (final i in data.items) {
      bytes.addAll(gen.row([
        PosColumn(text: _sanitize(i.name), width: 6),
        PosColumn(
          text: i.quantity.toStringAsFixed(i.unitDecimals),
          width: 2,
          styles: const PosStyles(align: PosAlign.center),
        ),
        PosColumn(
          text: _sanitize(_money(i.subtotal)),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
    }

    bytes.addAll(gen.hr());
    bytes.addAll(gen.row([
      PosColumn(text: 'Soustotal', width: 6),
      PosColumn(
        text: _sanitize(_money(data.subtotal)),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]));
    if (data.discount > 0) {
      bytes.addAll(gen.row([
        PosColumn(text: _sanitize('Rabè'), width: 6),
        PosColumn(
          text: '- ${_sanitize(_money(data.discount))}',
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
    }
    if (data.tax > 0) {
      bytes.addAll(gen.row([
        PosColumn(text: 'TCA', width: 6),
        PosColumn(
          text: _sanitize(_money(data.tax)),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
    }
    bytes.addAll(gen.row([
      PosColumn(
        text: 'TOTAL',
        width: 6,
        styles: const PosStyles(bold: true, height: PosTextSize.size2),
      ),
      PosColumn(
        text: _sanitize(_money(data.total)),
        width: 6,
        styles: const PosStyles(bold: true, align: PosAlign.right, height: PosTextSize.size2),
      ),
    ]));

    bytes.addAll(gen.feed(1));
    bytes.addAll(gen.text(_sanitize('Peman: ${data.paymentMethodLabel}')));
    if (data.amountReceived != null) {
      bytes.addAll(gen.text('Resi: ${_sanitize(_money(data.amountReceived!))}'));
    }
    if (data.changeDue != null && data.changeDue! > 0) {
      bytes.addAll(gen.text('Monnen: ${_sanitize(_money(data.changeDue!))}'));
    }
    if (data.amountDue > 0) {
      bytes.addAll(gen.feed(1));
      bytes.addAll(gen.row([
        PosColumn(text: '** DET POU PEYE **', width: 7, styles: const PosStyles(bold: true)),
        PosColumn(text: _sanitize(_money(data.amountDue)), width: 5, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]));
    }

    bytes.addAll(gen.feed(1));
    bytes.addAll(gen.text(
      _sanitize(data.footerText ?? 'Mèsi paske w achte lakay nou!'),
      styles: const PosStyles(align: PosAlign.center),
    ));

    bytes.addAll(gen.feed(2));
    bytes.addAll(gen.cut());

    return bytes;
  }

  /// Enprime resi sou Bluetooth (transpò defo pou telefòn).
  Future<bool> printReceipt(ReceiptData data) async {
    if (!await isConnected()) return false;
    return PrintBluetoothThermal.writeBytes(await buildReceiptBytes(data));
  }

  // ─────────── Transpò pou NENPÒT enprimant (sitou desktop) ───────────

  /// Ekri byte brit dirèk sou yon aparèy — egz. enprimant USB sou Linux
  /// (`/dev/usb/lp0`). Se fason ki pi senp pou Epson TM-T20II USB la.
  Future<bool> printBytesDevice(List<int> bytes, String devicePath) async {
    try {
      final raf = await File(devicePath).open(mode: FileMode.writeOnly);
      await raf.writeFrom(bytes);
      await raf.flush();
      await raf.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Voye byte sou yon enprimant rezo (ESC/POS, pò 9100 pa defo).
  Future<bool> printBytesNetwork(List<int> bytes, String host, int port) async {
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 6));
      socket.add(bytes);
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Voye byte brit sou yon enprimant SISTÈM via CUPS (`lp -o raw`).
  /// Sa a mache pou NENPÒT enprimant ki enstale nan sistèm nan
  /// (USB, rezo, elatriye). `printerName` vid = enprimant default la.
  Future<bool> printBytesCups(List<int> bytes, {String? printerName}) async {
    try {
      final args = <String>['-o', 'raw'];
      if (printerName != null && printerName.trim().isNotEmpty) {
        args.insertAll(0, ['-d', printerName.trim()]);
      }
      final proc = await Process.start('lp', args);
      proc.stdin.add(bytes);
      await proc.stdin.flush();
      await proc.stdin.close();
      return (await proc.exitCode) == 0;
    } catch (_) {
      return false;
    }
  }

  // ───────── Motè `printing` milti-platfòm (Windows + Linux + macOS) ─────────

  /// Lis non enprimant ki enstale nan sistèm nan (mache sou Windows tou).
  Future<List<String>> listSystemPrinters() async {
    try {
      final printers = await Printing.listPrinters();
      return printers.map((p) => p.name).where((n) => n.trim().isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Voye yon PDF sou yon enprimant sistèm via motè `printing` an. Si
  /// `printerName` vid oswa pa jwenn, li itilize enprimant default la.
  Future<bool> printPdfViaPrinting(List<int> pdfBytes, {String? printerName}) async {
    try {
      final bytes = Uint8List.fromList(pdfBytes);
      final printers = await Printing.listPrinters();
      Printer? target;
      if (printerName != null && printerName.trim().isNotEmpty) {
        for (final p in printers) {
          if (p.name.trim().toLowerCase() == printerName.trim().toLowerCase()) {
            target = p;
            break;
          }
        }
      }
      target ??= printers.where((p) => p.isDefault).cast<Printer?>().firstWhere((_) => true, orElse: () => null);
      target ??= printers.isNotEmpty ? printers.first : null;
      if (target == null) return false;
      return await Printing.directPrintPdf(printer: target, onLayout: (_) async => bytes);
    } catch (_) {
      return false;
    }
  }

  /// Enprime yon PDF (fakti/pofoma A4) sou NENPÒT platfòm, san janm echwe an silans.
  ///
  /// • Sou òdinatè (Windows/Linux/macOS): eseye voye dirèk sou enprimant A4 ki
  ///   chwazi a (`printerName`). Si sa echwe (non pa jwenn, enprimant pa reponn),
  ///   li louvri dyalòg enprime sistèm nan pou itilizatè a ka chwazi enprimant lan.
  /// • Sou telefòn/tablèt (Android/iOS): `lp` pa egziste — nou louvri dyalòg
  ///   enprime Android la (itilizatè chwazi nenpòt enprimant: Wi-Fi, sove, elatriye).
  ///
  /// Konsa pofoma/fakti A4 la TOUJOU rive sou yon enprimant, menm si enprimant
  /// tèmik « moman » an se sèl ki konfigire.
  Future<bool> printPdfSmart(List<int> pdfBytes, {String? printerName, String jobName = 'Dokiman'}) async {
    final bytes = Uint8List.fromList(pdfBytes);
    bool isDesktop = false;
    try {
      isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {}
    try {
      if (isDesktop) {
        final ok = await printPdfViaPrinting(bytes, printerName: printerName);
        if (ok) return true;
        // Fallback: dyalòg sistèm (itilizatè chwazi enprimant A4 la)
        return await Printing.layoutPdf(onLayout: (_) async => bytes, name: jobName);
      }
      // Mobil: dyalòg enprime sistèm nan
      return await Printing.layoutPdf(onLayout: (_) async => bytes, name: jobName);
    } catch (_) {
      // Dènye rekou: toujou eseye dyalòg la
      try {
        return await Printing.layoutPdf(onLayout: (_) async => bytes, name: jobName);
      } catch (_) {
        return false;
      }
    }
  }

  /// Enprime yon PDF (fakti A4) sou yon enprimant sistèm via CUPS.
  /// Pou resi NWIT otèl yo sou yon enprimant papye A4 regilye.
  /// `printerName` vid = enprimant default la.
  Future<bool> printPdfCups(List<int> pdfBytes, {String? printerName}) async {
    try {
      final tmp = File('${Directory.systemTemp.path}/hibiscus_fakti_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await tmp.writeAsBytes(pdfBytes, flush: true);
      final args = <String>[];
      if (printerName != null && printerName.trim().isNotEmpty) {
        args.addAll(['-d', printerName.trim()]);
      }
      args.add(tmp.path);
      final proc = await Process.run('lp', args);
      // lp kopye fichye a nan spool la, donk nou ka efase l kounye a.
      try { await tmp.delete(); } catch (_) {}
      return proc.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
