import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:sunmi_printer_plus/column_maker.dart';
import 'package:sunmi_printer_plus/enums.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import 'printer_service.dart';

/// Adapte pou imprimant entegre SUNMI (V1, V2, V2 Pro, T1, T2, etc.).
class SunmiPrinterAdapter {
  SunmiPrinterAdapter._();
  static final SunmiPrinterAdapter instance = SunmiPrinterAdapter._();

  bool? _isSunmiDevice;

  Future<bool> isSunmiDevice() async {
    if (_isSunmiDevice != null) return _isSunmiDevice!;
    if (!Platform.isAndroid) {
      _isSunmiDevice = false;
      return false;
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final manufacturer = info.manufacturer.toLowerCase();
      final brand = info.brand.toLowerCase();
      _isSunmiDevice = manufacturer.contains('sunmi') || brand.contains('sunmi');
    } catch (_) {
      _isSunmiDevice = false;
    }
    return _isSunmiDevice!;
  }

  Future<bool> bindPrinter() async {
    try {
      return (await SunmiPrinter.bindingPrinter()) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> printReceipt(ReceiptData data) async {
    try {
      await bindPrinter();
      await SunmiPrinter.initPrinter();
      await SunmiPrinter.startTransactionPrint(true);

      // Logo (si disponib)
      if (data.logoBytes != null) {
        await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
        await SunmiPrinter.printImage(data.logoBytes!);
        await SunmiPrinter.lineWrap(1);
      }

      // En-tèt
      if (data.businessName != null) {
        await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
        await SunmiPrinter.setFontSize(SunmiFontSize.LG);
        await SunmiPrinter.bold();
        await SunmiPrinter.printText(data.businessName!);
        await SunmiPrinter.resetBold();
        await SunmiPrinter.resetFontSize();
      }

      if (data.businessPhone != null) {
        await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
        await SunmiPrinter.printText('Tel: ${data.businessPhone}');
      }
      if (data.businessAddress != null) {
        await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
        await SunmiPrinter.printText(data.businessAddress!);
      }
      if (data.businessNif != null && data.businessNif!.trim().isNotEmpty) {
        await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
        await SunmiPrinter.printText('NIF: ${data.businessNif}');
      }
      if (data.businessEmail != null && data.businessEmail!.trim().isNotEmpty) {
        await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
        await SunmiPrinter.printText(data.businessEmail!);
      }

      await SunmiPrinter.line();
      await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);

      // Resi # + dat
      await SunmiPrinter.printRow(cols: [
        ColumnMaker(text: 'Resi #${data.saleNumber}', width: 6, align: SunmiPrintAlign.LEFT),
        ColumnMaker(text: _shortDate(data.createdAt.toLocal()), width: 6, align: SunmiPrintAlign.RIGHT),
      ]);

      if (data.customerName != null) {
        await SunmiPrinter.bold();
        await SunmiPrinter.printText('Kliyan: ${data.customerName}');
        await SunmiPrinter.resetBold();
      }
      if (data.cashierName != null) {
        await SunmiPrinter.printText('Sekretè: ${data.cashierName}');
      }

      await SunmiPrinter.line();

      // En-tèt tab
      await SunmiPrinter.bold();
      await SunmiPrinter.printRow(cols: [
        ColumnMaker(text: 'Atik', width: 6, align: SunmiPrintAlign.LEFT),
        ColumnMaker(text: 'Qty', width: 2, align: SunmiPrintAlign.CENTER),
        ColumnMaker(text: 'Total', width: 4, align: SunmiPrintAlign.RIGHT),
      ]);
      await SunmiPrinter.resetBold();
      await SunmiPrinter.line(ch: '-');

      // Atik yo
      for (final item in data.items) {
        await SunmiPrinter.printRow(cols: [
          ColumnMaker(text: item.name, width: 6, align: SunmiPrintAlign.LEFT),
          ColumnMaker(text: item.quantity.toStringAsFixed(item.unitDecimals), width: 2, align: SunmiPrintAlign.CENTER),
          ColumnMaker(text: _money(item.subtotal), width: 4, align: SunmiPrintAlign.RIGHT),
        ]);
      }

      await SunmiPrinter.line();

      // Total
      await SunmiPrinter.printRow(cols: [
        ColumnMaker(text: 'Soustotal', width: 6, align: SunmiPrintAlign.LEFT),
        ColumnMaker(text: _money(data.subtotal), width: 6, align: SunmiPrintAlign.RIGHT),
      ]);
      if (data.discount > 0) {
        await SunmiPrinter.printRow(cols: [
          ColumnMaker(text: 'Rabe', width: 6, align: SunmiPrintAlign.LEFT),
          ColumnMaker(text: '- ${_money(data.discount)}', width: 6, align: SunmiPrintAlign.RIGHT),
        ]);
      }
      if (data.tax > 0) {
        await SunmiPrinter.printRow(cols: [
          ColumnMaker(text: 'TCA', width: 6, align: SunmiPrintAlign.LEFT),
          ColumnMaker(text: _money(data.tax), width: 6, align: SunmiPrintAlign.RIGHT),
        ]);
      }

      await SunmiPrinter.setFontSize(SunmiFontSize.LG);
      await SunmiPrinter.bold();
      await SunmiPrinter.printRow(cols: [
        ColumnMaker(text: 'TOTAL', width: 6, align: SunmiPrintAlign.LEFT),
        ColumnMaker(text: _money(data.total), width: 6, align: SunmiPrintAlign.RIGHT),
      ]);
      await SunmiPrinter.resetBold();
      await SunmiPrinter.resetFontSize();

      await SunmiPrinter.lineWrap(1);

      // Peman
      await SunmiPrinter.printText('Peman: ${data.paymentMethodLabel}');
      if (data.amountReceived != null) {
        await SunmiPrinter.printText('Resi: ${_money(data.amountReceived!)}');
      }
      if (data.changeDue != null && data.changeDue! > 0) {
        await SunmiPrinter.printText('Monnen: ${_money(data.changeDue!)}');
      }

      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.printText(data.footerText ?? 'Mesi paske w achte lakay nou!');
      await SunmiPrinter.lineWrap(3);

      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> printTest({String text = 'WalCash POS - Tes SUNMI'}) async {
    try {
      await bindPrinter();
      await SunmiPrinter.initPrinter();
      await SunmiPrinter.startTransactionPrint(true);
      await SunmiPrinter.setAlignment(SunmiPrintAlign.CENTER);
      await SunmiPrinter.setFontSize(SunmiFontSize.LG);
      await SunmiPrinter.bold();
      await SunmiPrinter.printText(text);
      await SunmiPrinter.resetBold();
      await SunmiPrinter.resetFontSize();
      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cut();
      await SunmiPrinter.exitTransactionPrint(true);
      return true;
    } catch (_) {
      return false;
    }
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
    return '${buf.toString()}.${parts[1]}';
  }

  static String _shortDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}
