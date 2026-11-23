import 'dart:typed_data' show Uint8List;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportPdfSection {
  const ReportPdfSection({required this.title, required this.lines});

  final String title;
  final List<String> lines;
}

class ReportPdfService {
  static Future<void> printReport({
    required String title,
    required String subtitle,
    required String filePrefix,
    required List<ReportPdfSection> sections,
    String? footer,
  }) async {
    await Printing.layoutPdf(
      name: _fileName(filePrefix),
      onLayout: (_) => buildPdf(
        title: title,
        subtitle: subtitle,
        sections: sections,
        footer: footer,
      ),
    );
  }

  static Future<void> shareReport({
    required String title,
    required String subtitle,
    required String filePrefix,
    required List<ReportPdfSection> sections,
    String? footer,
  }) async {
    await Printing.sharePdf(
      bytes: await buildPdf(
        title: title,
        subtitle: subtitle,
        sections: sections,
        footer: footer,
      ),
      filename: _fileName(filePrefix),
    );
  }

  static String _fileName(String filePrefix) {
    final cleaned = filePrefix.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return '${cleaned}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
  }

  static Future<Uint8List> buildPdf({
    required String title,
    required String subtitle,
    required List<ReportPdfSection> sections,
    String? footer,
  }) async {
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

    String display(String value) => regular == null
        ? value.replaceAll('₱', 'PHP ')
        : value;

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            display(title),
            style: pw.TextStyle(
              font: bold,
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            display(subtitle),
            style: pw.TextStyle(font: regular, fontSize: 11),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Generated ${DateFormat('MMM d, yyyy h:mm a').format(DateTime.now())}',
            style: pw.TextStyle(font: regular, fontSize: 9),
          ),
          pw.SizedBox(height: 18),
          for (final section in sections) ...[
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey700, width: 1),
                ),
              ),
              child: pw.Text(
                display(section.title),
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            for (final line in section.lines)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(
                  display(line),
                  style: pw.TextStyle(font: regular, fontSize: 10),
                ),
              ),
            pw.SizedBox(height: 16),
          ],
        ],
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              footer ?? 'SmartEat Report',
              style: pw.TextStyle(font: regular, fontSize: 8),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(font: regular, fontSize: 8),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
