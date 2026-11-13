import 'dart:typed_data' show Uint8List;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/purchase_list_item.dart';

/// Builds and exports the Purchase List as a PDF matching the SmartEat layout:
///
///   SMARTEAT
///   Purchase List
///   Date: October 18, 2026
///
///   [ ] Chicken Breast    15 kg
///   [x] Rice              30 kg
///
///   Estimated Cost: ₱5,250
class PurchaseListPdfService {
  /// Exports [list] to a PDF and opens the share/save sheet.
  ///
  /// [totalCost] is shown as the "Estimated Cost" footer.
  static Future<void> export({
    required List<PurchaseListItem> list,
    required double totalCost,
  }) async {
    final bytes = await buildPdf(list: list, totalCost: totalCost);
    await Printing.sharePdf(
      bytes: bytes,
      filename: _fileName(),
    );
  }

  static String _fileName() {
    final d = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return 'purchase_list_$d.pdf';
  }

  static Future<Uint8List> buildPdf({
    required List<PurchaseListItem> list,
    required double totalCost,
  }) async {
    final doc = pw.Document();

    // Load the bundled Unicode-capable font so the ₱ (U+20B1) glyph renders.
    // Falls back to the default (Helvetica) font if the asset is unavailable.
    pw.Font? regular;
    pw.Font? bold;
    try {
      final r = await rootBundle.load('assets/fonts/arial.ttf');
      final b = await rootBundle.load('assets/fonts/arialbd.ttf');
      regular = pw.Font.ttf(r);
      bold = pw.Font.ttf(b);
    } catch (_) {
      regular = null;
      bold = null;
    }

    // The default PDF fonts are Latin-1 and cannot draw ₱. When we could not
    // load a Unicode font, use a safe "PHP " prefix instead of the ₱ symbol.
    final peso = regular != null ? '₱' : 'PHP ';
    String money(double v) {
      final formatted = NumberFormat.currency(
        symbol: peso,
        decimalDigits: v == v.roundToDouble() ? 0 : 2,
      ).format(v);
      return formatted;
    }

    final dateStr = DateFormat('MMMM d, yyyy').format(DateTime.now());

    pw.Widget checkbox(bool checked) {
      return pw.CustomPaint(
        size: const PdfPoint(11, 11),
        painter: (canvas, size) {
          canvas
            ..setStrokeColor(PdfColors.black)
            ..setLineWidth(1)
            ..moveTo(0, 0)
            ..lineTo(size.x, 0)
            ..lineTo(size.x, size.y)
            ..lineTo(0, size.y)
            ..closePath()
            ..strokePath();
          if (checked) {
            canvas
              ..setLineWidth(1.5)
              ..moveTo(2.5, 5.5)
              ..lineTo(4.5, 8)
              ..lineTo(8.5, 2.5)
              ..strokePath();
          }
        },
      );
    }

    pw.Widget line(PurchaseListItem e) {
      final qty = e.qty % 1 == 0 ? e.qty.toInt().toString() : e.qty.toString();
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            checkbox(e.checked),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                e.name,
                style: pw.TextStyle(
                  font: regular,
                  fontSize: 12,
                  decoration: e.checked ? pw.TextDecoration.lineThrough : null,
                ),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              '$qty ${e.unit}',
              style: pw.TextStyle(font: regular, fontSize: 12),
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        theme: pw.ThemeData.withFont(
          base: regular,
          bold: bold,
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'SMARTEAT',
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 24,
                    letterSpacing: 2,
                  ),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'Purchase List',
                  style: pw.TextStyle(font: regular, fontSize: 14),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'Date: $dateStr',
                  style: pw.TextStyle(font: regular, fontSize: 11),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Divider(color: PdfColors.grey600),
              pw.SizedBox(height: 8),
              if (list.isEmpty)
                pw.Center(
                  child: pw.Text(
                    'No items in the list.',
                    style: pw.TextStyle(font: regular, fontSize: 12),
                  ),
                )
              else
                ...list.map(line),
              pw.SizedBox(height: 12),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Estimated Cost: ${money(totalCost)}',
                  style: pw.TextStyle(font: bold, fontSize: 14),
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
