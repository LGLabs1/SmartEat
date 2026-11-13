import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/purchase_receipt.dart';

class PurchaseDialog extends StatefulWidget {
  const PurchaseDialog({Key? key}) : super(key: key);

  @override
  State<PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<PurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _receiptNumberController = TextEditingController();
  final _supplierController = TextEditingController();
  final _itemIdController = TextEditingController();
  final _qtyController = TextEditingController();
  final _costController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Purchase (GRN)'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _receiptNumberController,
                  decoration: const InputDecoration(labelText: 'Receipt #'),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                TextFormField(
                  controller: _supplierController,
                  decoration: const InputDecoration(labelText: 'Supplier'),
                ),
                TextFormField(
                  controller: _itemIdController,
                  decoration: const InputDecoration(labelText: 'Item ID'),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                TextFormField(
                  controller: _qtyController,
                  decoration: const InputDecoration(labelText: 'Quantity (base)'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) <= 0 ? 'Valid qty' : null,
                ),
                TextFormField(
                  controller: _costController,
                  decoration: const InputDecoration(labelText: 'Unit Cost per Base'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) < 0 ? 'Valid cost' : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final receipt = PurchaseReceipt(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              receiptNumber: _receiptNumberController.text,
              supplierName: _supplierController.text.isEmpty ? null : _supplierController.text,
              receivedBy: 'admin',
              items: [
                PurchaseReceiptItem(
                  itemId: _itemIdController.text,
                  qtyBase: double.parse(_qtyController.text),
                  qtyPurchased: double.parse(_qtyController.text),
                  unitCostPerBase: double.parse(_costController.text),
                  conversionFactor: 1.0,
                )
              ],
            );
            Navigator.pop(context, receipt);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
