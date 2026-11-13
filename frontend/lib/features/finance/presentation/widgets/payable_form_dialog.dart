import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme.dart';
import '../../data/finance_format.dart';
import 'finance_form_shell.dart';

/// Data captured by the payable form, suitable for both create and edit.
class PayableDraft {
  const PayableDraft({
    required this.name,
    required this.amount,
    required this.frequency,
    required this.dueDate,
    required this.notes,
    required this.vendor,
    this.dueDay,
    this.dueDays,
    this.dueMonth,
    this.reminderEnabled = false,
    this.reminderDaysBefore,
    this.reminderTime,
    this.isVariable = false,
    this.estimateAmount,
  });

  final String name;
  final double amount;
  final String frequency;
  final DateTime? dueDate;
  final String notes;
  final String vendor;
  final int? dueDay;
  final List<int>? dueDays;
  final int? dueMonth;
  final bool reminderEnabled;
  final int? reminderDaysBefore;
  final String? reminderTime;
  final bool isVariable;
  final double? estimateAmount;
}

/// Create/edit modal for recurring bills/payables.
///
/// Pass [initial] to edit an existing payable; omit it to create a new one.
class PayableFormDialog extends StatefulWidget {
  const PayableFormDialog({
    super.key,
    required this.currencySymbol,
    required this.billCategories,
    this.initial,
  });

  final String currencySymbol;
  final List<String> billCategories;
  final Map<String, dynamic>? initial;

  static Future<PayableDraft?> show(
    BuildContext context, {
    required String currencySymbol,
    required List<String> billCategories,
    Map<String, dynamic>? initial,
  }) {
    return showDialog<PayableDraft>(
      context: context,
      builder: (_) => PayableFormDialog(
        currencySymbol: currencySymbol,
        billCategories: billCategories,
        initial: initial,
      ),
    );
  }

  @override
  State<PayableFormDialog> createState() => _PayableFormDialogState();
}

class _PayableFormDialogState extends State<PayableFormDialog> {
  static const List<String> _frequencies = [
    'daily',
    'weekly',
    'biweekly',
    'monthly',
    'quarterly',
    'yearly',
  ];

  static const Map<String, String> _frequencyLabels = {
    'daily': 'Daily',
    'weekly': 'Weekly',
    'biweekly': 'Every 2 weeks',
    'monthly': 'Monthly',
    'quarterly': 'Quarterly',
    'yearly': 'Yearly',
  };

