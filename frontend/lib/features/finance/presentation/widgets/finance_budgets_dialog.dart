import 'package:flutter/material.dart';

import '../../data/finance_format.dart';

/// Editor for per-category monthly budgets. Returns the updated map on save,
/// or null when cancelled. An empty/zero value removes a budget.
class FinanceBudgetsDialog extends StatefulWidget {
  const FinanceBudgetsDialog({
    super.key,
    required this.categories,
    required this.budgets,
    required this.currencySymbol,
  });

  final List<String> categories;
  final Map<String, double> budgets;
  final String currencySymbol;

  static Future<Map<String, double>?> show(
    BuildContext context, {
    required List<String> categories,
    required Map<String, double> budgets,
    required String currencySymbol,
  }) {
    return showDialog<Map<String, double>>(
      context: context,
      builder: (_) => FinanceBudgetsDialog(
        categories: categories,
        budgets: budgets,
        currencySymbol: currencySymbol,
      ),
    );
  }

  @override
  State<FinanceBudgetsDialog> createState() => _FinanceBudgetsDialogState();
}

class _FinanceBudgetsDialogState extends State<FinanceBudgetsDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final c in widget.categories)
      c: TextEditingController(
        text: (widget.budgets[c] != null && widget.budgets[c]! > 0)
            ? widget.budgets[c]!.toStringAsFixed(0)
            : '',
      ),
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final result = <String, double>{};
    _controllers.forEach((category, controller) {
      final value = double.tryParse(controller.text.trim());
      if (value != null && value > 0) {
        result[category] = value;
      }
    });
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Category Budgets'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set a monthly limit per category. '
                'Leave blank for no budget.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final category in widget.categories) ...[
                TextField(
                  controller: _controllers[category],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: category,
                    prefixText: '${widget.currencySymbol} ',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
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
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Persists budgets under user_preferences (no schema/rules change needed).
class FinanceBudgetStore {
  FinanceBudgetStore._();

  static String _key = 'financeCategoryBudgets';

  static Map<String, double> parse(dynamic raw) {
    if (raw is! Map) return {};
    final result = <String, double>{};
    raw.forEach((k, v) {
      final key = k.toString();
      final value = v is num ? v.toDouble() : double.tryParse('$v');
      if (value != null && value > 0) {
        result[key] = value;
      }
    });
    return result;
  }

  static String get key => _key;
}

/// Formats a number for the budget dialog summary line.
String budgetSummary(Map<String, double> budgets, FinanceFormat fmt) {
  if (budgets.isEmpty) return 'No budgets set';
  final total = budgets.values.fold<double>(0, (a, b) => a + b);
  return '${budgets.length} categories • ${fmt.moneyCompact(total)}/mo';
}
