import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/finance/data/finance_format.dart';
import 'package:smarteat/features/finance/presentation/widgets/reports_tab.dart';
import 'package:smarteat/features/finance/presentation/widgets/staff_payment_history_dialog.dart';
import 'package:smarteat/features/inventory/presentation/screens/reports_screen.dart';

void main() {
  testWidgets('finance reports exposes only Bluetooth print and PDF download',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FinanceReportsTab(
          expenses: const [],
          payables: const [],
          fmt: FinanceFormat('₱'),
          onEditBudgets: () {},
        ),
      ),
    ));

    await tester.scrollUntilVisible(
      find.byKey(const Key('finance-bluetooth-print-button')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Print PDF via Bluetooth printer'), findsOneWidget);
    expect(find.text('Download PDF'), findsOneWidget);
    expect(find.text('Print PDF'), findsNothing);
    expect(find.text('Share PDF'), findsNothing);
    expect(find.textContaining('Export'), findsNothing);
  });

  testWidgets('finance reports marks missing costing labels red',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FinanceReportsTab(
          expenses: const [],
          payables: const [],
          itemPerformance: [
            {
              'name': 'Uncosted Item',
              'revenue': 100.0,
              'quantitySold': 2,
            },
          ],
          fmt: FinanceFormat('₱'),
          onEditBudgets: () {},
        ),
      ),
    ));

    await tester.scrollUntilVisible(
      find.text('N/A'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    final na = find.text('N/A');
    expect(na, findsOneWidget);
    final errorColor = Theme.of(tester.element(na)).colorScheme.error;
    expect(tester.widget<Text>(na).style?.color, errorColor);

    final missing = find.textContaining('Costing missing');
    expect(missing, findsOneWidget);
    expect(tester.widget<Text>(missing).style?.color, errorColor);
  });

  testWidgets('inventory reports exposes only Bluetooth print and PDF download',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ReportsScreen(items: [], movements: [], showAppBar: false),
    ));

    await tester.scrollUntilVisible(
      find.byKey(const Key('inventory-bluetooth-print-button')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Print PDF via Bluetooth printer'), findsOneWidget);
    expect(find.text('Download PDF'), findsOneWidget);
    expect(find.text('Print PDF'), findsNothing);
    expect(find.text('Share PDF'), findsNothing);
    expect(find.text('Print to Bluetooth Printer'), findsNothing);
  });

  testWidgets('staff payment history dialog identifies the selected staff',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => StaffPaymentHistoryDialog(
                eateryId: null,
                uid: 'staff-1',
                name: 'Ana Reyes',
                fmt: FinanceFormat('₱'),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Payment History'), findsOneWidget);
    expect(find.text('Ana Reyes'), findsOneWidget);
    expect(find.text('Eatery is not set up yet.'), findsOneWidget);
  });
}
