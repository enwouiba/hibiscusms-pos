import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/money_formatter.dart';

/// Done pou yon fakti A4 (resi sejou nwit otèl).
class InvoiceData {
  final String businessName;
  final String? businessAddress;
  final String? businessPhone;
  final String? businessNif;
  final String? businessEmail;
  final Uint8List? logoBytes;

  final int number;
  final DateTime createdAt;
  final DateTime? checkOutAt;

  final String? guestName;
  final String? guestPhone;
  final String? guestIdDoc;

  final String roomName;
  final String modeLabel; // "Pa nwit"
  final String unitLabel; // "nwit"
  final int duration;
  final double rate;
  final double roomCharge;
  final double extra;
  final double discount;
  final double total;
  final double amountPaid;
  final double amountDue;
  final String? footerText;
  final bool isProforma; // true = POFOMA (devi), false = FAKTI

  const InvoiceData({
    required this.businessName,
    this.businessAddress,
    this.businessPhone,
    this.businessNif,
    this.businessEmail,
    this.logoBytes,
    required this.number,
    required this.createdAt,
    this.checkOutAt,
    this.guestName,
    this.guestPhone,
    this.guestIdDoc,
    required this.roomName,
    required this.modeLabel,
    required this.unitLabel,
    required this.duration,
    required this.rate,
    required this.roomCharge,
    this.extra = 0,
    this.discount = 0,
    required this.total,
    this.amountPaid = 0,
    this.amountDue = 0,
    this.footerText,
    this.isProforma = false,
  });
}

/// Jenere yon fakti A4 an PDF pou yon sejou otèl.
class InvoicePdf {
  static String _d(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  static Future<Uint8List> build(InvoiceData d) async {
    final doc = pw.Document();
    final accent = PdfColor.fromInt(0xFF0D9488);
    final grey = PdfColors.grey700;

    pw.Widget kv(String k, String v, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(k, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(v, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ]),
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Antèt
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                if (d.logoBytes != null) ...[
                  pw.Image(pw.MemoryImage(d.logoBytes!), width: 54, height: 54),
                  pw.SizedBox(width: 12),
                ],
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(d.businessName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  if (d.businessAddress != null) pw.Text(d.businessAddress!, style: pw.TextStyle(color: grey, fontSize: 10)),
                  if (d.businessPhone != null) pw.Text('Tel: ${d.businessPhone}', style: pw.TextStyle(color: grey, fontSize: 10)),
                  if (d.businessNif != null && d.businessNif!.isNotEmpty) pw.Text('NIF: ${d.businessNif}', style: pw.TextStyle(color: grey, fontSize: 10)),
                  if (d.businessEmail != null && d.businessEmail!.isNotEmpty) pw.Text(d.businessEmail!, style: pw.TextStyle(color: grey, fontSize: 10)),
                ]),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(d.isProforma ? 'POFOMA' : 'FAKTI',
                    style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold,
                        color: d.isProforma ? PdfColors.orange800 : accent)),
                if (d.isProforma)
                  pw.Text('Devi — pa yon fakti definitif', style: pw.TextStyle(color: grey, fontSize: 9)),
                pw.Text('No ${d.number}', style: const pw.TextStyle(fontSize: 12)),
                pw.Text(_d(d.createdAt), style: pw.TextStyle(color: grey, fontSize: 10)),
              ]),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Divider(color: accent, thickness: 1.5),
          pw.SizedBox(height: 10),
          // Kliyan
          pw.Text('KLIYAN', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: accent)),
          pw.SizedBox(height: 4),
          if (d.guestName != null && d.guestName!.isNotEmpty) pw.Text('Non: ${d.guestName}'),
          if (d.guestPhone != null && d.guestPhone!.isNotEmpty) pw.Text('Telefòn: ${d.guestPhone}'),
          if (d.guestIdDoc != null && d.guestIdDoc!.isNotEmpty) pw.Text('NIF/CIN: ${d.guestIdDoc}'),
          pw.SizedBox(height: 16),
          // Tablo detay
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(5),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('Deskripsyon', bold: true),
                  _cell('Kantite', bold: true, align: pw.TextAlign.center),
                  _cell('Pri inite', bold: true, align: pw.TextAlign.right),
                  _cell('Total', bold: true, align: pw.TextAlign.right),
                ],
              ),
              pw.TableRow(children: [
                _cell('Chanm ${d.roomName} (${d.modeLabel})'),
                _cell('${d.duration} ${d.unitLabel}', align: pw.TextAlign.center),
                _cell(MoneyFormatter.format(d.rate), align: pw.TextAlign.right),
                _cell(MoneyFormatter.format(d.roomCharge), align: pw.TextAlign.right),
              ]),
              if (d.extra > 0)
                pw.TableRow(children: [
                  _cell('Chaj anplis'),
                  _cell('1', align: pw.TextAlign.center),
                  _cell(MoneyFormatter.format(d.extra), align: pw.TextAlign.right),
                  _cell(MoneyFormatter.format(d.extra), align: pw.TextAlign.right),
                ]),
            ],
          ),
          pw.SizedBox(height: 12),
          // Total yo
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 240,
              child: pw.Column(children: [
                kv('Soustotal', MoneyFormatter.format(d.roomCharge + d.extra)),
                if (d.discount > 0) kv('Rabè', '- ${MoneyFormatter.format(d.discount)}'),
                pw.Divider(),
                kv('TOTAL', MoneyFormatter.format(d.total), bold: true),
                kv('Peye', MoneyFormatter.format(d.amountPaid)),
                if (d.amountDue > 0) kv('Dèt pou peye', MoneyFormatter.format(d.amountDue), bold: true),
              ]),
            ),
          ),
          pw.Spacer(),
          pw.Divider(color: PdfColors.grey400),
          pw.Center(child: pw.Text(d.footerText ?? 'Mèsi pou vizit ou!', style: pw.TextStyle(color: grey))),
          if (d.checkOutAt != null)
            pw.Center(child: pw.Text('Check-out: ${_d(d.checkOutAt!)}', style: pw.TextStyle(color: grey, fontSize: 9))),
        ],
      ),
    ));
    return doc.save();
  }

  static pw.Widget _cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text, textAlign: align, style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 10)),
      );
}
