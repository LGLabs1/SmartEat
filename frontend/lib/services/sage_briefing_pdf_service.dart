import 'dart:typed_data' show Uint8List;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../widgets/sage_briefing_card.dart';
import 'briefing_history.dart';

/// Builds and exports a single Sage briefing as a PDF report.
///
/// Mirrors the on-screen briefing dialog: header with period + business
/// health, a metric grid, yesterday/forecast blocks, an inventory alert box
/// and the key recommendation callout. Light, printable styling so it reads
/// well on paper and on screen.
class SageBriefingPdfService {
  /// Builds the PDF and hands it to the platform: a browser download on web,
  /// a share sheet on mobile.
  static Future<void> export({required SageBriefingContent briefing}) async {
    final bytes = await buildPdf(briefing: briefing);
    await Printing.sharePdf(
      bytes: bytes,
      filename: _fileName(briefing),
    );
  }

  static String _fileName(SageBriefingContent briefing) {
    final d = DateFormat('yyyy-MM-dd').format(briefing.generatedAt);
    final period = briefing.period.isEmpty ? 'report' : briefing.period;
    return 'sage_briefing_${d}_$period.pdf';
  }

  static Future<Uint8List> buildPdf({
    required SageBriefingContent briefing,
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
    // The peso amounts arrive already formatted inside detailText, so the
    // fallback prefix has to be swapped there instead.
    String sanitize(String text) {
      if (regular != null || !text.contains('₱')) return text;
      return text.replaceAll('₱', 'PHP ');
    }

    final fields = parseBriefingDetail(briefing.detailText);
    final hasStructured = fields.length >= 3;
    final healthLabel = fields['Business Health'] ?? briefing.businessHealth;
    final healthScore = healthScoreFromLabel(healthLabel);

    final generated = fields['Date'] != null && fields['Time'] != null
        ? '${fields['Date']} • ${fields['Time']}'
        : DateFormat('MMM d, yyyy • h:mm a').format(briefing.generatedAt);

    pw.TextStyle style(double size,
            {bool isBold = false, PdfColor? color, double? height}) =>
        pw.TextStyle(
          font: isBold ? (bold ?? regular) : regular,
          fontSize: size,
          color: color ?? PdfColors.black,
          height: height,
        );

    // Light background tint derived from [c]: white with a hint of the color.
    PdfColor _tint(PdfColor c, [double amount = 0.08]) => PdfColor(
          c.red * amount + (1 - amount),
          c.green * amount + (1 - amount),
          c.blue * amount + (1 - amount),
        );

    // Section with a small caps heading and a colored left accent bar.
    pw.Widget section(String heading, String body, PdfColor accent) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            left: pw.BorderSide(color: accent, width: 3),
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              heading,
              style: pw.TextStyle(
                font: bold ?? regular,
                fontSize: 9,
                color: accent,
                letterSpacing: 1,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              sanitize(body),
              style: style(11, color: PdfColors.blueGrey800, height: 1.4),
            ),
          ],
        ),
      );
    }

    // Highlighted box for the alert / the recommendation.
    pw.Widget callout(String heading, String body, PdfColor color) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 1),
          color: _tint(color),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              heading,
              style: pw.TextStyle(
                font: bold ?? regular,
                fontSize: 9,
                color: color,
                letterSpacing: 1,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              sanitize(body),
              style: pw.TextStyle(
                font: bold ?? regular,
                fontSize: 11,
                color: PdfColors.blueGrey900,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget metricCell(String label, String value, PdfColor color) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _tint(color, 0.35), width: 0.8),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                font: bold ?? regular,
                fontSize: 8,
                color: PdfColors.grey600,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              sanitize(value),
              style: pw.TextStyle(
                font: bold ?? regular,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    final metrics = <(String, String, PdfColor)>[
      if (fields['Revenue'] != null)
        ('Revenue', fields['Revenue']!, PdfColors.green700),
      if (fields['Orders'] != null)
        ('Orders', fields['Orders']!, PdfColors.blue700),
      if (fields['Best Seller'] != null)
        ('Best Seller', fields['Best Seller']!, PdfColors.amber800),
      if (fields['Peak Hours'] != null)
        ('Peak Hours', fields['Peak Hours']!, PdfColors.purple700),
    ];

    final healthColor = switch (healthScore) {
      null => PdfColors.blue700,
      >= 80 => PdfColors.green700,
      >= 60 => PdfColors.lightGreen800,
      >= 40 => PdfColors.orange700,
      _ => PdfColors.red700,
    };

    final periodText = briefing.periodLabel.isNotEmpty
        ? briefing.periodLabel
        : '${briefingPeriodShortLabel(briefing.period)} briefing';
    final recommendation =
        fields['Recommendations'] ?? briefing.recommendation;

    final body = <pw.Widget>[
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
        child: pw.Text('Sage $periodText', style: style(14, isBold: true)),
      ),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text('Generated: $generated', style: style(11)),
      ),
      if (healthLabel.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(
            'Business Health: ${sanitize(healthLabel)}',
            style: pw.TextStyle(
              font: bold ?? regular,
              fontSize: 11,
              color: healthColor,
            ),
          ),
        ),
      ],
      pw.SizedBox(height: 14),
      pw.Divider(color: PdfColors.grey600),
      pw.SizedBox(height: 12),
      if (hasStructured) ...[
        if (metrics.isNotEmpty)
          pw.Table(
            border: null,
            children: [
              for (var i = 0; i < metrics.length; i += 2)
                pw.TableRow(
                  children: [
                    pw.Expanded(
                      child: pw.Padding(
                        padding:
                            const pw.EdgeInsets.only(right: 6, bottom: 6),
                        child: metricCell(
                            metrics[i].$1, metrics[i].$2, metrics[i].$3),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Padding(
                        padding:
                            const pw.EdgeInsets.only(left: 6, bottom: 6),
                        child: i + 1 < metrics.length
                            ? metricCell(metrics[i + 1].$1,
                                metrics[i + 1].$2, metrics[i + 1].$3)
                            : pw.SizedBox(),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        if (fields['Yesterday Summary'] != null)
          section('YESTERDAY', fields['Yesterday Summary']!,
              PdfColors.blueGrey500),
        if (fields["Today's Forecast"] != null)
          section("TODAY'S FORECAST", fields["Today's Forecast"]!,
              PdfColors.teal600),
        if (fields['Inventory Alerts'] != null)
          callout('INVENTORY ALERT', fields['Inventory Alerts']!,
              PdfColors.red600),
        if (recommendation.isNotEmpty)
          callout('KEY RECOMMENDATION', recommendation, PdfColors.green700),
      ] else
        // Legacy briefing without parseable fields — dump the stored text.
        pw.Paragraph(
          text: sanitize(
            briefing.detailText.trim().isNotEmpty
                ? briefing.detailText
                : briefing.summary,
          ),
          style: style(11, height: 1.5),
        ),
      pw.SizedBox(height: 16),
      pw.Divider(color: PdfColors.grey400),
      pw.SizedBox(height: 6),
      pw.Text(
        'Generated by Sage • SmartEat',
        style: style(9, color: PdfColors.grey600),
      ),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        maxPages: 6,
        theme: pw.ThemeData.withFont(
          base: regular,
          bold: bold,
        ),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Sage Briefing Report',
                style: style(8, color: PdfColors.grey500),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: style(8, color: PdfColors.grey500),
              ),
            ],
          ),
        ),
        build: (context) => body,
      ),
    );

    return doc.save();
  }
}
