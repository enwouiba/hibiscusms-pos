import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/money_formatter.dart';
import 'printer_service.dart';

/// Rann yon `ReceiptData` kòm yon PDF wòl tèmik (80mm) — pou enprime sou
/// Windows via motè `printing` an (kote ESC/POS brit pa disponib).
class ReceiptPdf {
  static String _dt(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  static Future<Uint8List> build(ReceiptData d) async {
    final doc = pw.Document();
    final mono = pw.TextStyle(fontSize: 8.5);
    final bold = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);

    pw.Widget line(String l, String r, {bool b = false}) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.Text(l, style: b ? bold : mono)),
            pw.Text(r, style: b ? bold : mono),
          ],
        );
    final divider = pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Text('--------------------------------', style: mono, maxLines: 1),
    );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80.copyWith(
        marginLeft: 6, marginRight: 6, marginTop: 8, marginBottom: 8),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (d.logoBytes != null)
            pw.Center(child: pw.Image(pw.MemoryImage(d.logoBytes!), width: 70, height: 70)),
          if (d.businessName != null)
            pw.Center(child: pw.Text(d.businessName!, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
          if (d.businessPhone != null) pw.Center(child: pw.Text('Tel: ${d.businessPhone}', style: mono, textAlign: pw.TextAlign.center)),
          if (d.businessAddress != null) pw.Center(child: pw.Text(d.businessAddress!, style: mono, textAlign: pw.TextAlign.center)),
          if (d.businessNif != null && d.businessNif!.trim().isNotEmpty) pw.Center(child: pw.Text('NIF: ${d.businessNif}', style: mono)),
          if (d.businessEmail != null && d.businessEmail!.trim().isNotEmpty) pw.Center(child: pw.Text(d.businessEmail!, style: mono, textAlign: pw.TextAlign.center)),
          if (d.ticketTitle != null)
            pw.Center(child: pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Text(d.ticketTitle!, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)))),
          divider,
          line('${d.numberLabel} #${d.saleNumber}', _dt(d.createdAt)),
          if (d.readyDate != null) pw.Text('Pare: ${_dt(d.readyDate!)}', style: bold),
          if (d.customerName != null && d.customerName!.trim().isNotEmpty) pw.Text('Kliyan: ${d.customerName}', style: bold),
          if (d.customerPhone != null && d.customerPhone!.trim().isNotEmpty) pw.Text('Tel: ${d.customerPhone}', style: mono),
          if (d.customerIdDoc != null && d.customerIdDoc!.trim().isNotEmpty) pw.Text('NIF/CIN: ${d.customerIdDoc}', style: mono),
          divider,
          pw.Row(children: [
            pw.Expanded(flex: 6, child: pw.Text('Atik', style: bold)),
            pw.Expanded(flex: 2, child: pw.Text('Qt', style: bold, textAlign: pw.TextAlign.center)),
            pw.Expanded(flex: 3, child: pw.Text('Total', style: bold, textAlign: pw.TextAlign.right)),
          ]),
          divider,
          for (final i in d.items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 1),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(flex: 6, child: pw.Text(i.name, style: mono)),
                pw.Expanded(flex: 2, child: pw.Text(i.quantity.toStringAsFixed(i.unitDecimals), style: mono, textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 3, child: pw.Text(MoneyFormatter.format(i.subtotal), style: mono, textAlign: pw.TextAlign.right)),
              ]),
            ),
          divider,
          line('Soustotal', MoneyFormatter.format(d.subtotal)),
          if (d.discount > 0) line('Rabè', '- ${MoneyFormatter.format(d.discount)}'),
          if (d.tax > 0) line('TCA', MoneyFormatter.format(d.tax)),
          line('TOTAL', MoneyFormatter.format(d.total), b: true),
          pw.SizedBox(height: 3),
          pw.Text('Peman: ${d.paymentMethodLabel}', style: mono),
          if (d.amountReceived != null) pw.Text('Resi: ${MoneyFormatter.format(d.amountReceived!)}', style: mono),
          if (d.changeDue != null && d.changeDue! > 0) pw.Text('Monnen: ${MoneyFormatter.format(d.changeDue!)}', style: mono),
          if (d.amountDue > 0) line('** DET POU PEYE **', MoneyFormatter.format(d.amountDue), b: true),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text(d.footerText ?? 'Mèsi paske w achte lakay nou!', style: mono, textAlign: pw.TextAlign.center)),
        ],
      ),
    ));
    return doc.save();
  }
}
