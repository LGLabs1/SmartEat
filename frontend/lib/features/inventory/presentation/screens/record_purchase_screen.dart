import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../data/models/purchase_list_item.dart';
import '../../data/models/purchase_receipt.dart';

/// Full-screen review step for turning the Purchase List into a recorded
/// purchase receipt. The user confirms which planned items were actually
/// bought (and can adjust quantity / unit cost) before the inventory is
/// updated.
class RecordPurchaseScreen extends StatefulWidget {
  final List<PurchaseListItem> list;

  const RecordPurchaseScreen({Key? key, required this.list}) : super(key: key);

  @override
  State<RecordPurchaseScreen> createState() => _RecordPurchaseScreenState();
}

class _RecordLine {
  final PurchaseListItem item;
  bool included;
  final TextEditingController qtyController;
  final TextEditingController costController;

  _RecordLine(this.item, {required this.included})
      : qtyController =
            TextEditingController(text: _formatNum(item.qty)),
        costController =
            TextEditingController(text: _formatNum(item.unitCost));

  static String _formatNum(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();

  double get qty => double.tryParse(qtyController.text.trim()) ?? 0;
  double get cost => double.tryParse(costController.text.trim()) ?? 0;
  double get lineCost => qty * cost;

  void dispose() {
    qtyController.dispose();
    costController.dispose();
  }
}

class _RecordPurchaseScreenState extends State<RecordPurchaseScreen> {
  late List<_RecordLine> _lines;
  final _supplierController = TextEditingController();
  final _receiptController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-select items already ticked in the list; if none are ticked, select
    // everything so the user can simply uncheck what they did not buy.
    final anyChecked = widget.list.any((e) => e.checked);
    _lines = widget.list
        .map((e) => _RecordLine(e, included: anyChecked ? e.checked : true))
        .toList();
    _receiptController.text =
        'PL-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}';
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _supplierController.dispose();
    _receiptController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatCurrency(double amount) =>
      NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(amount);

  List<_RecordLine> get _selected =>
      _lines.where((l) => l.included).toList();

  double get _total =>
      _selected.fold(0.0, (sum, l) => sum + l.lineCost);

  bool get _isValid =>
      _selected.isNotEmpty && _selected.every((l) => l.qty > 0);

  void _submit() {
    if (!_isValid) return;
    final receipt = PurchaseReceipt(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      receiptNumber: _receiptController.text.trim().isEmpty
          ? 'PL-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}'
          : _receiptController.text.trim(),
      supplierName: _supplierController.text.trim().isEmpty
          ? null
          : _supplierController.text.trim(),
      receivedBy: 'admin',
      receivedAt: DateTime.now(),
      status: 'received',
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      items: _selected
          .map((l) => PurchaseReceiptItem(
                itemId: l.item.itemId,
                qtyBase: l.qty,
                qtyPurchased: l.qty,
                purchaseUnit: l.item.unit,
                conversionFactor: 1.0,
                unitCostPerBase: l.cost,
              ))
          .toList(),
    );
    Navigator.of(context).pop(receipt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(title: const Text('Review Purchase')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _summaryCard(theme, selected.length),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.checklist_rtl,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Items',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          final allOn =
                              _lines.every((l) => l.included);
                          for (final l in _lines) {
                            l.included = !allOn;
                          }
                        }),
                        child: Text(
                          _lines.every((l) => l.included)
                              ? 'Clear all'
                              : 'Select all',
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  ..._lines.map((l) => _lineTile(theme, l)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Details (optional)',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _receiptController,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Receipt #',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _supplierController,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Supplier',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: _bottomBar(theme, selected.length),
    );
  }

  Widget _summaryCard(ThemeData theme, int selectedCount) {
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.inventory_2_outlined,
                color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$selectedCount of ${_lines.length} items selected',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    'Uncheck items you did not buy. Adjust quantities if different.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Est. total',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    )),
                Text(
                  _formatCurrency(_total),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineTile(ThemeData theme, _RecordLine l) {
    final disabled = !l.included;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1F000000))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: l.included,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => l.included = v ?? false),
              ),
              Expanded(
                child: Text(
                  l.item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: disabled
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
              Text(
                _formatCurrency(l.lineCost),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: disabled
                      ? theme.colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 40, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: l.qtyController,
                    enabled: l.included,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Qty (${l.item.unit})',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('×'),
                ),
                Expanded(
                  child: TextField(
                    controller: l.costController,
                    enabled: l.included,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Unit cost (₱)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(ThemeData theme, int selectedCount) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _isValid ? _submit : null,
                icon: const Icon(Icons.check),
                label: Text('Record & Update Inventory ($selectedCount)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
