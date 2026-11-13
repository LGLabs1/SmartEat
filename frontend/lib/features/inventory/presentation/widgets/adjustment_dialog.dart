import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/stock_adjustment.dart';

class AdjustmentDialog extends StatefulWidget {
  final String itemId;

  const AdjustmentDialog({Key? key, required this.itemId}) : super(key: key);

  @override
  State<AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<AdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  String _type = 'increase';

  final _reasons = const [
    'overcount',
    'spoilage',
    'theft',
    'donation',
    'countFix',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    _reasonController.text = _reasons.first;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Stock Adjustment'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'increase', child: Text('Increase')),
                    DropdownMenuItem(value: 'decrease', child: Text('Decrease')),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'increase'),
                ),
                TextFormField(
                  controller: _qtyController,
                  decoration: const InputDecoration(labelText: 'Quantity (base)'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) <= 0 ? 'Valid qty' : null,
                ),
                DropdownButtonFormField<String>(
                  value: _reasons.first,
                  decoration: const InputDecoration(labelText: 'Reason Code'),
                  items: _reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => _reasonController.text = v ?? _reasons.first,
                ),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 2,
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
            final qty = double.parse(_qtyController.text);
            final delta = _type == 'increase' ? qty : -qty;
            final reason = _reasonController.text.isEmpty ? _reasons.first : _reasonController.text;
            final adj = StockAdjustment(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              adjustmentNumber: 'ADJ-' + DateTime.now().millisecondsSinceEpoch.toString(),
              itemId: widget.itemId,
              deltaBase: delta,
              qtyBeforeBase: 0,
              qtyAfterBase: 0,
              reasonCode: reason,
              notes: _notesController.text.isEmpty ? null : _notesController.text,
              performedBy: 'admin',
            );
            Navigator.pop(context, adj);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
