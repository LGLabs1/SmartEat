import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/inventory/domain/services/recipe_consumption.dart';
import '../features/inventory/domain/services/unit_conversion.dart';
import '../services/firebase_service.dart';
import '../theme.dart';
import '../widgets/dashboard/section_card.dart';

class RecipeEditorPage extends StatefulWidget {
  final Map<String, dynamic>? recipe;
  const RecipeEditorPage({super.key, this.recipe});

  @override
  State<RecipeEditorPage> createState() => _RecipeEditorPageState();
}

class _RecipeEditorPageState extends State<RecipeEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  List<Map<String, dynamic>> _ingredients = [];
  List<Map<String, dynamic>> _inventoryItems = [];
  List<Map<String, dynamic>> _menuItems = [];
  List<String> _selectedMenuItemIds = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String _menuSearch = '';

  @override
  void initState() {
    super.initState();
    final recipe = widget.recipe;
    if (recipe != null) {
      final normalized = RecipeConsumption.normalizeRecipe(recipe);
      _nameController.text = (normalized['name'] ?? '').toString();
      _descController.text = (normalized['description'] ?? '').toString();
      final ingredients = normalized['ingredients'];
      if (ingredients is List) {
        _ingredients = ingredients
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      final linked = normalized['linkedMenuItemIds'];
      if (linked is List) {
        _selectedMenuItemIds = linked.map((e) => e.toString()).toList();
      }
    }
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final inventory = await FirebaseService.getInventoryItems();
      final menu = await FirebaseService.getMenuItems();
      if (!mounted) return;
      setState(() {
        _inventoryItems = List<Map<String, dynamic>>.from(inventory);
        _menuItems = List<Map<String, dynamic>>.from(menu);
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _recomputeCost() {
    final updated = <Map<String, dynamic>>[];
    for (final raw in _ingredients) {
      final ingredient = Map<String, dynamic>.from(raw);
      final qtyRaw = ingredient['quantityPerServing'] ?? ingredient['quantity'];
      final qty = qtyRaw is num
          ? qtyRaw.toDouble()
          : double.tryParse(qtyRaw?.toString() ?? '') ?? 0.0;
      final unitCostRaw = ingredient['unitCost'];
      final unitCost = unitCostRaw is num
          ? unitCostRaw.toDouble()
          : double.tryParse(unitCostRaw?.toString() ?? '') ?? 0.0;
      ingredient['quantity'] = qty;
      ingredient['quantityPerServing'] = qty;
      ingredient['unitCost'] = unitCost;
      ingredient['totalCost'] = qty * unitCost;
      updated.add(ingredient);
    }
    setState(() => _ingredients = updated);
  }

  double get _costPerServing {
    var sum = 0.0;
    for (final ingredient in _ingredients) {
      final qtyRaw = ingredient['quantityPerServing'] ?? ingredient['quantity'];
      final qty = qtyRaw is num
          ? qtyRaw.toDouble()
          : double.tryParse(qtyRaw?.toString() ?? '') ?? 0.0;
      final unitCostRaw = ingredient['unitCost'];
      final unitCost = unitCostRaw is num
          ? unitCostRaw.toDouble()
          : double.tryParse(unitCostRaw?.toString() ?? '') ?? 0.0;
      sum += qty * unitCost;
    }
    return sum;
  }

  Map<String, dynamic>? _inventoryForIngredient(
      Map<String, dynamic> ingredient) {
    final id = (ingredient['inventoryItemId'] ?? '').toString().trim();
    if (id.isNotEmpty) {
      for (final item in _inventoryItems) {
        if ((item['id'] ?? '').toString() == id) return item;
      }
    }
    final name = (ingredient['name'] ?? '').toString().trim().toLowerCase();
    if (name.isEmpty) return null;
    for (final item in _inventoryItems) {
      if ((item['name'] ?? '').toString().trim().toLowerCase() == name) {
        return item;
      }
    }
    return null;
  }

  double _recipeUnitCost(Map<String, dynamic> inventoryItem, String unit) {
    try {
      return RecipeConsumption.costPerRecipeUnit(
        inventoryItem: inventoryItem,
        recipeUnit: unit,
      );
    } catch (_) {
      return (inventoryItem['unitCost'] as num?)?.toDouble() ?? 0.0;
    }
  }

  Future<void> _addFromInventory() async {
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          _InventoryPickerDialog(inventoryItems: _inventoryItems),
    );
    if (selected == null) return;
    final id = selected['id']?.toString();
    final existingIndex = _ingredients.indexWhere(
        (i) => id != null && i['inventoryItemId']?.toString() == id);
    if (existingIndex >= 0) {
      setState(() {
        final current =
            (_ingredients[existingIndex]['quantityPerServing'] as num?)
                    ?.toDouble() ??
                1.0;
        _ingredients[existingIndex]['quantityPerServing'] = current + 1;
        _ingredients[existingIndex]['quantity'] = current + 1;
      });
    } else {
      final unit = (selected['unit'] ?? '').toString();
      setState(() {
        _ingredients.add({
          'inventoryItemId': selected['id'],
          'name': selected['name'],
          'quantity': 1.0,
          'quantityPerServing': 1.0,
          'unit': unit,
          'unitCost': _recipeUnitCost(selected, unit),
          'totalCost': 0.0,
          'isAutoCreated': false,
          'inventoryCategory': selected['category'],
          'inventoryUnit': unit,
        });
      });
    }
    _recomputeCost();
  }

  Future<void> _createNewItem() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _CreateInventoryItemDialog(),
    );
    if (result == null) return;
    try {
      final created = await FirebaseService.createInventoryItemFromRecipe(
        name: result['name'],
        category: result['category'],
        unit: result['unit'],
        unitCost: (result['unitCost'] as num).toDouble(),
        initialStock: (result['initialStock'] as num?)?.toDouble() ?? 0.0,
        notes: result['notes'],
      );
      if (!mounted) return;
      final unit = (created['unit'] ?? result['unit'] ?? '').toString();
      setState(() {
        _ingredients.add({
          'inventoryItemId': created['id'],
          'name': created['name'],
          'quantity': 1.0,
          'quantityPerServing': 1.0,
          'unit': unit,
          'unitCost': _recipeUnitCost(created, unit),
          'totalCost': 0.0,
          'isAutoCreated': created['isAutoCreated'] == true ||
              created['createdBy'] == 'recipe_auto_create',
          'inventoryCategory': result['category'],
          'inventoryUnit': unit,
        });
      });
      await _loadData();
      _recomputeCost();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Inventory item created as recipe-pending and added.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _changeIngredientUnit(Map<String, dynamic> ingredient, String unit) {
    final inventoryItem = _inventoryForIngredient(ingredient);
    setState(() {
      ingredient['unit'] = unit;
      if (inventoryItem != null) {
        ingredient['unitCost'] = _recipeUnitCost(inventoryItem, unit);
      }
    });
    _recomputeCost();
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one ingredient')));
      return;
    }
    final invalidIngredient = _ingredients.any((ingredient) {
      final qtyRaw = ingredient['quantityPerServing'] ?? ingredient['quantity'];
      final qty = qtyRaw is num
          ? qtyRaw.toDouble()
          : double.tryParse(qtyRaw?.toString() ?? '') ?? 0.0;
      return qty <= 0;
    });
    if (invalidIngredient) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Each ingredient needs a quantity per serving')));
      return;
    }

    setState(() => _isSaving = true);
    _recomputeCost();
    final cost = _costPerServing;
    final recipeData = {
      'name': _nameController.text.trim(),
      'description': _descController.text.trim(),
      'baseServings': 1.0,
      'batchYield': 1.0,
      'ingredients': _ingredients,
      'batchCost': cost,
      'costPerServing': cost,
      'costingMethod': 'recipe',
      'costSource': 'recipe_calculated',
      'linkedMenuItemIds': _selectedMenuItemIds,
    };
    try {
      String recipeId;
      if (widget.recipe != null && widget.recipe!['id'] != null) {
        recipeId = widget.recipe!['id'].toString();
        await FirebaseService.updateRecipe(recipeId, recipeData);
      } else {
        final created = await FirebaseService.createRecipe(recipeData);
        recipeId = created['id'].toString();
      }
      await FirebaseService.linkRecipeToMenuItems(
        recipeId: recipeId,
        menuItemIds: _selectedMenuItemIds,
        recipeCostData: {
          'batchCost': cost,
          'costPerServing': cost,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Recipe saved')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEdit = widget.recipe != null;
    return Theme(
      data: AppTheme.dashboardTheme,
      child: Scaffold(
        backgroundColor: AppTheme.sageNavy,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'Edit Recipe' : 'New Recipe'),
              Text(
                'Per-serving costing',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveRecipe,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(_isSaving ? 'Saving' : 'Save'),
              ),
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.sageNavy, AppTheme.sagePanel],
            ),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 980;
                      final content = [
                        _sectionCard(
                          title: 'Recipe details',
                          icon: Icons.edit_note_rounded,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Recipe name *',
                                  prefixIcon: Icon(Icons.restaurant_outlined),
                                ),
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _descController,
                                decoration: const InputDecoration(
                                  labelText: 'Description',
                                  prefixIcon: Icon(Icons.notes_outlined),
                                ),
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.sageBlue.withValues(alpha: .1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.sageBlue
                                        .withValues(alpha: .22),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.percent_rounded,
                                        size: 18, color: AppTheme.sageCyan),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Quantities and costs are for one serving. SmartEat multiplies by ordered quantity when the order is completed.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _sectionCard(
                          title: 'Ingredients',
                          icon: Icons.inventory_2_outlined,
                          trailing: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _addFromInventory,
                                icon: const Icon(Icons.search, size: 16),
                                label: const Text('From inventory'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _createNewItem,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('New item'),
                              ),
                            ],
                          ),
                          child: _ingredients.isEmpty
                              ? _emptyIngredients(scheme)
                              : Column(
                                  children: [
                                    for (int i = 0;
                                        i < _ingredients.length;
                                        i++)
                                      _IngredientRow(
                                        key: ValueKey(
                                            '${_ingredients[i]['inventoryItemId'] ?? _ingredients[i]['name']}_$i'),
                                        ingredient: _ingredients[i],
                                        onChanged: _recomputeCost,
                                        onUnitChanged: (unit) =>
                                            _changeIngredientUnit(
                                                _ingredients[i], unit),
                                        onRemove: () {
                                          setState(
                                              () => _ingredients.removeAt(i));
                                          _recomputeCost();
                                        },
                                      ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 14),
                        _buildLinkCard(scheme),
                      ];
                      final side = [
                        _buildCostCard(scheme),
                        const SizedBox(height: 14),
                        _sectionCard(
                          title: 'Inventory & menu',
                          icon: Icons.link_outlined,
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _HintRow(
                                icon: Icons.inventory_2_outlined,
                                text:
                                    'Unit cost comes from inventory and converts between compatible mass or volume units.',
                              ),
                              SizedBox(height: 8),
                              _HintRow(
                                icon: Icons.pending_actions_outlined,
                                text:
                                    'Stock is deducted only when an order is completed, never when it is created.',
                              ),
                              SizedBox(height: 8),
                              _HintRow(
                                icon: Icons.restaurant_menu_outlined,
                                text:
                                    'A menu item uses either this recipe or a direct inventory link, never both.',
                              ),
                            ],
                          ),
                        ),
                      ];
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      flex: 7,
                                      child: Column(children: content)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                      flex: 4, child: Column(children: side)),
                                ],
                              )
                            : Column(
                                children: [
                                  ...content,
                                  const SizedBox(height: 14),
                                  ...side,
                                ],
                              ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }

  Widget _emptyIngredients(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.sagePanel.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        children: [
          Icon(Icons.kitchen_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          const Text('No ingredients yet',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Add from inventory or create a new recipe-pending item.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildCostCard(ColorScheme scheme) {
    return _sectionCard(
      title: 'Costing',
      icon: Icons.calculate_outlined,
      trailing: TextButton.icon(
        onPressed: _recomputeCost,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Recompute'),
      ),
      child: Column(
        children: [
          _CostTile(
            label: 'Cost / serving',
            value: '₱${_costPerServing.toStringAsFixed(2)}',
            color: AppTheme.sageSuccess,
            icon: Icons.price_check_outlined,
            emphasized: true,
          ),
          const SizedBox(height: 8),
          _CostTile(
            label: 'Ingredient lines',
            value: '${_ingredients.length}',
            color: AppTheme.sageCyan,
            icon: Icons.format_list_numbered,
          ),
          const SizedBox(height: 8),
          _CostTile(
            label: 'Linked menu',
            value: '${_selectedMenuItemIds.length}',
            color: AppTheme.sageBlue,
            icon: Icons.restaurant_menu_outlined,
          ),
          if (_selectedMenuItemIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Saving syncs per-serving costing to ${_selectedMenuItemIds.length} linked menu item${_selectedMenuItemIds.length == 1 ? '' : 's'}.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLinkCard(ColorScheme scheme) {
    final q = _menuSearch.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _menuItems
        : _menuItems.where((m) {
            final name = (m['name'] ?? '').toString().toLowerCase();
            return name.contains(q);
          }).toList();
    return _sectionCard(
      title: 'Link to menu items',
      icon: Icons.restaurant_menu_outlined,
      trailing: _selectedMenuItemIds.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.sageBlue.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_selectedMenuItemIds.length} selected',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.sageCyan,
                ),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: (v) => setState(() => _menuSearch = v),
            decoration: const InputDecoration(
              hintText: 'Search menu items...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          if (_menuItems.isEmpty)
            Text('No menu items found.',
                style: TextStyle(color: scheme.onSurfaceVariant))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filtered.map((menuItem) {
                final id = (menuItem['id'] ?? '').toString();
                if (id.isEmpty) return const SizedBox.shrink();
                final selected = _selectedMenuItemIds.contains(id);
                final price = (menuItem['price'] as num?)?.toDouble();
                final name = (menuItem['name'] ?? '').toString();
                final hasDirectLink =
                    (menuItem['inventoryItemId'] ?? '').toString().isNotEmpty;
                return FilterChip(
                  label: Text(price != null
                      ? '$name  ·  ₱${price.toStringAsFixed(0)}'
                      : name),
                  selected: selected,
                  showCheckmark: true,
                  avatar: hasDirectLink && !selected
                      ? const Icon(Icons.inventory_2_outlined, size: 15)
                      : null,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        if (!_selectedMenuItemIds.contains(id)) {
                          _selectedMenuItemIds.add(id);
                        }
                      } else {
                        _selectedMenuItemIds.remove(id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          if (filtered.any(
              (m) => (m['inventoryItemId'] ?? '').toString().isNotEmpty)) ...[
            const SizedBox(height: 10),
            Text(
              'Selecting a directly linked menu item replaces its inventory link with this recipe.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return SectionCard(
      title: title,
      icon: icon,
      iconColor: AppTheme.sageCyan,
      action: trailing,
      child: child,
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    super.key,
    required this.ingredient,
    required this.onChanged,
    required this.onUnitChanged,
    required this.onRemove,
  });

  final Map<String, dynamic> ingredient;
  final VoidCallback onChanged;
  final ValueChanged<String> onUnitChanged;
  final VoidCallback onRemove;

  static const _units = [
    'g',
    'kg',
    'ml',
    'L',
    'pcs',
    'pack',
    'box',
    'bottle',
    'can',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final qtyRaw = ingredient['quantityPerServing'] ?? ingredient['quantity'];
    final qty = qtyRaw is num
        ? qtyRaw.toDouble()
        : double.tryParse(qtyRaw?.toString() ?? '') ?? 0.0;
    final unitCostRaw = ingredient['unitCost'];
    final unitCost = unitCostRaw is num
        ? unitCostRaw.toDouble()
        : double.tryParse(unitCostRaw?.toString() ?? '') ?? 0.0;
    final line = qty * unitCost;
    final pending = ingredient['isAutoCreated'] == true ||
        ingredient['createdBy'] == 'recipe_auto_create';
    final unit = (ingredient['unit'] ?? '').toString();
    final inventoryUnit = (ingredient['inventoryUnit'] ?? '').toString();
    final mismatch = unit.isNotEmpty &&
        inventoryUnit.isNotEmpty &&
        !UnitConversion.isCompatible(unit, inventoryUnit);
    final units = <String>{..._units, if (unit.isNotEmpty) unit}.toList();

    final qtyField = TextFormField(
      key: ValueKey(
          'qty_${ingredient['inventoryItemId']}_${ingredient['name']}'),
      initialValue: qty.toString(),
      decoration: const InputDecoration(
        labelText: 'Qty / serving',
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      onChanged: (v) {
        final value = double.tryParse(v) ?? 0;
        ingredient['quantity'] = value;
        ingredient['quantityPerServing'] = value;
        onChanged();
      },
    );

    final unitField = DropdownButtonFormField<String>(
      key: ValueKey(
          'unit_${ingredient['inventoryItemId']}_${ingredient['name']}'),
      initialValue: units.contains(unit) ? unit : null,
      decoration: const InputDecoration(
        labelText: 'Recipe unit',
        isDense: true,
      ),
      items: units
          .map((value) => DropdownMenuItem(value: value, child: Text(value)))
          .toList(),
      onChanged: (value) {
        if (value != null) onUnitChanged(value);
      },
    );

    final costField = TextFormField(
      key: ValueKey(
          'cost_${ingredient['inventoryItemId']}_${ingredient['name']}'),
      initialValue: unitCost.toString(),
      decoration: const InputDecoration(
        labelText: 'Cost / unit (₱)',
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
      ],
      onChanged: (v) {
        ingredient['unitCost'] = double.tryParse(v) ?? 0;
        onChanged();
      },
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.sagePanel.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (ingredient['name'] ?? 'Ingredient').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MiniTag(
                          label: unit,
                          color: AppTheme.sageCyan,
                        ),
                        if (pending)
                          const _MiniTag(
                            label: 'Recipe-pending',
                            color: AppTheme.warning,
                          ),
                        if (mismatch)
                          const _MiniTag(
                            label: 'Unit mismatch',
                            color: AppTheme.error,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₱${line.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.sageSuccess,
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 520) {
                return Column(
                  children: [
                    qtyField,
                    const SizedBox(height: 8),
                    unitField,
                    const SizedBox(height: 8),
                    costField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: qtyField),
                  const SizedBox(width: 10),
                  Expanded(child: unitField),
                  const SizedBox(width: 10),
                  Expanded(child: costField),
                ],
              );
            },
          ),
          if (mismatch) ...[
            const SizedBox(height: 8),
            Text(
              'Recipe unit is incompatible with inventory unit $inventoryUnit. Use a mass or volume unit that matches.',
              style: TextStyle(fontSize: 11, color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _CostTile extends StatelessWidget {
  const _CostTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: emphasized ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasized ? 18 : 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _InventoryPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> inventoryItems;
  const _InventoryPickerDialog({required this.inventoryItems});

  @override
  State<_InventoryPickerDialog> createState() => _InventoryPickerDialogState();
}

class _InventoryPickerDialogState extends State<_InventoryPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = widget.inventoryItems.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final cat = (item['category'] ?? '').toString().toLowerCase();
      return name.contains(q) || cat.contains(q);
    }).toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Add from inventory',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ],
              ),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search by name or category',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching inventory items.'))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final unitCost =
                              (item['unitCost'] as num?)?.toDouble() ?? 0;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppTheme.sageBlue.withValues(alpha: 0.14),
                              child: const Icon(Icons.inventory_2_outlined,
                                  color: AppTheme.sageCyan, size: 18),
                            ),
                            title: Text((item['name'] ?? '').toString()),
                            subtitle: Text(
                                '${item['category'] ?? ''} • ${item['unit'] ?? ''} • ₱${unitCost.toStringAsFixed(2)}'),
                            trailing: const Icon(Icons.add_circle_outline),
                            onTap: () => Navigator.pop(context, item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateInventoryItemDialog extends StatefulWidget {
  const _CreateInventoryItemDialog();

  @override
  State<_CreateInventoryItemDialog> createState() =>
      _CreateInventoryItemDialogState();
}

class _CreateInventoryItemDialogState
    extends State<_CreateInventoryItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _unitController = TextEditingController(text: 'pcs');
  final _unitCostController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  final List<String> _units = const [
    'kg',
    'g',
    'L',
    'ml',
    'pcs',
    'pack',
    'box',
    'bottle',
    'can',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _unitController.dispose();
    _unitCostController.dispose();
    _stockController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create inventory item'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Created items are marked recipe-pending so they do not affect direct stock deduction until configured.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Item name *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Category *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _unitController.text,
                  decoration: const InputDecoration(labelText: 'Unit *'),
                  items: _units
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => _unitController.text = v ?? 'pcs',
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _unitCostController,
                  decoration:
                      const InputDecoration(labelText: 'Unit cost (₱) *'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  validator: (v) =>
                      double.tryParse(v ?? '') == null ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _stockController,
                  decoration: const InputDecoration(labelText: 'Initial stock'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                ),
                const SizedBox(height: 10),
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
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'name': _nameController.text.trim(),
              'category': _categoryController.text.trim(),
              'unit':
                  _unitController.text.isEmpty ? 'pcs' : _unitController.text,
              'unitCost': double.parse(_unitCostController.text),
              'initialStock': double.tryParse(_stockController.text) ?? 0.0,
              'notes': _notesController.text.trim(),
            });
          },
          child: const Text('Create & add'),
        ),
      ],
    );
  }
}