  late String _category;
  late String _frequency;
  final _amountController = TextEditingController();
  final _estimateController = TextEditingController();
  final _notesController = TextEditingController();
  final _vendorController = TextEditingController();
  DateTime? _dueDate;
  bool _isVariable = false;
  bool _reminderEnabled = true;
  int _reminderDaysBefore = 3;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);

  int? _monthlyDueDay;
  int? _weeklyDueDay;
  List<int> _biWeeklyDueDays = [];
  int? _quarterlyDueMonth;
  int? _quarterlyDueDay;
  int? _yearlyDueMonth;
  int? _yearlyDueDay;

  String? _categoryError;
  String? _amountError;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) {
      _category = widget.billCategories.isNotEmpty
          ? widget.billCategories.first
          : 'Other';
      _frequency = 'monthly';
      _monthlyDueDay = DateTime.now().day;
      _dueDate = _defaultDueDateFor('monthly', DateTime.now().day);
      return;
    }

    final name = (initial['name'] ?? '').toString();
    _category = widget.billCategories.contains(name)
        ? name
        : (widget.billCategories.isNotEmpty
            ? widget.billCategories.first
            : 'Other');
    final amount = initial['amount'];
    if (amount is num && amount > 0) {
      _amountController.text = amount.toString();
    }
    _isVariable = initial['isVariable'] == true ||
        (initial['isVariable'] != false && (amount is! num || amount <= 0));
    final estimate = initial['estimateAmount'];
    if (estimate is num && estimate > 0) {
      _estimateController.text = estimate.toString();
    } else if (_isVariable) {
      final fallback = initial['lastAmount'] ?? initial['averageAmount'];
      if (fallback is num && fallback > 0) {
        _estimateController.text = fallback.toString();
      }
    }
    _vendorController.text = (initial['vendor'] ?? '').toString();
    _notesController.text = (initial['notes'] ?? '').toString();

    var freq = (initial['frequency'] ?? 'monthly').toString().toLowerCase();
    if (!_frequencies.contains(freq)) freq = 'monthly';
    _frequency = freq;
    _dueDate = FinanceFormat.asDate(initial['dueDate']);

    _monthlyDueDay = initial['dueDay'] is int ? initial['dueDay'] as int : null;
    _weeklyDueDay = initial['dueDay'] is int ? initial['dueDay'] as int : null;
    _biWeeklyDueDays = (initial['dueDays'] is List)
        ? (initial['dueDays'] as List).whereType<int>().toList()
        : [];
    _quarterlyDueMonth =
        initial['dueMonth'] is int ? initial['dueMonth'] as int : null;
    _quarterlyDueDay =
        initial['dueDay'] is int ? initial['dueDay'] as int : null;
    _yearlyDueMonth =
        initial['dueMonth'] is int ? initial['dueMonth'] as int : null;
    _yearlyDueDay = initial['dueDay'] is int ? initial['dueDay'] as int : null;

    _reminderEnabled = initial['reminderEnabled'] == true;
    _reminderDaysBefore =
        initial['reminderDaysBefore'] is int ? initial['reminderDaysBefore'] as int : 3;
    final time = (initial['reminderTime'] ?? '').toString();
    final parts = time.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        _reminderTime = TimeOfDay(hour: h, minute: m);
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _estimateController.dispose();
    _notesController.dispose();
    _vendorController.dispose();
    super.dispose();
  }

  /// Computes a sensible next due date for a frequency + anchor day.
  DateTime _defaultDueDateFor(String frequency, int day) {
    final now = DateTime.now();
    final safeDay = day.clamp(1, 28);
    switch (frequency) {
      case 'daily':
        return now;
      case 'weekly':
        final delta = (day - now.weekday) % 7;
        return DateTime(now.year, now.month, now.day + delta);
      case 'biweekly':
        return DateTime(now.year, now.month, now.day + 14);
      default:
        var target = DateTime(now.year, now.month, safeDay);
        if (target.isBefore(now)) {
          target = DateTime(now.year, now.month + 1, safeDay);
        }
        return target;
    }
  }

  int? get _computedDueDay {
    switch (_frequency) {
      case 'monthly':
        return _monthlyDueDay;
      case 'weekly':
        return _weeklyDueDay;
      case 'biweekly':
        return _biWeeklyDueDays.isNotEmpty ? _biWeeklyDueDays.first : null;
      case 'quarterly':
        return _quarterlyDueDay;
      case 'yearly':
        return _yearlyDueDay;
      default:
        return null;
    }
  }

  int? get _computedDueMonth {
    if (_frequency == 'quarterly') return _quarterlyDueMonth;
    if (_frequency == 'yearly') return _yearlyDueMonth;
    return null;
  }

  void _onFrequencyChanged(String freq) {
    setState(() {
      _frequency = freq;
      _monthlyDueDay = freq == 'monthly' ? (_monthlyDueDay ?? DateTime.now().day) : _monthlyDueDay;
      if (freq == 'monthly') {
        _dueDate = _defaultDueDateFor('monthly', _monthlyDueDay ?? DateTime.now().day);
      } else {
        _dueDate = _defaultDueDateFor(freq, 1);
      }
    });
  }

  void _save() {
    final amountText = _amountController.text.trim();
    final amount = amountText.isEmpty ? null : double.tryParse(amountText);
    final estimateText = _estimateController.text.trim();
    final estimate =
        estimateText.isEmpty ? null : double.tryParse(estimateText);

    final categoryError = _category.isEmpty ? 'Bill category is required' : null;

    // Fixed bills require a positive amount; variable bills may carry an
    // optional estimate but the actual is captured at payment time.
    String? amountError;
    if (!_isVariable) {
      if (amount == null || amount <= 0) {
        amountError = 'Enter the bill amount';
      }
    } else if (estimateText.isNotEmpty &&
        (estimate == null || estimate <= 0)) {
      amountError = 'Enter a valid estimated amount or leave empty';
    }

    if (categoryError != null || amountError != null) {
      setState(() {
        _categoryError = categoryError;
        _amountError = amountError;
      });
      return;
    }

    Navigator.of(context).pop(
      PayableDraft(
        name: _category,
        amount: _isVariable ? 0.0 : (amount ?? 0.0),
        frequency: _frequency,
        dueDate: _dueDate,
        notes: _notesController.text.trim(),
        vendor: _vendorController.text.trim(),
        dueDay: _computedDueDay,
        dueDays: _frequency == 'biweekly' && _biWeeklyDueDays.isNotEmpty
            ? _biWeeklyDueDays
            : null,
        dueMonth: _computedDueMonth,
        reminderEnabled: _reminderEnabled,
        reminderDaysBefore: _reminderDaysBefore,
        reminderTime: '${_reminderTime.hour}:${_reminderTime.minute}',
        isVariable: _isVariable,
        estimateAmount: _isVariable ? estimate : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FinanceFormShell(
      title: _isEdit ? 'Edit Recurring Bill' : 'Add Recurring Bill',
      subtitle: 'Set up a repeating payable and optional reminder',
      icon: Icons.event_repeat_outlined,
      accentColor: AppTheme.warning,
      saveLabel: _isEdit ? 'Save Changes' : 'Add Bill',
      onCancel: () => Navigator.of(context).pop(),
      onSave: _save,
      children: [
        FinanceFormSection(
          title: 'Bill',
          icon: Icons.receipt_outlined,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Bill Category',
                prefixIcon: const Icon(Icons.category_outlined),
                errorText: _categoryError,
              ),
              items: widget.billCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _category = v;
                  _categoryError = null;
                });
              },
            ),
            financeFieldGap,
            TextField(
              controller: _vendorController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Vendor / Payee',
                hintText: 'e.g., PLDT, Meralco, Landlord',
                prefixIcon: Icon(Icons.business_outlined),
              ),
            ),
            financeFieldGap,
            _amountTypeSelector(context),
            financeFieldGap,
            if (_isVariable)
              TextField(
                controller: _estimateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  labelText: 'Typical amount (for estimates)',
                  hintText: 'Optional',
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
                  helperText: 'Used to project costs. The actual is entered '
                      'each time you mark the bill paid.',
                  errorText: _amountError,
                ),
              )
            else
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
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
          ],
        ),
        FinanceFormSection(
          title: 'Schedule',
          icon: Icons.schedule_outlined,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Repeats',
                prefixIcon: Icon(Icons.repeat),
              ),
              items: _frequencies
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(_frequencyLabels[f] ?? f),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                _onFrequencyChanged(v);
              },
            ),
            financeFieldGap,
            _buildDueControl(context),
            financeFieldGap,
            _dueDateField(context),
          ],
        ),
        _reminderSection(context),
        FinanceFormSection(
          title: 'Notes',
          icon: Icons.notes_outlined,
          children: [
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Account number, reference, etc.',
                prefixIcon: Icon(Icons.notes),
                alignLabelWithHint: true,
              ),
              minLines: 2,
              maxLines: 4,
            ),
          ],
        ),
      ],
    );
  }

  /// Single contextual control describing when the bill recurs, derived from
  /// the selected [frequency], replacing the previous stack of per-frequency
  /// pickers.
  Widget _buildDueControl(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (_frequency) {
      case 'daily':
        return _hint(
          context,
          Icons.today_outlined,
          'Repeats every day starting from the next due date.',
        );
      case 'weekly':
        return DropdownButtonFormField<int>(
          initialValue: _weeklyDueDay,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Due day of week',
            prefixIcon: Icon(Icons.calendar_view_week_outlined),
            hintText: 'Select a day',
          ),
          items: const [
            DropdownMenuItem(value: 1, child: Text('Monday')),
            DropdownMenuItem(value: 2, child: Text('Tuesday')),
            DropdownMenuItem(value: 3, child: Text('Wednesday')),
            DropdownMenuItem(value: 4, child: Text('Thursday')),
            DropdownMenuItem(value: 5, child: Text('Friday')),
            DropdownMenuItem(value: 6, child: Text('Saturday')),
            DropdownMenuItem(value: 7, child: Text('Sunday')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _weeklyDueDay = v;
              _dueDate = _defaultDueDateFor('weekly', v);
            });
          },
        );
      case 'biweekly':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_view_month_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  const Text(
                    'Pick two due days each month',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [1, 7, 14, 15, 21, 28, 30].map((day) {
                  final isSelected = _biWeeklyDueDays.contains(day);
                  final atLimit =
                      !isSelected && _biWeeklyDueDays.length >= 2;
                  return FilterChip(
                    label: Text('$day'),
                    selected: isSelected,
                    onSelected: atLimit
                        ? null
                        : (selected) {
                            setState(() {
                              if (selected) {
                                _biWeeklyDueDays.add(day);
                              } else {
                                _biWeeklyDueDays.remove(day);
                              }
                              _biWeeklyDueDays.sort();
                              if (_biWeeklyDueDays.length == 2) {
                                _dueDate = _defaultDueDateFor(
                                  'biweekly',
                                  _biWeeklyDueDays.first,
                                );
                              }
                            });
                          },
                  );
                }).toList(),
              ),
              if (_biWeeklyDueDays.length == 2) ...[
                const SizedBox(height: 8),
                Text(
                  'Due on the ${_biWeeklyDueDays.map((d) => "$d${FinanceFormat.daySuffix(d)}").join(" and ")}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      case 'quarterly':
        return Row(
          children: [
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<int>(
                initialValue: _quarterlyDueMonth,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Month',
                  hintText: 'Select',
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('January')),
                  DropdownMenuItem(value: 4, child: Text('April')),
                  DropdownMenuItem(value: 7, child: Text('July')),
                  DropdownMenuItem(value: 10, child: Text('October')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _quarterlyDueMonth = v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _dayDropdown(
                _quarterlyDueDay,
                (v) => setState(() => _quarterlyDueDay = v),
              ),
            ),
          ],
        );
      case 'yearly':
        return Row(
          children: [
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<int>(
                initialValue: _yearlyDueMonth,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Month',
                  hintText: 'Select',
                ),
                items: FinanceFormat.monthsLong.asMap().entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key + 1,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _yearlyDueMonth = v);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _dayDropdown(
                _yearlyDueDay,
                (v) => setState(() => _yearlyDueDay = v),
              ),
            ),
          ],
        );
      default:
        return DropdownButtonFormField<int>(
          initialValue: _monthlyDueDay,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Due day of month',
            prefixIcon: Icon(Icons.calendar_view_day_outlined),
            hintText: 'Select day (1-31)',
          ),
          items: List.generate(31, (i) => i + 1).map((day) {
            return DropdownMenuItem(
              value: day,
              child: Text('$day${FinanceFormat.daySuffix(day)}'),
            );
          }).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _monthlyDueDay = v;
              _dueDate = _defaultDueDateFor('monthly', v);
            });
          },
        );
    }
  }

  /// Fixed vs. variable amount selector. Variable bills (water, electricity)
  /// keep their schedule but capture the real cost when marked paid.
  Widget _amountTypeSelector(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount type',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Fixed'),
                icon: Icon(Icons.lock_outline, size: 16),
              ),
              ButtonSegment(
                value: true,
                label: Text('Variable'),
                icon: Icon(Icons.trending_up, size: 16),
              ),
            ],
            selected: {_isVariable},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              setState(() {
                _isVariable = s.first;
                _amountError = null;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _isVariable
                ? 'For bills that change each cycle. Enter the actual amount '
                    'each time you mark it paid.'
                : 'For bills that are the same every cycle.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dueDateField(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _dueDate ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked == null) return;
        setState(() => _dueDate = picked);
      },
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Next Due Date',
          prefixIcon: Icon(Icons.event_outlined),
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          _dueDate == null ? 'Select date' : FinanceFormat.date(_dueDate!),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _dayDropdown(int? value, ValueChanged<int> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Day',
        hintText: 'Select',
      ),
      items: List.generate(31, (i) => i + 1)
          .map((day) => DropdownMenuItem(value: day, child: Text('$day')))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _reminderSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 18,
                color: _reminderEnabled
                    ? AppTheme.warning
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              const Text(
                'Payment Reminder',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const Spacer(),
              Switch(
                value: _reminderEnabled,
                onChanged: (v) => setState(() => _reminderEnabled = v),
              ),
            ],
          ),
          if (_reminderEnabled) ...[
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                const Text('Remind me', style: TextStyle(fontSize: 13)),
                _stepper(
                  value: _reminderDaysBefore,
                  onChanged: (v) => setState(() => _reminderDaysBefore = v),
                ),
                const Text('days before at', style: TextStyle(fontSize: 13)),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _reminderTime,
                    );
                    if (picked == null) return;
                    setState(() => _reminderTime = picked);
                  },
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text(
                    '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepper({required int value, required ValueChanged<int> onChanged}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value > 0 ? value - 1 : 0),
          icon: const Icon(Icons.remove_circle_outline),
          color: AppTheme.warning,
          iconSize: 20,
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline),
          color: AppTheme.warning,
          iconSize: 20,
        ),
      ],
    );
  }
}
