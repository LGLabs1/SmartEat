import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/services/sage_briefing_pdf_service.dart';
import 'package:smarteat/widgets/sage_briefing_card.dart';
import 'package:smarteat/widgets/sage_shared_views.dart';

SageBriefingContent _fullBriefing() => SageBriefingContent(
      id: 'test_1',
      title: 'Good morning',
      summary: 'Summary text.',
      periodLabel: 'Morning briefing',
      generatedAt: DateTime(2026, 11, 11, 8, 30),
      recommendation: 'Restock chicken before the lunch rush.',
      businessHealth: 'Fair (72/100)',
      detailText: 'Date: Nov 11, 2026\n'
          'Time: 8:30 AM\n'
          'Yesterday Summary: ₱1,200.00 in sales and revenue increased by 5.0%.\n'
          "Today's Forecast: The forecast points to ₱900 for the next peak window.\n"
          'Business Health: Fair (72/100)\n'
          'Revenue: ₱450.00\n'
          'Orders: 12\n'
          'Best Seller: Chicken Adobo\n'
          'Peak Hours: 12 PM\n'
          'Inventory Alerts: Chicken is running critically low.\n'
          'Recommendations: Restock chicken before the lunch rush.',
      period: 'morning',
    );

Future<void> _open(WidgetTester tester, SageBriefingContent briefing) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showBriefingDetailDialog(context, briefing),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump(); // start dialog route
  await tester.pump(const Duration(milliseconds: 1));
}

/// Opens the dialog in a real dialog route with an injected export callback.
Future<void> _openInjected(
    WidgetTester tester, Future<void> Function() onDownload) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (dialogContext) => Dialog(
                backgroundColor: Colors.transparent,
                child: SageBriefingDetailDialog(
                  briefing: _fullBriefing(),
                  onClose: () => Navigator.of(dialogContext).pop(),
                  onDownloadPdf: onDownload,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump(); // start dialog route
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('full briefing renders highlighted sections without layout '
      'exceptions', (tester) async {
    await _open(tester, _fullBriefing());

    // Unbounded-height stretch rows inside the scroll view used to throw a
    // layout exception here (surfacing later as a mouse_tracker assertion).
    expect(tester.takeException(), isNull);

    expect(find.text('Morning briefing'), findsOneWidget);
    expect(find.text('Fair (72/100)'), findsWidgets);
    expect(find.text('REVENUE'), findsOneWidget);
    expect(find.text('₱450.00'), findsOneWidget);
    expect(find.text('ORDERS'), findsOneWidget);
    expect(find.text('12'), findsWidgets);
    expect(find.text('Chicken Adobo'), findsOneWidget);
    expect(find.text('INVENTORY ALERT'), findsOneWidget);
    expect(find.text('KEY RECOMMENDATION'), findsOneWidget);
    expect(
        find.text('Restock chicken before the lunch rush.'), findsWidgets);
    expect(find.text('Download PDF'), findsOneWidget);
  });

  testWidgets('legacy briefing without parseable fields falls back to raw '
      'text', (tester) async {
    await _open(tester, SageBriefingContent(
      id: 'test_2',
      title: 'Hello',
      summary: 'Fallback summary text.',
      periodLabel: 'Closing briefing',
      generatedAt: DateTime(2026, 11, 10, 20, 0),
      recommendation: '',
      businessHealth: '',
      detailText: 'Just a plain old report with no labels.',
      period: 'evening',
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('Just a plain old report with no labels.'),
        findsOneWidget);
    expect(find.text('KEY RECOMMENDATION'), findsNothing);
    expect(find.text('Download PDF'), findsOneWidget);
  });

  testWidgets('download button generates the PDF and closes the dialog',
      (tester) async {
    var downloadStarted = false;
    await _openInjected(tester, () async {
      downloadStarted = true;
    });
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Download PDF'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(downloadStarted, isTrue);
    // Success pops the dialog and shows the confirmation snackbar.
    expect(find.text('Briefing PDF downloaded.'), findsOneWidget);
    expect(find.text('Morning briefing'), findsNothing);
  });

  testWidgets('download button recovers when the export fails',
      (tester) async {
    await _openInjected(tester, () async => throw Exception('export failed'));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Download PDF'));
    await tester.pump();
    await tester.pumpAndSettle();

    // The dialog stays open, the button is re-enabled and the error shows.
    expect(find.text('Could not generate the PDF.'), findsOneWidget);
    expect(find.text('Download PDF'), findsOneWidget);
  });

  test('PDF build produces a non-empty document', () async {
    final bytes = await SageBriefingPdfService.buildPdf(
      briefing: _fullBriefing(),
    );

    expect(bytes, isNotEmpty);
    // A valid PDF starts with the %PDF header.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('PDF build falls back to raw text for legacy briefings', () async {
    final bytes = await SageBriefingPdfService.buildPdf(
      briefing: SageBriefingContent(
        id: 'test_2',
        title: 'Hello',
        summary: 'Fallback summary text.',
        periodLabel: 'Closing briefing',
        generatedAt: DateTime(2026, 11, 10, 20, 0),
        recommendation: '',
        businessHealth: '',
        detailText: 'Just a plain old report with no labels.',
        period: 'evening',
      ),
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
