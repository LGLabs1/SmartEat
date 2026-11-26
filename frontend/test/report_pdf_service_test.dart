import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/finance/data/report_period.dart';
import 'package:smarteat/services/report_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a finance report PDF with unicode report content', () async {
    final bytes = await ReportPdfService.buildPdf(
      title: 'Financial Report',
      subtitle: 'November 2026',
      sections: [
        ReportPdfSection(
          title: 'November 2026 summary',
          lines: const [
            'Revenue: ₱12,450.00',
            'COGS source: Weighted average — inventory',
            'Net profit: ₱3,120.00',
          ],
        ),
        const ReportPdfSection(
          title: 'Expenses by category',
          lines: ['Ingredients: ₱4,200.00', 'Delivery: ₱310.00'],
        ),
      ],
      footer: 'SmartEat Financial Reports',
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('builds a PDF for a selected report month', () async {
    final month = DateTime(2026, 10, 15);
    final bytes = await ReportPdfService.buildPdf(
      title: 'Financial Report',
      subtitle: ReportPeriod.label(month),
      sections: [
        ReportPdfSection(
          title: '${ReportPeriod.label(month)} summary',
          lines: const ['Net sales: ₱1,000.00'],
        ),
      ],
      footer: 'SmartEat Financial Reports',
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
