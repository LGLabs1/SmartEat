import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/widgets/pending_approvals_card.dart';

void main() {
  testWidgets('renders pending staff and wires approve/reject', (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final approved = <String>[];
    final rejected = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingApprovalsCard(
            pending: const [
              PendingStaffEntry(
                uid: 'u1',
                name: 'Ana Cruz',
                email: 'ana@example.com',
              ),
              PendingStaffEntry(
                uid: 'u2',
                name: 'Ben Santos',
                phone: '09171234567',
              ),
            ],
            onApprove: (uid) async => approved.add(uid),
            onReject: (uid, name) async => rejected.add('$uid:$name'),
          ),
        ),
      ),
    );

    expect(find.text('Pending approvals (2)'), findsOneWidget);
    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Ben Santos'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
    await tester.pump();
    expect(approved, ['u1']);

    await tester.tap(find.widgetWithText(TextButton, 'Reject').last);
    await tester.pump();
    expect(rejected, ['u2:Ben Santos']);
  });

  testWidgets('renders nothing when there is no pending staff',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PendingApprovalsCard(
            pending: const [],
            onApprove: (_) async {},
            onReject: (_, __) async {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Pending approvals'), findsNothing);
    expect(find.byType(Card), findsNothing);
  });
}
