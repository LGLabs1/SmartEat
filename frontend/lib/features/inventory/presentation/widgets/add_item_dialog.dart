import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../services/api_service.dart';
import '../../../../../models/inventory_item.dart';
import '../../../../../theme.dart';
import '../../data/models/stock_adjustment.dart';
import 'adjustment_dialog.dart';

class AddItemDialog extends StatefulWidget {
  final String? initialCategory;
  final InventoryItem? initialItem;
  final Future<InventoryItem?> Function(StockAdjustment adjustment)?
      onAdjustStock;
  final String? performedBy;

  const AddItemDialog({
    Key? key,
    this.initialCategory,
    this.initialItem,
    this.onAdjustStock,
    this.performedBy,
  }) : super(key: key);

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();
  final _currentStockController = TextEditingController();
  final _minStockController = TextEditingController();
  final _reorderPointController = TextEditingController();
  final _maxStockController = TextEditingController();
  final _safetyStockController = TextEditingController();
  final _leadTimeController = TextEditingController();
  final _unitController = TextEditingController();
  final _unitCostController = TextEditingController();
  final _sellingPriceController = TextEditingController();
  final _supplierController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isLoading = false;

  String? _selectedCategory;
  String? _selectedUnit;
  String _consumptionMode = 'direct';

  final List<String> _categories = const [
    'Vegetables',
    'Meat',
    'Dairy',
    'Grains',
    'Spices',
    'Beverages',
  ];

  final List<String> _units = const [
    'pcs',
    'kg',
    'g',
    'L',
    'mL',
    'pack',
    'bottle',
    'box',
    'can',
  ];

  bool get isEdit => widget.initialItem != null;

  List<String> get _categoryOptions {
    final values = <String>{..._categories};
    final initial = widget.initialItem?.category ?? widget.initialCategory;
    if (initial != null && initial.isNotEmpty) values.add(initial);
    return values.toList()..sort();
  }

