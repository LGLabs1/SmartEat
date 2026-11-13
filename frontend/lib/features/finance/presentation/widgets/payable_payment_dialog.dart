import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/finance_format.dart';
import '../../data/finance_metrics.dart';

/// Asks for the actual amount when a variable bill is marked paid.
///
/// Returns the entered amount, or null when cancelled. Prefilled with the
/// bill's best-known amount (last actual / estimate / average) when available.
class PayablePaymentDialog extends StatefulWidget {
  const PayablePaymentDialog({
    super.key,
    required this.payable,
    required this.currencySymbol,
  });

  final Map<String, dynamic> payable;
  final String currencySymbol;

  static Future<double?> show(
    BuildContext context, {
    required Map<String, dynamic> payable,
    required String currencySymbol,
  }) {
    return showDialog<double>(
      context: context,
      builder: (_) => PayablePaymentDialog(
        payable: payable,
        currencySymbol: currencySymbol,
      ),
    );
  }

  @override
  State<PayablePaymentDialog> createState() => _PayablePaymentDialogState();
}

class _PayablePaymentDialogState extends State<PayablePaymentDialog> {
  final _amountController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final suggested = FinanceMetrics.estimatedAmountOf(widget.payable);
    if (suggested > 0) {
      _amountController.text = suggested.toStringAsFixed(2);
    }
    _amountController.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _save() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Please enter the amount paid');
      return;
    }
    Navigator.of(context).pop(amount);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (widget.payable['name'] ?? 'Bill').toString();
    final history = FinanceMetrics.payableHistory(widget.payable);
    final recent = history.take(3).toList();

    return AlertDialog(
      title: const Text('Confirm Payment'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How much did you pay for $name?',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  labelText: 'Amount paid',
                  prefixIcon: SizedBox(
                    width: 56,
                    child: Center(
                      child: Text(
                        widget.currencySymbol,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  errorText: _error,
                ),
                onSubmitted: (_) => _save(),
              ),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Recent amounts',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: recent.map((entry) {
                    final label = entry.value == null
                        ? '${widget.currencySymbol}${entry.key.toStringAsFixed(2)}'
                        : '${widget.currencySymbol}${entry.key.toStringAsFixed(2)}'
                            ' · ${FinanceFormat.date(entry.value!)}';
                    return ActionChip(
                      label: Text(label),
                      onPressed: () {
                        _amountController.text =
                            entry.key.toStringAsFixed(2);
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Mark Paid'),
        ),
      ],
    );
  }
}
