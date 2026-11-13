import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme.dart';
import '../../data/finance_format.dart';
import 'finance_form_shell.dart';

/// Result of the add-expense form.
class ExpenseDraft {
  const ExpenseDraft({
    required this.name,
    required this.category,
    required this.amount,
    required this.date,
    required this.notes,
    required this.supplierName,
    required this.paymentMethod,
  });

  final String name;
  final String category;
  final double amount;
  final DateTime date;
  final String notes;
  final String supplierName;
  final String paymentMethod;
}

/// Modal dialog used to record a manual expense. Returns a draft on save or
/// null when cancelled so the caller can persist it via [ApiService].
class ExpenseFormDialog extends StatefulWidget {
  const ExpenseFormDialog({
    super.key,
    required this.currencySymbol,
    required this.categories,
    required this.paymentMethods,
  });

  final String currencySymbol;
  final List<String> categories;
  final List<String> paymentMethods;

  static Future<ExpenseDraft?> show(
    BuildContext context, {
    required String currencySymbol,
    required List<String> categories,
    required List<String> paymentMethods,
  }) {
    return showDialog<ExpenseDraft>(
      context: context,
      builder: (_) => ExpenseFormDialog(
        currencySymbol: currencySymbol,
        categories: categories,
        paymentMethods: paymentMethods,
      ),
    );
  }

  @override
  State<ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<ExpenseFormDialog> {
  late String _category = widget.categories.isNotEmpty
      ? widget.categories.first
      : 'Other';
  late String _paymentMethod = widget.paymentMethods.isNotEmpty
      ? widget.paymentMethods.first
      : 'Cash';
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _amountController = TextEditingController();
  final _supplierController = TextEditingController();
  DateTime _date = DateTime.now();

  String? _nameError;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_clearAmountError);
    _nameController.addListener(_clearNameError);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _amountController.dispose();
    _supplierController.dispose();
    super.dispose();
  }

  void _clearNameError() {
    if (_nameError != null && _nameController.text.trim().isNotEmpty) {
      setState(() => _nameError = null);
    }
  }

  void _clearAmountError() {
    if (_amountError != null) {
      final parsed = double.tryParse(_amountController.text.trim());
      if (parsed != null && parsed > 0) setState(() => _amountError = null);
    }
  }

  double? get _parsedAmount =>
      double.tryParse(_amountController.text.trim());

  void _save() {
    final name = _nameController.text.trim();
    final amount = _parsedAmount;
    final nameError = name.isEmpty ? 'Please enter an expense name' : null;
    final amountError = (amount == null || amount <= 0)
        ? 'Please enter a valid amount'
        : null;
    if (nameError != null || amountError != null) {
      setState(() {
        _nameError = nameError;
        _amountError = amountError;
      });
      return;
    }
    Navigator.of(context).pop(
      ExpenseDraft(
        name: name,
        category: _category,
        amount: amount!,
        date: _date,
        notes: _notesController.text.trim(),
        supplierName: _supplierController.text.trim(),
        paymentMethod: _paymentMethod,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FinanceFormShell(
      title: 'Add Expense',
      subtitle: 'Record a one-off or manual business expense',
      icon: Icons.receipt_long_outlined,
      accentColor: AppTheme.primary,
      saveLabel: 'Save Expense',
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      children: [
        FinanceFormSection(
          title: 'Details',
          icon: Icons.description_outlined,
          children: [
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Expense Name',
                hintText: 'e.g., Electricity bill',
                prefixIcon: const Icon(Icons.edit_note),
                errorText: _nameError,
              ),
            ),
            financeFieldGap,
            _dateField(context),
          ],
        ),
        FinanceFormSection(
          title: 'Amount',
          icon: Icons.payments_outlined,
          children: [
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixIcon: SizedBox(
                  width: 52,
                  child: Center(
                    child: Text(
                      widget.currencySymbol,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                errorText: _amountError,
              ),
            ),
            financeFieldGap,
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: widget.categories
                  .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _category = v);
              },
            ),
            financeFieldGap,
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              items: widget.paymentMethods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _paymentMethod = v);
              },
            ),
          ],
        ),
        FinanceFormSection(
          title: 'More (optional)',
          icon: Icons.more_horiz,
          children: [
            TextField(
              controller: _supplierController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Supplier / Vendor',
                hintText: 'e.g., Local market',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
            ),
            financeFieldGap,
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Notes',
                hintText: 'Additional details...',
                prefixIcon: const Icon(Icons.notes),
                alignLabelWithHint: true,
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
              ),
              minLines: 2,
              maxLines: 4,
            ),
          ],
        ),
      ],
    );
  }

  Widget _dateField(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked == null) return;
        setState(() => _date = picked);
      },
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Date',
          prefixIcon: Icon(Icons.calendar_today_outlined),
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          FinanceFormat.date(_date),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
