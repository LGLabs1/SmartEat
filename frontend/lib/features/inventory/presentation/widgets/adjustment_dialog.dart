import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smarteat/models/inventory_item.dart';
import 'package:smarteat/theme.dart';
import '../../data/models/stock_adjustment.dart';

class AdjustmentDialog extends StatefulWidget {
  final List<InventoryItem> items;
  final InventoryItem? initialItem;
  final String? performedBy;

  const AdjustmentDialog({
    Key? key,
    required this.items,
    this.initialItem,
    this.performedBy,
  }) : super(key: key);

  @override
  State<AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<AdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qtyController = TextEditingController();
  final _notesController = TextEditingController();

  late String _selectedItemId;
  String _type = 'increase';
  String _reason = 'countFix';

  static const _reasons = [
    'overcount',
    'spoilage',
    'theft',
    'donation',
    'countFix',
    'other',
  ];

  static const _reasonLabels = {
    'overcount': 'Overcount',
    'spoilage': 'Spoilage',
    'theft': 'Theft',
    'donation': 'Donation',
    'countFix': 'Count correction',
    'other': 'Other',
  };

  @override
  void initState() {
    super.initState();
    _selectedItemId = widget.initialItem?.id ??
        (widget.items.isNotEmpty ? widget.items.first.id : '');
  }

  InventoryItem? get _selectedItem {
    for (final item in widget.items) {
      if (item.id == _selectedItemId) return item;
    }
    return null;
  }

  double get _currentStock => _selectedItem?.currentStock ?? 0;

  double? get _enteredQty {
    final value = double.tryParse(_qtyController.text.trim());
    return value != null && value > 0 ? value : null;
  }

  String _qty(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  String _reasonLabel(String code) => _reasonLabels[code] ?? code;

  @override
  Widget build(BuildContext context) {
    final item = _selectedItem;
    final unit = item?.effectiveBaseUnit ?? 'units';
    final qty = _enteredQty;
    final projected =
        qty == null ? null : _currentStock + (_type == 'increase' ? qty : -qty);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: const BoxDecoration(gradient: AppTheme.sageGradient),
              child: Row(
                children: [
                  const Icon(Icons.tune, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stock Adjustment',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Record a manual stock correction',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.initialItem == null && widget.items.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _selectedItemId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Inventory item',
                            prefixIcon: Icon(Icons.inventory_2_outlined),
                          ),
                          items: [
                            for (final entry in widget.items)
                              DropdownMenuItem<String>(
                                value: entry.id,
                                child: Text(entry.name,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedItemId = value ?? ''),
                        ),
                      if (widget.initialItem == null && widget.items.isNotEmpty)
                        const SizedBox(height: 16),
                      if (item == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No inventory items are available to adjust.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.sagePanel.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.layers_outlined,
                                  color: AppTheme.sageAccent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Current stock'),
                                    Text(
                                      '${_qty(_currentStock)} $unit',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Chip(
                                label: Text(item.category),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _type,
                          decoration: const InputDecoration(
                            labelText: 'Adjustment type',
                            prefixIcon: Icon(Icons.swap_vert),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'increase', child: Text('Increase')),
                            DropdownMenuItem(
                                value: 'decrease', child: Text('Decrease')),
                          ],
                          onChanged: (value) =>
                              setState(() => _type = value ?? 'increase'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _qtyController,
                          decoration: InputDecoration(
                            labelText: 'Quantity ($unit)',
                            prefixIcon: const Icon(Icons.numbers),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d*')),
                          ],
                          onChanged: (_) => setState(() {}),
                          validator: (value) {
                            final parsed = double.tryParse(value?.trim() ?? '');
                            if (parsed == null || parsed <= 0) {
                              return 'Enter a quantity greater than zero';
                            }
                            if (_type == 'decrease' && parsed > _currentStock) {
                              return 'Cannot reduce stock below zero';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _reason,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                            prefixIcon: Icon(Icons.label_outline),
                          ),
                          items: [
                            for (final reason in _reasons)
                              DropdownMenuItem<String>(
                                value: reason,
                                child: Text(_reasonLabel(reason)),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _reason = value ?? _reason),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _notesController,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            prefixIcon: Icon(Icons.notes_outlined),
                            helperText: 'Optional context for the audit trail',
                          ),
                          maxLines: 2,
                          minLines: 2,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.sageBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            projected == null
                                ? 'Enter a quantity to preview the new stock level.'
                                : 'New stock level: ${_qty(projected)} $unit',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: item == null ? null : _save,
                    icon: const Icon(Icons.check),
                    label: const Text('Apply Adjustment'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final item = _selectedItem;
    if (item == null) return;
    final qty = double.parse(_qtyController.text.trim());
    final delta = _type == 'increase' ? qty : -qty;
    final before = item.currentStock;
    final now = DateTime.now();
    Navigator.of(context).pop(
      StockAdjustment(
        id: now.microsecondsSinceEpoch.toString(),
        adjustmentNumber: 'ADJ-${now.millisecondsSinceEpoch}',
        itemId: item.id,
        deltaBase: delta,
        qtyBeforeBase: before,
        qtyAfterBase: before + delta,
        reasonCode: _reason,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        performedBy: widget.performedBy ?? 'admin',
        performedAt: now,
      ),
    );
  }
}
