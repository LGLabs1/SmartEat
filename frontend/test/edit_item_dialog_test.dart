import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/features/inventory/presentation/widgets/add_item_dialog.dart';
import 'package:smarteat/models/inventory_item.dart';

void main() {
  testWidgets('edit mode prefills item details and locks stock quantity',
      (tester) async {
    final item = InventoryItem(
      id: 'item-7',
      name: 'Tomato',
      category: 'Vegetables',
      currentStock: 12.5,
      unit: 'kg',
      minStock: 4,
      unitCost: 25,
      sellingPrice: 40,
      supplier: 'Farm Co',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddItemDialog(initialItem: item),
        ),
      ),
    );

    expect(find.text('Edit Inventory Item'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    final stockValue = find.byWidgetPredicate(
      (widget) => widget is EditableText && widget.controller.text == '12.50',
    );
    final stockField = tester.widget<TextField>(
      find.ancestor(of: stockValue, matching: find.byType(TextField)),
    );
    expect(stockField.enabled, isFalse);
  });
}