  List<String> get _unitOptions {
    final values = <String>{..._units};
    final initial = widget.initialItem?.unit;
    if (initial != null && initial.isNotEmpty) values.add(initial);
    return values.toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    final initialCategory = item?.category ?? widget.initialCategory;
    if (initialCategory != null && initialCategory.isNotEmpty) {
      _selectedCategory = initialCategory;
      _categoryController.text = initialCategory;
    }
    _selectedUnit = (item?.unit ?? _units.first).trim().isNotEmpty
        ? (item?.unit ?? _units.first).trim()
        : _units.first;
    _unitController.text = _selectedUnit!;
    _sellingPriceController.text = '0';
    _currentStockController.text = '0';
    _minStockController.text = '0';
    _reorderPointController.text = '0';
    _maxStockController.text = '0';
    _safetyStockController.text = '0';
    _leadTimeController.text = '0';

    if (item != null) {
      _nameController.text = item.name;
      _skuController.text = item.sku ?? '';
      _descriptionController.text = item.description ?? '';
      _currentStockController.text = item.currentStock.toStringAsFixed(2);
      _minStockController.text = item.minStock.toStringAsFixed(2);
      _reorderPointController.text = item.reorderPoint.toStringAsFixed(2);
      _maxStockController.text = item.maxStock.toStringAsFixed(2);
      _safetyStockController.text = item.safetyStock.toStringAsFixed(2);
      _leadTimeController.text = item.leadTimeDays.toString();
      _unitController.text = item.unit;
      _unitCostController.text = item.unitCost.toStringAsFixed(2);
      _sellingPriceController.text = item.sellingPrice.toStringAsFixed(2);
      _supplierController.text = item.supplier;
      _notesController.text = item.notes ?? '';
      _consumptionMode = item.consumptionMode == ConsumptionMode.direct
          ? 'direct'
          : 'recipe_pending';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _currentStockController.dispose();
    _minStockController.dispose();
    _reorderPointController.dispose();
    _maxStockController.dispose();
    _safetyStockController.dispose();
    _leadTimeController.dispose();
    _unitController.dispose();
    _unitCostController.dispose();
    _sellingPriceController.dispose();
    _supplierController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final extra = <String, dynamic>{
        'reorderPoint': _reorderPointController.text.isEmpty
            ? double.parse(_minStockController.text)
            : double.parse(_reorderPointController.text),
        'maxStock': _maxStockController.text.isEmpty
            ? 0.0
            : double.parse(_maxStockController.text),
        'safetyStock': _safetyStockController.text.isEmpty
            ? 0.0
            : double.parse(_safetyStockController.text),
        'leadTimeDays': int.tryParse(_leadTimeController.text) ?? 0,
        'consumptionMode': _consumptionMode,
      };
      if (_skuController.text.trim().isNotEmpty) {
        extra['sku'] = _skuController.text.trim();
      }
      if (_descriptionController.text.trim().isNotEmpty) {
        extra['description'] = _descriptionController.text.trim();
      }
      if (_notesController.text.trim().isNotEmpty) {
        extra['notes'] = _notesController.text.trim();
      }

      final name = _nameController.text.trim();
      final category = _categoryController.text.trim().isEmpty
          ? (_selectedCategory ?? 'Other')
          : _categoryController.text.trim();
      final unit = _unitController.text.trim().isEmpty
          ? (_selectedUnit ?? 'pcs')
          : _unitController.text.trim();
      final minStock = double.parse(_minStockController.text);
      final unitCost = double.parse(_unitCostController.text);
      final sellingPrice = _sellingPriceController.text.isEmpty
          ? 0.0
          : double.parse(_sellingPriceController.text);
      final supplier = _supplierController.text.trim();

      late final Map<String, dynamic> response;
      if (isEdit) {
        extra['unit'] = unit;
        extra['sku'] = _skuController.text.trim();
        extra['description'] = _descriptionController.text.trim();
        extra['notes'] = _notesController.text.trim();
        if (widget.initialItem?.purchaseUnit != null) {
          extra['purchaseUnit'] = widget.initialItem!.purchaseUnit;
        }
        if (widget.initialItem?.saleUnit != null) {
          extra['saleUnit'] = widget.initialItem!.saleUnit;
        }
        if (widget.initialItem?.conversionFactor != null) {
          extra['conversionFactor'] = widget.initialItem!.conversionFactor;
        }
        response = await ApiService.updateInventoryItem(
          widget.initialItem!.id,
          name: name,
          category: category,
          minStock: minStock,
          unitCost: unitCost,
          sellingPrice: sellingPrice,
          supplier: supplier,
          extra: extra,
        );
      } else {
        response = await ApiService.createInventoryItem(
          name: name,
          category: category,
          currentStock: double.parse(_currentStockController.text),
          minStock: minStock,
          unit: unit,
          unitCost: unitCost,
          sellingPrice: sellingPrice,
          supplier: supplier,
          extra: extra,
        );
      }

      if (!mounted) return;
      setState(() => _isLoading = false);

      final data = response['data'] as Map<String, dynamic>?;
      if (data != null) {
        final item = InventoryItem.fromJson(data);
        Navigator.of(context).pop(item);
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to ${isEdit ? 'update' : 'add'} item: ${e.toString()}',
          ),
        ),
      );
    }
  }

  InputDecoration _dec(String label,
      {String? helper, String? prefix, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixText: prefix,
      suffixIcon: suffixIcon,
      border: const OutlineInputBorder(),
      isDense: true,
    );
  }

  String _formatQty(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  Future<void> _openAdjustStock() async {
    final item = widget.initialItem;
    if (item == null || widget.onAdjustStock == null) return;
    final adjustment = await showDialog<StockAdjustment>(
      context: context,
      builder: (_) => AdjustmentDialog(
        items: [item],
        initialItem: item,
        performedBy: widget.performedBy,
      ),
    );
    if (adjustment == null) return;
    final updated = await widget.onAdjustStock!(adjustment);
    if (updated != null && mounted) {
      setState(() =>
          _currentStockController.text = _formatQty(updated.currentStock));
    }
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dashboardTheme,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration:
                    const BoxDecoration(gradient: AppTheme.sageGradient),
                child: Row(
                  children: [
                    Icon(
                      isEdit ? Icons.edit_outlined : Icons.add_box_outlined,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit
                                ? 'Edit Inventory Item'
                                : 'Add Inventory Item',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                          ),
                          Text(
                            'Fields marked * are required',
                            style: const TextStyle(
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final twoCol = constraints.maxWidth >= 560;
                        final half = twoCol
                            ? (constraints.maxWidth - 16) / 2
                            : constraints.maxWidth;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionTitle(context, Icons.info_outline,
                                'Basic Information'),
                            TextFormField(
                              controller: _nameController,
                              decoration: _dec('Item Name *'),
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'Item name is required'
                                      : null,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                SizedBox(
                                  width: half,
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedCategory,
                                    decoration: _dec('Category *'),
                                    isExpanded: true,
                                    items: _categoryOptions
                                        .map((cat) => DropdownMenuItem(
                                            value: cat, child: Text(cat)))
                                        .toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedCategory = value;
                                        _categoryController.text = value ?? '';
                                      });
                                    },
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                            ? 'Category is required'
                                            : null,
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: TextFormField(
                                    controller: _skuController,
                                    decoration: _dec('SKU / Barcode',
                                        helper: 'Optional'),
                                    textInputAction: TextInputAction.next,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _descriptionController,
                              decoration: _dec('Description',
                                  helper: 'Optional short description'),
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 24),
                            _sectionTitle(context, Icons.straighten,
                                'Units & Stock Levels'),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                SizedBox(
                                  width: half,
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedUnit,
                                    decoration: _dec('Unit of Measure *'),
                                    isExpanded: true,
                                    items: _unitOptions
                                        .map((unit) => DropdownMenuItem(
                                            value: unit, child: Text(unit)))
                                        .toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedUnit = value;
                                        _unitController.text = value ?? '';
                                      });
                                    },
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                            ? 'Unit is required'
                                            : null,
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: TextFormField(
                                    controller: _currentStockController,
                                    enabled: !isEdit,
                                    decoration: _dec(
                                      'Current Stock *',
                                      helper: isEdit
                                          ? 'Quantity is changed through Adjust Stock'
                                          : null,
                                      suffixIcon:
                                          isEdit && widget.onAdjustStock != null
                                              ? IconButton(
                                                  tooltip: 'Adjust stock',
                                                  icon: const Icon(Icons.tune),
                                                  onPressed: _openAdjustStock,
                                                )
                                              : null,
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*'))
                                    ],
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Current stock is required';
                                      }
                                      final d = double.tryParse(value);
                                      if (d == null || d < 0)
                                        return 'Enter valid stock';
                                      return null;
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: TextFormField(
                                    controller: _minStockController,
                                    decoration: _dec('Min Stock *',
                                        helper: 'Low-stock alert threshold'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*'))
                                    ],
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Min stock is required';
                                      }
                                      final d = double.tryParse(value);
                                      if (d == null || d < 0)
                                        return 'Enter valid stock';
                                      return null;
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: TextFormField(
                                    controller: _reorderPointController,
                                    decoration: _dec('Reorder Point',
                                        helper:
                                            'Reorder when stock reaches this'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*'))
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: TextFormField(
                                    controller: _maxStockController,
                                    decoration: _dec('Max Stock',
                                        helper: 'Used for restock suggestions'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*'))
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: TextFormField(
                                    controller: _safetyStockController,
                                    decoration: _dec('Safety Stock',
                                        helper: 'Buffer above min stock'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*'))
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: TextFormField(
                                    controller: _leadTimeController,
                                    decoration: _dec('Lead Time (days)',
                                        helper: 'Supplier delivery time'),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _sectionTitle(
                                context, Icons.payments_outlined, 'Pricing'),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                SizedBox(
                                  width: half,
                                  child: TextFormField(
                                    controller: _unitCostController,
                                    decoration:
                                        _dec('Unit Cost *', prefix: '₱ '),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*'))
                                    ],
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Unit cost is required';
                                      }
                                      final d = double.tryParse(value);
                                      if (d == null || d < 0)
                                        return 'Enter valid cost';
                                      return null;
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: TextFormField(
                                    controller: _sellingPriceController,
                                    decoration: _dec('Selling Price',
                                        prefix: '₱ ', helper: 'Optional'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d*'))
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _sectionTitle(
                                context,
                                Icons.settings_suggest_outlined,
                                'Inventory Settings'),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                SizedBox(
                                  width: half,
                                  child: DropdownButtonFormField<String>(
                                    value: _consumptionMode,
                                    decoration: _dec('Consumption Mode *'),
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'direct',
                                        child: Text(
                                            'Direct - decrement stock on sales'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'recipe_pending',
                                        child: Text(
                                            'Recipe ingredient - awaiting dish mapping'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value != null)
                                        setState(
                                            () => _consumptionMode = value);
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: TextFormField(
                                    controller: _supplierController,
                                    decoration:
                                        _dec('Supplier', helper: 'Optional'),
                                    textInputAction: TextInputAction.next,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _notesController,
                              decoration: _dec('Notes',
                                  helper: 'Optional internal notes'),
                              maxLines: 3,
                              minLines: 2,
                            ),
                          ],
                        );
                      },
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
                      onPressed:
                          _isLoading ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _saveItem,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(isEdit ? 'Save Changes' : 'Add Item'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
