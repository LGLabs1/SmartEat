import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/firebase_service.dart';
import '../theme.dart';

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
  final _batchYieldController = TextEditingController(text: '1');

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
      _nameController.text = (recipe['name'] ?? '').toString();
      _descController.text = (recipe['description'] ?? '').toString();
      _batchYieldController.text =
          (recipe['batchYield'] ?? recipe['baseServings'] ?? 1).toString();
      final ingredients = recipe['ingredients'];
      if (ingredients is List) {
        _ingredients = ingredients
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      final linked = recipe['linkedMenuItemIds'];
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
    _batchYieldController.dispose();
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
    final recipeData = {
      'ingredients': _ingredients,
      'batchYield': double.tryParse(_batchYieldController.text) ?? 1.0,
    };
    final computed = FirebaseService.computeRecipeCostTotals(recipeData);
    setState(() {
      _ingredients = List<Map<String, dynamic>>.from(
          computed['ingredients'] ?? _ingredients);
    });
  }

  double get _batchCost {
    double sum = 0;
    for (final ing in _ingredients) {
      sum += (ing['totalCost'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  double get _costPerServing {
    final y = double.tryParse(_batchYieldController.text) ?? 1.0;
    if (y <= 0) return 0;
    return _batchCost / y;
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
        _ingredients[existingIndex]['quantity'] =
            ((_ingredients[existingIndex]['quantity'] as num?)?.toDouble() ??
                    0) +
                1;
      });
    } else {
      setState(() {
        _ingredients.add({
          'inventoryItemId': selected['id'],
          'name': selected['name'],
          'quantity': 1.0,
          'unit': selected['unit'] ?? '',
          'unitCost': (selected['unitCost'] as num?)?.toDouble() ?? 0.0,
          'totalCost': 0.0,
          'isAutoCreated': false,
          'inventoryCategory': selected['category'],
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
      setState(() {
        _ingredients.add({
          'inventoryItemId': created['id'],
          'name': created['name'],
          'quantity': 1.0,
          'unit': created['unit'] ?? result['unit'] ?? '',
          'unitCost': (created['unitCost'] as num?)?.toDouble() ??
              (result['unitCost'] as num).toDouble(),
          'totalCost': 0.0,
          'isAutoCreated': created['isAutoCreated'] == true ||
              created['createdBy'] == 'recipe_auto_create',
          'inventoryCategory': result['category'],
        });
      });
      await _loadData();
      _recomputeCost();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Inventory item created as recipe-pending and added.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one ingredient')));
      return;
    }
    setState(() => _isSaving = true);
    _recomputeCost();
    final recipeData = {
      'name': _nameController.text.trim(),
      'description': _descController.text.trim(),
      'batchYield': double.tryParse(_batchYieldController.text) ?? 1.0,
      'ingredients': _ingredients,
      'batchCost': _batchCost,
      'costPerServing': _costPerServing,
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
      if (_selectedMenuItemIds.isNotEmpty) {
        await FirebaseService.linkRecipeToMenuItems(
          recipeId: recipeId,
          menuItemIds: _selectedMenuItemIds,
          recipeCostData: {
            'batchCost': _batchCost,
            'costPerServing': _costPerServing
          },
        );
      }
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Recipe' : 'New Recipe'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveRecipe,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check, size: 18),
              label: Text(_isSaving ? 'Saving' : 'Save'),
            ),
          ),
        ],
      ),
      body: _isLoading
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
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? 'Required' : null,
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
                          TextFormField(
                            controller: _batchYieldController,
                            decoration: const InputDecoration(
                              labelText: 'Batch yield (servings) *',
                              helperText:
                                  'How many servings this batch produces',
                              prefixIcon: Icon(Icons.pie_chart_outline),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d*'))
                            ],
                            validator: (v) {
                              final d = double.tryParse(v ?? '');
                              if (d == null || d <= 0) return 'Must be > 0';
                              return null;
                            },
                            onChanged: (_) => _recomputeCost(),
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
                          ? Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: scheme.outlineVariant),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.kitchen_outlined,
                                      color: scheme.outline),
                                  const SizedBox(height: 8),
                                  const Text('No ingredients yet',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Add from inventory or create a new recipe-pending item.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              children: [
                                for (int i = 0; i < _ingredients.length; i++)
                                  _IngredientRow(
                                    key: ValueKey(
                                        '${_ingredients[i]['inventoryItemId'] ?? _ingredients[i]['name']}_$i'),
                                    ingredient: _ingredients[i],
                                    onChanged: () {
                                      _recomputeCost();
                                      setState(() {});
                                    },
                                    onRemove: () {
                                      setState(() => _ingredients.removeAt(i));
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          _HintRow(
                              icon: Icons.inventory_2_outlined,
                              text:
                                  'Ingredient unit cost comes from inventory; override per recipe as needed.'),
                          SizedBox(height: 8),
                          _HintRow(
                              icon: Icons.pending_actions_outlined,
                              text:
                                  'New items are created as recipe-pending (not a direct deduction flow).'),
                          SizedBox(height: 8),
                          _HintRow(
                              icon: Icons.restaurant_menu_outlined,
                              text:
                                  'Linked menu items use recipe costing (separate from Actual COGS).'),
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
                              Expanded(flex: 7, child: Column(children: content)),
                              const SizedBox(width: 14),
                              Expanded(flex: 4, child: Column(children: side)),
                            ],
                          )
                        : Column(
                            children: [
                              ...content,
                              const SizedBox(height: 14),
                              ...side
                            ],
                          ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildCostCard(ColorScheme scheme) {
    final y = double.tryParse(_batchYieldController.text) ?? 1.0;
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
              label: 'Batch cost',
              value: '₱${_batchCost.toStringAsFixed(2)}',
              color: AppTheme.primary,
              icon: Icons.layers_outlined),
          const SizedBox(height: 8),
          _CostTile(
              label: 'Batch yield',
              value: '${y.toStringAsFixed(y % 1 == 0 ? 0 : 2)} servings',
              color: scheme.secondary,
              icon: Icons.pie_chart_outline),
          const SizedBox(height: 8),
          _CostTile(
              label: 'Cost / serving',
              value: '₱${_costPerServing.toStringAsFixed(2)}',
              color: AppTheme.success,
              icon: Icons.price_check_outlined,
              emphasized: true),
          if (_selectedMenuItemIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Saving syncs costing to ${_selectedMenuItemIds.length} linked menu item${_selectedMenuItemIds.length == 1 ? '' : 's'}.',
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
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${_selectedMenuItemIds.length} selected',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
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
                return FilterChip(
                  label: Text(price != null
                      ? '$name  ·  ₱${price.toStringAsFixed(0)}'
                      : name),
                  selected: selected,
                  showCheckmark: true,
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
        ],
      ),
    );
  }

  Widget _sectionCard(
      {required String title,
      required IconData icon,
      required Widget child,
      Widget? trailing}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    super.key,
    required this.ingredient,
    required this.onChanged,
    required this.onRemove,
  });

  final Map<String, dynamic> ingredient;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final qty = (ingredient['quantity'] as num?)?.toDouble() ?? 0.0;
    final unitCost = (ingredient['unitCost'] as num?)?.toDouble() ?? 0.0;
    final line = qty * unitCost;
    final pending = ingredient['isAutoCreated'] == true ||
        ingredient['createdBy'] == 'recipe_auto_create';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
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
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _MiniTag(
                            label: (ingredient['unit'] ?? '').toString(),
                            color: scheme.secondary),
                        if (pending)
                          const _MiniTag(
                              label: 'Recipe-pending', color: AppTheme.warning),
                      ],
                    ),
                  ],
                ),
              ),
              Text('₱${line.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppTheme.success)),
              IconButton(
                tooltip: 'Remove',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey(
                      'qty_${ingredient['inventoryItemId']}_${ingredient['name']}'),
                  initialValue: qty.toString(),
                  decoration: const InputDecoration(
                      labelText: 'Qty / batch', isDense: true),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                  ],
                  onChanged: (v) {
                    ingredient['quantity'] = double.tryParse(v) ?? 0;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  key: ValueKey(
                      'cost_${ingredient['inventoryItemId']}_${ingredient['name']}'),
                  initialValue: unitCost.toString(),
                  decoration: const InputDecoration(
                      labelText: 'Unit cost (₱)', isDense: true),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                  ],
                  onChanged: (v) {
                    ingredient['unitCost'] = double.tryParse(v) ?? 0;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
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
        color: color.withValues(alpha: emphasized ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: emphasized ? 18 : 15,
                  fontWeight: FontWeight.w800,
                  color: color)),
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
            child: Text(text,
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
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
                                  AppTheme.primary.withValues(alpha: 0.12),
                              child: const Icon(Icons.inventory_2_outlined,
                                  color: AppTheme.primary, size: 18),
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

class _CreateInventoryItemDialogState extends State<_CreateInventoryItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _unitController = TextEditingController(text: 'pcs');
  final _unitCostController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  final List<String> _units = const [
    'kg', 'g', 'L', 'ml', 'pcs', 'pack', 'box', 'bottle', 'can'
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
                  'Created items are marked recipe-pending so they don’t affect direct stock deduction until configured.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
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
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
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
