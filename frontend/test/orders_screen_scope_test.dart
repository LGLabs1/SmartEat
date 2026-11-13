import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/screens/orders_screen.dart';

/// The History view replaces the StreamBuilder, which cancels its subscription.
/// Coming back must attach to a fresh stream — getTodayOrdersStream() is
/// single-subscription, so re-listening to the old one throws
/// "Stream has already been listened to".
void main() {
  testWidgets('History switch is absent for staff', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: OrdersScreen(isAdmin: false)),
    ));
    await tester.pump();
    expect(find.text('History'), findsNothing);
  });
}