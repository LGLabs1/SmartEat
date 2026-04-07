import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_provider.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({
    Key? key,
    this.globalSearchQuery,
    this.showAppBar = true,
    this.onOpenDrawer,
    this.onNavigate,
  }) : super(key: key);

  final ValueNotifier<String>? globalSearchQuery;
  final bool showAppBar;
  final VoidCallback? onOpenDrawer;
  final ValueChanged<int>? onNavigate;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _isLoading = false;
  String? _error;

  bool _isAdmin = false;
  String? _lastRoleUid;

  List<Map<String, dynamic>> _expenses = const [];
  List<Map<String, dynamic>> _payables = const [];

  String _searchQuery = '';
  VoidCallback? _globalSearchListener;

  // Currency symbol from business settings
  String get _currencySymbol => '₱';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();

    final notifier = widget.globalSearchQuery;
    if (notifier != null) {
      _searchQuery = notifier.value;
      _globalSearchListener = () {
        if (!mounted) return;
        setState(() {
          _searchQuery = notifier.value;
        });
      };
      notifier.addListener(_globalSearchListener!);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRole();
    });
  }

  @override
  void dispose() {
    final notifier = widget.globalSearchQuery;
    final listener = _globalSearchListener;
    if (notifier != null && listener != null) {
      notifier.removeListener(listener);
    }
    _tabController.dispose();
    super.dispose();
  }

  bool _isAdminFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final role = (profile['role'] ?? '').toString().trim().toLowerCase();
    final dynamic isAdminRaw = profile['isAdmin'];
    final bool isAdminFlag = isAdminRaw == true ||
        isAdminRaw == 1 ||
        (isAdminRaw is String && isAdminRaw.toLowerCase().trim() == 'true');
    return isAdminFlag || role == 'admin';
  }

  Future<void> _loadRole() async {
    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null || uid.isEmpty) return;
    if (_lastRoleUid == uid) return;
    _lastRoleUid = uid;

    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      if (!mounted) return;
      setState(() {
        _isAdmin = _isAdminFromProfile(profile);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        ApiService.getExpenses(),
        ApiService.getPayables(),
      ]);

      final expenses =
          List<Map<String, dynamic>>.from(results[0]['data'] ?? const []);
      final payables =
          List<Map<String, dynamic>>.from(results[1]['data'] ?? const []);

      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _payables = payables;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // Predefined expense categories
  static const List<String> _expenseCategories = [
    'Ingredients',
    'Utilities',
    'Rent',
    'Salaries',
    'Equipment',
    'Maintenance',
    'Marketing',
    'Supplies',
    'Transportation',
    'Taxes',
    'Insurance',
    'Other',
  ];

  // Predefined bill categories for payables
  static const List<String> _billCategories = [
    'Rent',
    'Electricity',
    'Water',
    'Internet',
    'Phone',
    'Gas',
    'Insurance',
    'Taxes',
    'Supplier Payment',
    'Salaries',
    'Maintenance',
    'Equipment Lease',
    'Marketing',
    'Other',
  ];

  String _fmtMoney(num? v, {bool showDashForZero = false}) {
    if (v == null || v == 0) {
      if (showDashForZero) return '${_currencySymbol}-.--';
      return '${_currencySymbol}0.00';
    }
    return '$_currencySymbol${v.toStringAsFixed(2)}';
  }

  DateTime? _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _getDaySuffix(int day) {
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  Future<void> _showAddExpenseDialog() async {
    if (!_isAdmin) return;

    String selectedCategory = _expenseCategories[0];
    final vendorController = TextEditingController();
    final notesController = TextEditingController();
    final amountController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String reminderFrequency = 'none';
    bool enableReminders = false;
    TimeOfDay reminderTime = const TimeOfDay(hour: 9, minute: 0);

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Add Expense'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date picker
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Date',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked == null) return;
                              setLocalState(() {
                                selectedDate = picked;
                              });
                            },
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(_fmtDate(selectedDate)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Category dropdown
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          prefixIcon: Icon(Icons.category),
                          border: OutlineInputBorder(),
                        ),
                        items: _expenseCategories.map((cat) {
                          return DropdownMenuItem(
                            value: cat,
                            child: Text(cat),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setLocalState(() {
                            selectedCategory = v;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      // Amount field
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          hintText: 'e.g., 1500',
                          prefixIcon: Icon(Icons.attach_money),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Vendor field
                      TextField(
                        controller: vendorController,
                        decoration: const InputDecoration(
                          labelText: 'Vendor (optional)',
                          hintText: 'e.g., Supplier Name',
                          prefixIcon: Icon(Icons.business),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Notes field
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'Additional details...',
                          prefixIcon: Icon(Icons.notes),
                          border: OutlineInputBorder(),
                        ),
                        minLines: 2,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 16),
                      // Reminder section
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.notifications_active,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Set Reminder',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Switch(
                                  value: enableReminders,
                                  onChanged: (v) {
                                    setLocalState(() {
                                      enableReminders = v;
                                      if (v && reminderFrequency == 'none') {
                                        reminderFrequency = 'monthly';
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (enableReminders) ...[
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: reminderFrequency,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Reminder Frequency',
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    ['daily', 'weekly', 'monthly'].map((freq) {
                                  final labels = {
                                    'daily': 'Daily',
                                    'weekly': 'Weekly',
                                    'monthly': 'Monthly',
                                  };
                                  return DropdownMenuItem(
                                    value: freq,
                                    child: Text(labels[freq] ?? freq),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setLocalState(() {
                                    reminderFrequency = v;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('Reminder Time:'),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: reminderTime,
                                      );
                                      if (picked == null) return;
                                      setLocalState(() {
                                        reminderTime = picked;
                                      });
                                    },
                                    icon:
                                        const Icon(Icons.access_time, size: 16),
                                    label: Text(
                                      '${reminderTime.hour.toString().padLeft(2, '0')}:${reminderTime.minute.toString().padLeft(2, '0')}',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'You will receive notifications based on this schedule.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final amount =
                        double.tryParse(amountController.text.trim());
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid amount'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != true) return;

    try {
      await ApiService.createExpense(
        category: selectedCategory,
        amount: double.parse(amountController.text.trim()),
        date: selectedDate,
        vendor: vendorController.text.trim(),
        notes: notesController.text.trim(),
      );

      // TODO: Save reminder settings to Firestore if enabled
      if (enableReminders) {
        // Save reminder configuration
        final eateryId = await _getEateryId();
        if (eateryId != null) {
          await FirebaseFirestore.instance
              .collection('eateries')
              .doc(eateryId)
              .collection('expense_reminders')
              .add({
            'category': selectedCategory,
            'frequency': reminderFrequency,
            'time': '${reminderTime.hour}:${reminderTime.minute}',
            'enabled': true,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense added')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add expense: $e')),
      );
    }
  }

  Future<String?> _getEateryId() async {
    try {
      final profile =
          await context.read<AuthProvider>().getCurrentUserProfile();
      return (profile?['eateryId'] ?? '').toString().trim();
    } catch (_) {
      return null;
    }
  }

  Future<void> _showAddPayableDialog() async {
    if (!_isAdmin) return;

    String selectedBillCategory = _billCategories[0];
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final vendorController = TextEditingController();
    String frequency = 'monthly';
    DateTime dueDate = DateTime.now().add(const Duration(days: 7));
    bool enableReminders = true;
    TimeOfDay reminderTime = const TimeOfDay(hour: 9, minute: 0);
    int? reminderDaysBefore = 3;

    // Due day selection based on frequency
    int? monthlyDueDay;
    int? weeklyDueDay; // 0=Monday, 6=Sunday
    List<int> biWeeklyDueDays = []; // For bi-weekly: two days of month
    int? quarterlyDueMonth; // 1-12
    int? quarterlyDueDay;
    int? yearlyDueMonth;
    int? yearlyDueDay;

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Add Recurring Bill / Payable'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bill Category dropdown
                      DropdownButtonFormField<String>(
                        value: selectedBillCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Bill Category',
                          prefixIcon: Icon(Icons.category),
                          border: OutlineInputBorder(),
                        ),
                        items: _billCategories.map((cat) {
                          return DropdownMenuItem(
                            value: cat,
                            child: Text(cat),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setLocalState(() {
                            selectedBillCategory = v;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      // Amount with PHP currency symbol
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixIcon: Icon(Icons.money),
                          prefixText: '₱ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Vendor
                      TextField(
                        controller: vendorController,
                        decoration: const InputDecoration(
                          labelText: 'Vendor / Payee (optional)',
                          hintText: 'e.g., PLDT, Meralco, Landlord',
                          prefixIcon: Icon(Icons.business),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Frequency dropdown
                      DropdownButtonFormField<String>(
                        value: frequency,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Frequency',
                          prefixIcon: Icon(Icons.repeat),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'daily',
                            child: Text('Daily'),
                          ),
                          DropdownMenuItem(
                            value: 'weekly',
                            child: Text('Weekly'),
                          ),
                          DropdownMenuItem(
                            value: 'biweekly',
                            child: Text('Bi-weekly'),
                          ),
                          DropdownMenuItem(
                            value: 'monthly',
                            child: Text('Monthly'),
                          ),
                          DropdownMenuItem(
                            value: 'quarterly',
                            child: Text('Quarterly'),
                          ),
                          DropdownMenuItem(
                            value: 'yearly',
                            child: Text('Yearly'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocalState(() {
                            frequency = v;
                            // Reset due day selections when frequency changes
                            monthlyDueDay = null;
                            weeklyDueDay = null;
                            biWeeklyDueDays = [];
                            quarterlyDueDay = null;
                            quarterlyDueMonth = null;
                            yearlyDueDay = null;
                            yearlyDueMonth = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      // Due day selector based on frequency
                      if (frequency == 'monthly') ...[
                        DropdownButtonFormField<int>(
                          value: monthlyDueDay,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Due day of month',
                            prefixIcon: Icon(Icons.calendar_view_day),
                            border: OutlineInputBorder(),
                            hintText: 'Select day (1-31)',
                          ),
                          items: List.generate(31, (i) => i + 1).map((day) {
                            return DropdownMenuItem(
                              value: day,
                              child: Text('$day${_getDaySuffix(day)}'),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setLocalState(() {
                                monthlyDueDay = v;
                                // Update next due date to match selected day
                                final now = DateTime.now();
                                DateTime newDueDate =
                                    DateTime(now.year, now.month, v);
                                // If the day has passed this month, use next month
                                if (newDueDate.isBefore(now)) {
                                  newDueDate =
                                      DateTime(now.year, now.month + 1, v);
                                }
                                dueDate = newDueDate;
                              });
                            }
                          },
                        ),
                      ] else if (frequency == 'weekly') ...[
                        DropdownButtonFormField<int>(
                          value: weeklyDueDay,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Due day of week',
                            prefixIcon: Icon(Icons.calendar_view_week),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Monday')),
                            DropdownMenuItem(value: 2, child: Text('Tuesday')),
                            DropdownMenuItem(
                                value: 3, child: Text('Wednesday')),
                            DropdownMenuItem(value: 4, child: Text('Thursday')),
                            DropdownMenuItem(value: 5, child: Text('Friday')),
                            DropdownMenuItem(value: 6, child: Text('Saturday')),
                            DropdownMenuItem(value: 7, child: Text('Sunday')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setLocalState(() => weeklyDueDay = v);
                            }
                          },
                        ),
                      ] else if (frequency == 'biweekly') ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Due days of month (select 2)',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [15, 30, 1, 14, 28, 7, 21].map((day) {
                                  final isSelected =
                                      biWeeklyDueDays.contains(day);
                                  return FilterChip(
                                    label: Text('$day'),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setLocalState(() {
                                        if (selected) {
                                          if (biWeeklyDueDays.length < 2) {
                                            biWeeklyDueDays.add(day);
                                          }
                                        } else {
                                          biWeeklyDueDays.remove(day);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              if (biWeeklyDueDays.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Selected: ${biWeeklyDueDays.map((d) => "$d${_getDaySuffix(d)}").join(" and ")}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else if (frequency == 'quarterly') ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                value: quarterlyDueMonth,
                                decoration: const InputDecoration(
                                  labelText: 'Month',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 1, child: Text('January')),
                                  DropdownMenuItem(
                                      value: 4, child: Text('April')),
                                  DropdownMenuItem(
                                      value: 7, child: Text('July')),
                                  DropdownMenuItem(
                                      value: 10, child: Text('October')),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setLocalState(() => quarterlyDueMonth = v);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: quarterlyDueDay,
                                decoration: const InputDecoration(
                                  labelText: 'Day',
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    List.generate(31, (i) => i + 1).map((day) {
                                  return DropdownMenuItem(
                                    value: day,
                                    child: Text('$day'),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setLocalState(() => quarterlyDueDay = v);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ] else if (frequency == 'yearly') ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                value: yearlyDueMonth,
                                decoration: const InputDecoration(
                                  labelText: 'Month',
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  'January',
                                  'February',
                                  'March',
                                  'April',
                                  'May',
                                  'June',
                                  'July',
                                  'August',
                                  'September',
                                  'October',
                                  'November',
                                  'December'
                                ].asMap().entries.map((entry) {
                                  return DropdownMenuItem(
                                    value: entry.key + 1,
                                    child: Text(entry.value),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setLocalState(() => yearlyDueMonth = v);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: yearlyDueDay,
                                decoration: const InputDecoration(
                                  labelText: 'Day',
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    List.generate(31, (i) => i + 1).map((day) {
                                  return DropdownMenuItem(
                                    value: day,
                                    child: Text('$day'),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setLocalState(() => yearlyDueDay = v);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      // Due date
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Next Due Date',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: dueDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked == null) return;
                              setLocalState(() {
                                dueDate = picked;
                              });
                            },
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(_fmtDate(dueDate)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Notes
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'Account number, reference, etc.',
                          prefixIcon: Icon(Icons.notes),
                          border: OutlineInputBorder(),
                        ),
                        minLines: 2,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 16),
                      // Reminder section
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.notifications_active,
                                  size: 18,
                                  color: enableReminders
                                      ? Colors.orange
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Payment Reminder',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Switch(
                                  value: enableReminders,
                                  onChanged: (v) {
                                    setLocalState(() {
                                      enableReminders = v;
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (enableReminders) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  const Text('Remind me'),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed: () {
                                          setLocalState(() {
                                            reminderDaysBefore =
                                                (reminderDaysBefore ?? 3) - 1;
                                            if (reminderDaysBefore! < 0)
                                              reminderDaysBefore = 0;
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        color: Colors.orange,
                                        iconSize: 20,
                                      ),
                                      SizedBox(
                                        width: 50,
                                        child: TextField(
                                          keyboardType: TextInputType.number,
                                          controller: TextEditingController(
                                            text: reminderDaysBefore
                                                    ?.toString() ??
                                                '3',
                                          ),
                                          onChanged: (v) {
                                            reminderDaysBefore =
                                                int.tryParse(v);
                                          },
                                          textAlign: TextAlign.center,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 8,
                                            ),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          setLocalState(() {
                                            reminderDaysBefore =
                                                (reminderDaysBefore ?? 3) + 1;
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.add_circle_outline),
                                        color: Colors.orange,
                                        iconSize: 20,
                                      ),
                                    ],
                                  ),
                                  const Text('days before'),
                                  TextButton(
                                    onPressed: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: reminderTime,
                                      );
                                      if (picked == null) return;
                                      setLocalState(() {
                                        reminderTime = picked;
                                      });
                                    },
                                    child: Text(
                                      '${reminderTime.hour.toString().padLeft(2, '0')}:${reminderTime.minute.toString().padLeft(2, '0')}',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final amountText = amountController.text.trim();
                    final amount =
                        amountText.isEmpty ? null : double.tryParse(amountText);
                    if (selectedBillCategory.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bill category is required'),
                        ),
                      );
                      return;
                    }
                    if (amountText.isNotEmpty && amount == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Please enter a valid amount or leave empty for variable bills'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created != true) return;

    try {
      final result = await ApiService.createPayable(
        name: selectedBillCategory,
        amount: amountController.text.trim().isEmpty
            ? 0.0
            : double.parse(amountController.text.trim()),
        frequency: frequency,
        dueDate: dueDate,
        notes: notesController.text.trim(),
        vendor: vendorController.text.trim(),
        // Include due day information
        dueDay: frequency == 'monthly'
            ? monthlyDueDay
            : frequency == 'weekly'
                ? weeklyDueDay
                : frequency == 'biweekly'
                    ? biWeeklyDueDays.isNotEmpty
                        ? biWeeklyDueDays.first
                        : null
                    : frequency == 'quarterly'
                        ? quarterlyDueDay
                        : frequency == 'yearly'
                            ? yearlyDueDay
                            : null,
        dueDays: frequency == 'biweekly' && biWeeklyDueDays.isNotEmpty
            ? biWeeklyDueDays
            : null,
        dueMonth: frequency == 'quarterly'
            ? quarterlyDueMonth
            : frequency == 'yearly'
                ? yearlyDueMonth
                : null,
      );

      // Save reminder settings as part of the payable document if enabled
      if (enableReminders && result['data']?['id'] != null) {
        final eateryId = await _getEateryId();
        final payableId = result['data']['id'];
        if (eateryId != null && payableId != null) {
          try {
            await FirebaseFirestore.instance
                .collection('eateries')
                .doc(eateryId)
                .collection('payables')
                .doc(payableId)
                .update({
              'reminderEnabled': true,
              'reminderDaysBefore': reminderDaysBefore ?? 3,
              'reminderTime': '${reminderTime.hour}:${reminderTime.minute}',
            });
          } catch (e) {
            // Reminder update failed but payable was created
            debugPrint('Failed to update reminder settings: $e');
          }
        }
      }

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payable added')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add payable: $e')),
      );
    }
  }

  Future<void> _showEditPayableDialog(Map<String, dynamic> payable) async {
    if (!_isAdmin) return;

    final id = (payable['id'] ?? '').toString();
    if (id.isEmpty) return;

    final billCategories = [
      'Rent',
      'Utilities',
      'Water',
      'Electricity',
      'Internet',
      'Salaries',
      'Supplies',
      'Equipment',
      'Maintenance',
      'Insurance',
      'Taxes',
      'Other',
    ];

    // Pre-fill controllers with existing data
    String selectedBillCategory = (payable['name'] ?? '').toString();
    final amountController = TextEditingController(
      text: (payable['amount'] is num && (payable['amount'] as num) > 0)
          ? (payable['amount'] as num).toString()
          : '',
    );
    final vendorController = TextEditingController(
      text: (payable['vendor'] ?? '').toString(),
    );
    final notesController = TextEditingController(
      text: (payable['notes'] ?? '').toString(),
    );

    String frequency =
        (payable['frequency'] ?? 'Monthly').toString().toLowerCase();
    if (!['daily', 'weekly', 'biweekly', 'monthly', 'quarterly', 'yearly']
        .contains(frequency)) {
      frequency = 'monthly';
    }

    DateTime? dueDate = _asDate(payable['dueDate']);

    // Due day selection based on frequency (pre-fill from existing data)
    int? monthlyDueDay =
        payable['dueDay'] is int ? payable['dueDay'] as int : null;
    int? weeklyDueDay =
        payable['dueDay'] is int ? payable['dueDay'] as int : null;
    List<int> biWeeklyDueDays = (payable['dueDays'] is List)
        ? (payable['dueDays'] as List).whereType<int>().toList()
        : [];
    int? quarterlyDueMonth =
        payable['dueMonth'] is int ? payable['dueMonth'] as int : null;
    int? quarterlyDueDay =
        payable['dueDay'] is int ? payable['dueDay'] as int : null;
    int? yearlyDueMonth =
        payable['dueMonth'] is int ? payable['dueMonth'] as int : null;
    int? yearlyDueDay =
        payable['dueDay'] is int ? payable['dueDay'] as int : null;

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Bill / Payable'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Bill Category',
                          prefixIcon: Icon(Icons.category),
                        ),
                        value: billCategories.contains(selectedBillCategory)
                            ? selectedBillCategory
                            : null,
                        items: billCategories.map((c) {
                          return DropdownMenuItem(value: c, child: Text(c));
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => selectedBillCategory = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        decoration: const InputDecoration(
                          labelText: 'Amount (leave empty for variable)',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: vendorController,
                        decoration: const InputDecoration(
                          labelText: 'Vendor / Payee (optional)',
                          prefixIcon: Icon(Icons.business),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Frequency',
                          prefixIcon: Icon(Icons.repeat),
                        ),
                        value: frequency,
                        items: const [
                          DropdownMenuItem(
                              value: 'daily', child: Text('Daily')),
                          DropdownMenuItem(
                              value: 'weekly', child: Text('Weekly')),
                          DropdownMenuItem(
                              value: 'biweekly', child: Text('Bi-weekly')),
                          DropdownMenuItem(
                              value: 'monthly', child: Text('Monthly')),
                          DropdownMenuItem(
                              value: 'quarterly', child: Text('Quarterly')),
                          DropdownMenuItem(
                              value: 'yearly', child: Text('Yearly')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              frequency = v;
                              // Reset due day selections when frequency changes
                              monthlyDueDay = null;
                              weeklyDueDay = null;
                              biWeeklyDueDays = [];
                              quarterlyDueDay = null;
                              quarterlyDueMonth = null;
                              yearlyDueDay = null;
                              yearlyDueMonth = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Due day selector based on frequency
                      if (frequency == 'monthly') ...[
                        DropdownButtonFormField<int>(
                          value: monthlyDueDay,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Due day of month',
                            prefixIcon: Icon(Icons.calendar_view_day),
                            border: OutlineInputBorder(),
                            hintText: 'Select day (1-31)',
                          ),
                          items: List.generate(31, (i) => i + 1).map((day) {
                            return DropdownMenuItem(
                              value: day,
                              child: Text('$day${_getDaySuffix(day)}'),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                monthlyDueDay = v;
                                // Update next due date to match selected day
                                final now = DateTime.now();
                                DateTime newDueDate =
                                    DateTime(now.year, now.month, v);
                                // If the day has passed this month, use next month
                                if (newDueDate.isBefore(now)) {
                                  newDueDate =
                                      DateTime(now.year, now.month + 1, v);
                                }
                                dueDate = newDueDate;
                              });
                            }
                          },
                        ),
                      ] else if (frequency == 'weekly') ...[
                        DropdownButtonFormField<int>(
                          value: weeklyDueDay,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Due day of week',
                            prefixIcon: Icon(Icons.calendar_view_week),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Monday')),
                            DropdownMenuItem(value: 2, child: Text('Tuesday')),
                            DropdownMenuItem(
                                value: 3, child: Text('Wednesday')),
                            DropdownMenuItem(value: 4, child: Text('Thursday')),
                            DropdownMenuItem(value: 5, child: Text('Friday')),
                            DropdownMenuItem(value: 6, child: Text('Saturday')),
                            DropdownMenuItem(value: 7, child: Text('Sunday')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => weeklyDueDay = v);
                            }
                          },
                        ),
                      ] else if (frequency == 'biweekly') ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Due days of month (select 2)',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [15, 30, 1, 14, 28, 7, 21].map((day) {
                                  final isSelected =
                                      biWeeklyDueDays.contains(day);
                                  return FilterChip(
                                    label: Text('$day'),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          if (biWeeklyDueDays.length < 2) {
                                            biWeeklyDueDays.add(day);
                                          }
                                        } else {
                                          biWeeklyDueDays.remove(day);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              if (biWeeklyDueDays.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Selected: ${biWeeklyDueDays.map((d) => "$d${_getDaySuffix(d)}").join(" and ")}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ] else if (frequency == 'quarterly') ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                value: quarterlyDueMonth,
                                decoration: const InputDecoration(
                                  labelText: 'Month',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                      value: 1, child: Text('January')),
                                  DropdownMenuItem(
                                      value: 4, child: Text('April')),
                                  DropdownMenuItem(
                                      value: 7, child: Text('July')),
                                  DropdownMenuItem(
                                      value: 10, child: Text('October')),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => quarterlyDueMonth = v);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: quarterlyDueDay,
                                decoration: const InputDecoration(
                                  labelText: 'Day',
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    List.generate(31, (i) => i + 1).map((day) {
                                  return DropdownMenuItem(
                                    value: day,
                                    child: Text('$day'),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => quarterlyDueDay = v);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ] else if (frequency == 'yearly') ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                value: yearlyDueMonth,
                                decoration: const InputDecoration(
                                  labelText: 'Month',
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  'January',
                                  'February',
                                  'March',
                                  'April',
                                  'May',
                                  'June',
                                  'July',
                                  'August',
                                  'September',
                                  'October',
                                  'November',
                                  'December'
                                ].asMap().entries.map((entry) {
                                  return DropdownMenuItem(
                                    value: entry.key + 1,
                                    child: Text(entry.value),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => yearlyDueMonth = v);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: yearlyDueDay,
                                decoration: const InputDecoration(
                                  labelText: 'Day',
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    List.generate(31, (i) => i + 1).map((day) {
                                  return DropdownMenuItem(
                                    value: day,
                                    child: Text('$day'),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => yearlyDueDay = v);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: dueDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setState(() => dueDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Next Due Date',
                            prefixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Text(
                            dueDate != null
                                ? _fmtDate(dueDate!)
                                : 'Select date',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          prefixIcon: Icon(Icons.notes),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final amountText = amountController.text.trim();
                    final amount =
                        amountText.isEmpty ? null : double.tryParse(amountText);
                    if (selectedBillCategory.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bill category is required'),
                        ),
                      );
                      return;
                    }
                    if (amountText.isNotEmpty && amount == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Please enter a valid amount or leave empty for variable bills'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (updated != true) return;

    try {
      await ApiService.updatePayable(
        id,
        name: selectedBillCategory,
        amount: amountController.text.trim().isEmpty
            ? 0.0
            : double.parse(amountController.text.trim()),
        frequency: frequency,
        dueDate: dueDate,
        notes: notesController.text.trim(),
        vendor: vendorController.text.trim(),
        // Include due day information
        dueDay: frequency == 'monthly'
            ? monthlyDueDay
            : frequency == 'weekly'
                ? weeklyDueDay
                : frequency == 'biweekly'
                    ? biWeeklyDueDays.isNotEmpty
                        ? biWeeklyDueDays.first
                        : null
                    : frequency == 'quarterly'
                        ? quarterlyDueDay
                        : frequency == 'yearly'
                            ? yearlyDueDay
                            : null,
        dueDays: frequency == 'biweekly' && biWeeklyDueDays.isNotEmpty
            ? biWeeklyDueDays
            : null,
        dueMonth: frequency == 'quarterly'
            ? quarterlyDueMonth
            : frequency == 'yearly'
                ? yearlyDueMonth
                : null,
      );

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update bill: $e')),
      );
    }
  }

  List<Map<String, dynamic>> _filterByQuery(
    List<Map<String, dynamic>> items, {
    required List<String> fields,
  }) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items.where((m) {
      for (final f in fields) {
        final v = (m[f] ?? '').toString().toLowerCase();
        if (v.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  Widget _buildExpensesTab() {
    final items = _filterByQuery(
      _expenses,
      fields: const ['category', 'vendor', 'notes'],
    );

    final total = items.fold<double>(
      0,
      (sum, e) =>
          sum + ((e['amount'] is num) ? (e['amount'] as num).toDouble() : 0),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Total: ${_fmtMoney(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (_isAdmin)
                FilledButton.icon(
                  onPressed: _showAddExpenseDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No expenses yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final e = items[index];
                    final id = (e['id'] ?? '').toString();
                    final category = (e['category'] ?? '').toString();
                    final vendor = (e['vendor'] ?? '').toString();
                    final amount = (e['amount'] is num)
                        ? (e['amount'] as num).toDouble()
                        : 0.0;
                    final date = _asDate(e['date']) ?? _asDate(e['createdAt']);
                    final notes = (e['notes'] ?? '').toString();

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        title: Text(category.isEmpty ? 'Expense' : category),
                        subtitle: Text(
                          '${date == null ? '' : _fmtDate(date)}${vendor.trim().isEmpty ? '' : ' • $vendor'}${notes.trim().isEmpty ? '' : '\n$notes'}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _fmtMoney(amount),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            if (_isAdmin && id.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (context) {
                                      return AlertDialog(
                                        title: const Text('Delete expense?'),
                                        content: const Text(
                                            'This action cannot be undone.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context)
                                                    .pop(false),
                                            child: const Text('Cancel'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                  if (ok != true) return;
                                  try {
                                    await ApiService.deleteExpense(id);
                                    await _load();
                                  } catch (err) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Failed to delete expense: $err'),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPayablesTab() {
    final items = _filterByQuery(
      _payables,
      fields: const ['name', 'frequency', 'notes', 'status'],
    );

    items.sort((a, b) {
      final ad = _asDate(a['dueDate']);
      final bd = _asDate(b['dueDate']);
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Payables',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (_isAdmin)
                FilledButton.icon(
                  onPressed: _showAddPayableDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No payables yet'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final p = items[index];
                    final id = (p['id'] ?? '').toString();
                    final name = (p['name'] ?? '').toString();
                    final frequency = (p['frequency'] ?? '').toString();
                    final status = (p['status'] ?? 'unpaid').toString();
                    final amount = (p['amount'] is num)
                        ? (p['amount'] as num).toDouble()
                        : 0.0;
                    final due = _asDate(p['dueDate']);
                    final notes = (p['notes'] ?? '').toString();

                    final isPaid = status.toLowerCase().trim() == 'paid';
                    final hasAmount =
                        (p['amount'] is num) && (p['amount'] as num) > 0;

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: InkWell(
                        onTap: _isAdmin && id.isNotEmpty
                            ? () => _showEditPayableDialog(p)
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        child: ListTile(
                          title: Text(name.isEmpty ? 'Payable' : name),
                          subtitle: Text(
                            '${due == null ? '' : 'Due: ${_fmtDate(due)}'}${frequency.trim().isEmpty ? '' : ' • $frequency'}${notes.trim().isEmpty ? '' : '\n$notes'}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          leading: Icon(
                            isPaid
                                ? Icons.check_circle_outline
                                : Icons.schedule_outlined,
                            color: isPaid ? Colors.green : Colors.orange,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                hasAmount ? _fmtMoney(amount) : 'Variable',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: hasAmount ? null : Colors.grey,
                                  fontStyle:
                                      hasAmount ? null : FontStyle.italic,
                                ),
                              ),
                              if (_isAdmin && id.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: isPaid ? 'Mark unpaid' : 'Mark paid',
                                  onPressed: () async {
                                    try {
                                      await ApiService.updatePayableStatus(
                                        id,
                                        status: isPaid ? 'unpaid' : 'paid',
                                      );
                                      await _load();
                                    } catch (err) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'Failed to update payable: $err'),
                                        ),
                                      );
                                    }
                                  },
                                  icon: Icon(
                                    isPaid
                                        ? Icons.undo_outlined
                                        : Icons.check_outlined,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (context) {
                                        return AlertDialog(
                                          title: const Text('Delete payable?'),
                                          content: const Text(
                                              'This action cannot be undone.'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .pop(false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.of(context)
                                                      .pop(true),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                    if (ok != true) return;
                                    try {
                                      await ApiService.deletePayable(id);
                                      await _load();
                                    } catch (err) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'Failed to delete payable: $err'),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              leading: widget.onOpenDrawer != null
                  ? IconButton(
                      icon: const Icon(Icons.menu),
                      tooltip: 'Menu',
                      onPressed: widget.onOpenDrawer,
                    )
                  : (Navigator.of(context).canPop()
                      ? IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).maybePop(),
                        )
                      : null),
              title: const Text('Finance'),
              bottom: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
                  Tab(icon: Icon(Icons.receipt_long), text: 'Expenses'),
                  Tab(icon: Icon(Icons.payment), text: 'Payables'),
                  Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
                ],
              ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Failed to load finance data: $_error'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDashboardLayout(),
                    _buildExpensesTab(),
                    _buildPayablesTab(),
                    _buildMonthlyAnalyticsTab(),
                  ],
                ),
    );
  }

  Widget _buildDashboardLayout() {
    // Calculate totals and upcoming items
    final totalExpenses = _expenses.fold<double>(
      0,
      (sum, e) =>
          sum + ((e['amount'] is num) ? (e['amount'] as num).toDouble() : 0),
    );

    final totalPayables = _payables
        .where(
            (p) => (p['status'] ?? 'unpaid').toString().toLowerCase() != 'paid')
        .fold<double>(
          0,
          (sum, p) =>
              sum +
              ((p['amount'] is num) ? (p['amount'] as num).toDouble() : 0),
        );

    // Get upcoming payables (due within 7 days and not paid)
    final now = DateTime.now();
    final upcomingPayables = _payables.where((p) {
      final dueDate = _asDate(p['dueDate']);
      final status = (p['status'] ?? 'unpaid').toString().toLowerCase();
      if (dueDate == null || status == 'paid') return false;
      final daysUntilDue = dueDate.difference(now).inDays;
      return daysUntilDue >= -7 && daysUntilDue <= 7;
    }).toList();

    upcomingPayables.sort((a, b) {
      final ad = _asDate(a['dueDate']);
      final bd = _asDate(b['dueDate']);
      if (ad == null || bd == null) return 0;
      return ad.compareTo(bd);
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Cards Row
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Total Expenses',
                  amount: totalExpenses,
                  icon: Icons.account_balance_wallet,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Due Payables',
                  amount: totalPayables,
                  icon: Icons.payment,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Quick Actions Section
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  title: 'Add Expense',
                  subtitle: 'Record new expense',
                  icon: Icons.add_circle,
                  color: Colors.green,
                  onTap: _showAddExpenseDialog,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  title: 'Add Bill',
                  subtitle: 'Set recurring payable',
                  icon: Icons.repeat,
                  color: Colors.purple,
                  onTap: _showAddPayableDialog,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Reminders Section (Upcoming Payables)
          if (upcomingPayables.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Reminders',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Could navigate to payables tab or show all
                  },
                  child: Text('${upcomingPayables.length} upcoming'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...upcomingPayables.take(3).map((p) => _buildReminderCard(p)),
            const SizedBox(height: 20),
          ],

          // Recent Expenses Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Expenses',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_expenses.isNotEmpty)
                TextButton(
                  onPressed: () {
                    // Could expand or navigate to full list
                  },
                  child: Text('${_expenses.length} total'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_expenses.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No expenses yet\nTap "Add Expense" to record your first expense',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._expenses.take(5).map((e) => _buildExpenseItem(e)),

          const SizedBox(height: 20),

          // Navigation to full tabs - Compact layout
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showFullExpensesList(),
                icon: const Icon(Icons.list, size: 18),
                label: const Text('All Expenses'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showFullPayablesList(),
                icon: const Icon(Icons.payment, size: 18),
                label: const Text('All Payables'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  // Navigate to Staff tab using the callback
                  widget.onNavigate?.call(5);
                },
                icon: const Icon(Icons.people, size: 18),
                label: const Text('Staff Payroll'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _fmtMoney(amount),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: _isAdmin ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBillDetailsDialog(Map<String, dynamic> p) async {
    final name = (p['name'] ?? 'Bill').toString();
    final amount = (p['amount'] is num) ? (p['amount'] as num).toDouble() : 0.0;
    final dueDate = _asDate(p['dueDate']);
    final frequency = (p['frequency'] ?? '').toString();
    final status = (p['status'] ?? 'unpaid').toString();
    final vendor = (p['vendor'] ?? '').toString();
    final notes = (p['notes'] ?? '').toString();
    final isPaid = status.toLowerCase().trim() == 'paid';
    final hasAmount = amount > 0;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                isPaid ? Icons.check_circle : Icons.notifications,
                color: isPaid ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(name)),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Status', isPaid ? 'Paid' : 'Unpaid',
                      isPaid ? Colors.green : Colors.orange),
                  const Divider(),
                  _buildDetailRow(
                      'Amount', hasAmount ? _fmtMoney(amount) : 'Variable'),
                  _buildDetailRow('Due Date',
                      dueDate != null ? _fmtDate(dueDate) : 'Not set'),
                  _buildDetailRow('Frequency',
                      frequency.isNotEmpty ? frequency : 'Not set'),
                  if (vendor.isNotEmpty) _buildDetailRow('Vendor', vendor),
                  if (notes.isNotEmpty) _buildDetailRow('Notes', notes),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (_isAdmin)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showEditPayableDialog(p);
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit Bill'),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(Map<String, dynamic> p) {
    final name = (p['name'] ?? 'Payable').toString();
    final amount = (p['amount'] is num) ? (p['amount'] as num).toDouble() : 0.0;
    final dueDate = _asDate(p['dueDate']);
    final frequency = (p['frequency'] ?? '').toString();

    final daysUntil =
        dueDate != null ? dueDate.difference(DateTime.now()).inDays : null;
    String dueText;
    Color dueColor;

    if (daysUntil == null) {
      dueText = 'No due date';
      dueColor = Colors.grey;
    } else if (daysUntil < 0) {
      dueText = '${daysUntil.abs()} days overdue';
      dueColor = Colors.red;
    } else if (daysUntil == 0) {
      dueText = 'Due today';
      dueColor = Colors.orange;
    } else if (daysUntil == 1) {
      dueText = 'Due tomorrow';
      dueColor = Colors.orange;
    } else {
      dueText = 'Due in $daysUntil days';
      dueColor = Colors.green;
    }

    return InkWell(
      onTap: () {
        // Show view-only bill details dialog first
        _showBillDetailsDialog(p);
      },
      borderRadius: BorderRadius.circular(12),
      child: Card(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: dueColor.withOpacity(0.3)),
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: dueColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.notifications, color: dueColor, size: 20),
          ),
          title: Text(name),
          subtitle: Text(
            '$dueText${frequency.isNotEmpty ? ' • $frequency' : ''}',
            style: TextStyle(color: dueColor, fontSize: 12),
          ),
          trailing: Text(
            _fmtMoney(amount),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseItem(Map<String, dynamic> e) {
    final category = (e['category'] ?? '').toString();
    final vendor = (e['vendor'] ?? '').toString();
    final amount = (e['amount'] is num) ? (e['amount'] as num).toDouble() : 0.0;
    final date = _asDate(e['date']) ?? _asDate(e['createdAt']);

    final categoryIcons = {
      'Ingredients': Icons.restaurant,
      'Utilities': Icons.electric_bolt,
      'Rent': Icons.home,
      'Salaries': Icons.people,
      'Equipment': Icons.build,
      'Maintenance': Icons.handyman,
      'Marketing': Icons.campaign,
      'Supplies': Icons.inventory,
      'Transportation': Icons.local_shipping,
      'Taxes': Icons.account_balance,
      'Insurance': Icons.shield,
      'Other': Icons.more_horiz,
    };

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            categoryIcons[category] ?? Icons.receipt,
            color: Colors.blue,
            size: 20,
          ),
        ),
        title: Text(category.isEmpty ? 'Expense' : category),
        subtitle: Text(
          '${date != null ? _fmtDate(date) : ''}${vendor.isNotEmpty ? ' • $vendor' : ''}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Text(
          _fmtMoney(amount),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlyAnalyticsTab() {
    return _MonthlyAnalyticsView(
      expenses: _expenses,
      payables: _payables,
      fmtMoney: _fmtMoney,
      asDate: _asDate,
    );
  }

  void _showFullExpensesList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'All Expenses',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: _buildExpensesTab(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showFullPayablesList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'All Payables',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: _buildPayablesTab(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Monthly Analytics View Widget
class _MonthlyAnalyticsView extends StatefulWidget {
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> payables;
  final String Function(num) fmtMoney;
  final DateTime? Function(dynamic) asDate;

  const _MonthlyAnalyticsView({
    required this.expenses,
    required this.payables,
    required this.fmtMoney,
    required this.asDate,
  });

  @override
  State<_MonthlyAnalyticsView> createState() => _MonthlyAnalyticsViewState();
}

class _MonthlyAnalyticsViewState extends State<_MonthlyAnalyticsView> {
  int _selectedMonthOffset = 0; // 0 = current month, -1 = last month, etc.

  DateTime get _selectedMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _selectedMonthOffset, 1);
  }

  String get _monthName {
    final month = _selectedMonth;
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[month.month - 1]} ${month.year}';
  }

  List<Map<String, dynamic>> get _monthExpenses {
    final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

    return widget.expenses.where((e) {
      final date = widget.asDate(e['date']) ?? widget.asDate(e['createdAt']);
      if (date == null) return false;
      return date.isAfter(monthStart.subtract(const Duration(days: 1))) &&
          date.isBefore(monthEnd.add(const Duration(days: 1)));
    }).toList();
  }

  List<Map<String, dynamic>> get _monthPayables {
    return widget.payables.where((p) {
      final dueDate = widget.asDate(p['dueDate']);
      if (dueDate == null) return false;
      return dueDate.year == _selectedMonth.year &&
          dueDate.month == _selectedMonth.month;
    }).toList();
  }

  Map<String, double> get _expensesByCategory {
    final map = <String, double>{};
    for (final e in _monthExpenses) {
      final category = (e['category'] ?? 'Other').toString();
      final amount =
          (e['amount'] is num) ? (e['amount'] as num).toDouble() : 0.0;
      map[category] = (map[category] ?? 0) + amount;
    }
    return map;
  }

  double get _totalMonthExpenses {
    return _monthExpenses.fold<double>(
      0,
      (sum, e) =>
          sum + ((e['amount'] is num) ? (e['amount'] as num).toDouble() : 0),
    );
  }

  double get _totalMonthPayables {
    return _monthPayables.fold<double>(
      0,
      (sum, p) =>
          sum + ((p['amount'] is num) ? (p['amount'] as num).toDouble() : 0),
    );
  }

  double get _previousMonthTotal {
    final now = DateTime.now();
    final prevMonth =
        DateTime(now.year, now.month + _selectedMonthOffset - 1, 1);
    final prevStart = DateTime(prevMonth.year, prevMonth.month, 1);
    final prevEnd = DateTime(prevMonth.year, prevMonth.month + 1, 0);

    final prevExpenses = widget.expenses.where((e) {
      final date = widget.asDate(e['date']) ?? widget.asDate(e['createdAt']);
      if (date == null) return false;
      return date.isAfter(prevStart.subtract(const Duration(days: 1))) &&
          date.isBefore(prevEnd.add(const Duration(days: 1)));
    });

    return prevExpenses.fold<double>(
      0,
      (sum, e) =>
          sum + ((e['amount'] is num) ? (e['amount'] as num).toDouble() : 0),
    );
  }

  double get _monthOverMonthChange {
    final prev = _previousMonthTotal;
    if (prev == 0) return 0;
    return ((_totalMonthExpenses - prev) / prev) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final categoryData = _expensesByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month Selector
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() => _selectedMonthOffset--),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      _monthName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _selectedMonthOffset < 0
                        ? () => setState(() => _selectedMonthOffset++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildAnalyticsCard(
                  title: 'Total Expenses',
                  amount: _totalMonthExpenses,
                  icon: Icons.account_balance_wallet,
                  color: Colors.red.shade400,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAnalyticsCard(
                  title: 'Due Payables',
                  amount: _totalMonthPayables,
                  icon: Icons.payment,
                  color: Colors.orange.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Month-over-Month Comparison
          Card(
            color: _monthOverMonthChange > 0
                ? Colors.red.shade50
                : _monthOverMonthChange < 0
                    ? Colors.green.shade50
                    : Colors.grey.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _monthOverMonthChange > 0
                        ? Icons.trending_up
                        : _monthOverMonthChange < 0
                            ? Icons.trending_down
                            : Icons.trending_flat,
                    color: _monthOverMonthChange > 0
                        ? Colors.red
                        : _monthOverMonthChange < 0
                            ? Colors.green
                            : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'vs Previous Month',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          '${_monthOverMonthChange >= 0 ? '+' : ''}${_monthOverMonthChange.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _monthOverMonthChange > 0
                                ? Colors.red
                                : _monthOverMonthChange < 0
                                    ? Colors.green
                                    : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Category Breakdown
          const Text(
            'Expenses by Category',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          if (categoryData.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.pie_chart_outline,
                        size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'No expenses recorded for $_monthName',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          else
            ...categoryData.map((entry) {
              final percent = _totalMonthExpenses > 0
                  ? (entry.value / _totalMonthExpenses * 100)
                  : 0.0;
              return _buildCategoryBar(
                category: entry.key,
                amount: entry.value,
                percent: percent,
                color: _getCategoryColor(entry.key),
              );
            }),

          const SizedBox(height: 24),

          // Transaction Count
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Transactions',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '${_monthExpenses.length}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Average per transaction
          if (_monthExpenses.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Average per Transaction',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      widget.fmtMoney(
                          _totalMonthExpenses / _monthExpenses.length),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCard({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              widget.fmtMoney(amount),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBar({
    required String category,
    required double amount,
    required double percent,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                category,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                '${percent.toStringAsFixed(1)}% • ${widget.fmtMoney(amount)}',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    final colors = {
      'Ingredients': Colors.orange,
      'Utilities': Colors.yellow.shade700,
      'Rent': Colors.blue,
      'Salaries': Colors.green,
      'Equipment': Colors.purple,
      'Maintenance': Colors.brown,
      'Marketing': Colors.pink,
      'Supplies': Colors.teal,
      'Transportation': Colors.indigo,
      'Taxes': Colors.red,
      'Insurance': Colors.cyan,
      'Other': Colors.grey,
    };
    return colors[category] ?? Colors.blue;
  }
}
