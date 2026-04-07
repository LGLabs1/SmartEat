import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';

class RecipeScreen extends StatefulWidget {
  const RecipeScreen({
    Key? key,
    this.globalSearchQuery,
    this.showAppBar = true,
  }) : super(key: key);

  final ValueNotifier<String>? globalSearchQuery;
  final bool showAppBar;

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _recipes = const [];
  List<Map<String, dynamic>> _inventory = const [];
  final Map<String, int> _targetServingsById = {};
  String _searchQuery = '';
  bool _isAdmin = false;
  String? _lastRoleUid;
  VoidCallback? _globalSearchListener;

  @override
  void initState() {
    super.initState();
    _loadRecipes();
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

  Future<void> _openAddRecipeDialog() async {
    if (!_isAdmin) return;
    if (_inventory.isEmpty) {
      await _loadRecipes();
      if (!mounted) return;
    }

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _AddRecipeDialog(inventory: _inventory);
      },
    );

    if (created == true) {
      await _loadRecipes();
    }
  }

  String _norm(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim();
  }

  Map<String, dynamic>? _findInventoryItemByName(String ingredientName) {
    final key = _norm(ingredientName);
    if (key.isEmpty) return null;

    for (final item in _inventory) {
      final name = (item['name'] ?? '').toString();
      if (_norm(name) == key) return item;
    }
    return null;
  }

  double _asDoubleSafe(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().trim()) ?? 0.0;
  }

  List<Map<String, dynamic>> _ingredientAlerts({
    required List<Map<String, dynamic>> ingredients,
    required double factor,
  }) {
    final alerts = <Map<String, dynamic>>[];

    for (final ing in ingredients) {
      final ingName = (ing['name'] ?? '').toString().trim();
      if (ingName.isEmpty) continue;

      final inv = _findInventoryItemByName(ingName);
      if (inv == null) {
        alerts.add({
          'severity': 'missing',
          'name': ingName,
          'message': 'Missing in inventory',
        });
        continue;
      }

      final currentStock = _asDoubleSafe(inv['currentStock']);
      final minStock = _asDoubleSafe(inv['minStock']);
      final invUnit = (inv['unit'] ?? '').toString().trim();
      final ingUnit = (ing['unit'] ?? '').toString().trim();
      final baseQty = _asDoubleSafe(ing['quantity']);
      final scaledQty = baseQty * factor;

      final unitsComparable = ingUnit.isEmpty || invUnit.isEmpty
          ? true
          : _norm(ingUnit) == _norm(invUnit);

      if (currentStock <= 0) {
        alerts.add({
          'severity': 'out',
          'name': ingName,
          'message': 'Out of stock',
          'currentStock': currentStock,
          'minStock': minStock,
          'unit': invUnit,
        });
        continue;
      }

      if (baseQty > 0 && unitsComparable && scaledQty > currentStock) {
        alerts.add({
          'severity': 'insufficient',
          'name': ingName,
          'message': 'Not enough stock for selected servings',
          'required': scaledQty,
          'currentStock': currentStock,
          'unit': invUnit.isEmpty ? ingUnit : invUnit,
        });
        continue;
      }

      if (currentStock <= minStock) {
        alerts.add({
          'severity': 'low',
          'name': ingName,
          'message': 'Low stock',
          'currentStock': currentStock,
          'minStock': minStock,
          'unit': invUnit,
        });
      }
    }

    return alerts;
  }

  void _showIngredientAlertsDialog(
    BuildContext context, {
    required String recipeName,
    required List<Map<String, dynamic>> alerts,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Stock alerts: $recipeName'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final a = alerts[index];
                final severity = (a['severity'] ?? '').toString();
                final name = (a['name'] ?? '').toString();
                final message = (a['message'] ?? '').toString();

                Color color;
                IconData icon;
                switch (severity) {
                  case 'out':
                  case 'missing':
                    color = Colors.red;
                    icon = Icons.error_outline;
                    break;
                  case 'insufficient':
                    color = Colors.deepOrange;
                    icon = Icons.warning_amber_rounded;
                    break;
                  case 'low':
                  default:
                    color = Colors.orange;
                    icon = Icons.warning_amber_rounded;
                    break;
                }

                String? trailing;
                if (severity == 'insufficient') {
                  final required = (a['required'] as num?)?.toDouble() ?? 0;
                  final current = (a['currentStock'] as num?)?.toDouble() ?? 0;
                  final unit = (a['unit'] ?? '').toString();
                  trailing =
                      '${_fmtQty(current)}/${_fmtQty(required)}${unit.isEmpty ? '' : ' $unit'}';
                } else if (severity == 'low' || severity == 'out') {
                  final current = (a['currentStock'] as num?)?.toDouble() ?? 0;
                  final min = (a['minStock'] as num?)?.toDouble() ?? 0;
                  final unit = (a['unit'] ?? '').toString();
                  trailing =
                      '${_fmtQty(current)} (min ${_fmtQty(min)})${unit.isEmpty ? '' : ' $unit'}';
                }

                return ListTile(
                  dense: true,
                  leading: Icon(icon, color: color),
                  title: Text(name),
                  subtitle: Text(
                    message,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  trailing: trailing == null
                      ? null
                      : Text(
                          trailing,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadRecipes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        ApiService.getRecipes(),
        ApiService.getInventoryItems(),
      ]);
      final data =
          List<Map<String, dynamic>>.from(results[0]['data'] ?? const []);
      final inventory =
          List<Map<String, dynamic>>.from(results[1]['data'] ?? const []);
      for (final recipe in data) {
        final id = (recipe['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final base = _asInt(recipe['baseServings'], fallback: 1);
        _targetServingsById.putIfAbsent(id, () => base);
      }
      if (!mounted) return;
      setState(() {
        _recipes = data;
        _inventory = inventory;
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

  int _asInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.round();
    final parsed = int.tryParse((value ?? '').toString().trim());
    return parsed ?? fallback;
  }

  double _asDouble(dynamic value, {required double fallback}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    final parsed = double.tryParse((value ?? '').toString().trim());
    return parsed ?? fallback;
  }

  List<Map<String, dynamic>> _ingredients(dynamic raw) {
    if (raw is List) {
      final mapped = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map) {
          mapped.add(Map<String, dynamic>.from(e));
        } else {
          mapped.add({'name': e.toString()});
        }
      }
      return mapped;
    }
    return const [];
  }

  String _fmtQty(double qty) {
    final rounded = (qty * 1000).round() / 1000;
    final asInt = rounded.roundToDouble();
    if ((rounded - asInt).abs() < 0.0000001) {
      return asInt.toInt().toString();
    }
    return rounded.toString();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _recipes.where((r) {
      if (_searchQuery.trim().isEmpty) return true;
      final name = (r['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.trim().toLowerCase());
    }).toList();

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              leading: Navigator.of(context).canPop()
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
              title: const Text('Recipes'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadRecipes,
                ),
              ],
            )
          : null,
      floatingActionButton: !_isAdmin
          ? null
          : FloatingActionButton.extended(
              onPressed: _openAddRecipeDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Recipe'),
            ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text('Failed to load recipes: $_error'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadRecipes,
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    : filtered.isEmpty
                        ? const Center(child: Text('No recipes found'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final recipe = filtered[index];
                              final id = (recipe['id'] ?? '').toString();
                              final name = (recipe['name'] ?? '').toString();
                              final baseServings = _asInt(
                                recipe['baseServings'],
                                fallback: 1,
                              ).clamp(1, 1000000);
                              final targetServings =
                                  (_targetServingsById[id] ?? baseServings)
                                      .clamp(1, 1000000);
                              final factor = targetServings / baseServings;
                              final ingredients =
                                  _ingredients(recipe['ingredients']);
                              final alerts = _ingredientAlerts(
                                ingredients: ingredients,
                                factor: factor,
                              );

                              return Card(
                                elevation: 0,
                                color: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              name.isEmpty
                                                  ? 'Untitled recipe'
                                                  : name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          if (alerts.isNotEmpty) ...[
                                            Tooltip(
                                              message:
                                                  'Some ingredients are low/out of stock',
                                              child: IconButton(
                                                onPressed: () =>
                                                    _showIngredientAlertsDialog(
                                                  context,
                                                  recipeName: name.isEmpty
                                                      ? 'Recipe'
                                                      : name,
                                                  alerts: alerts,
                                                ),
                                                icon: Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Colors.orange.shade800,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              'Base: $baseServings',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          const Text(
                                            'Servings to make',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            onPressed: targetServings <= 1
                                                ? null
                                                : () {
                                                    setState(() {
                                                      _targetServingsById[id] =
                                                          targetServings - 1;
                                                    });
                                                  },
                                            icon: const Icon(Icons.remove),
                                          ),
                                          SizedBox(
                                            width: 64,
                                            child: Text(
                                              targetServings.toString(),
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () {
                                              setState(() {
                                                _targetServingsById[id] =
                                                    targetServings + 1;
                                              });
                                            },
                                            icon: const Icon(Icons.add),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ExpansionTile(
                                        tilePadding: EdgeInsets.zero,
                                        title: const Text(
                                          'Ingredients',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        children: [
                                          if (ingredients.isEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: Text(
                                                'No ingredients saved',
                                                style: TextStyle(
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            )
                                          else
                                            ...ingredients.map((ing) {
                                              final ingName =
                                                  (ing['name'] ?? '')
                                                      .toString();
                                              final unit = (ing['unit'] ?? '')
                                                  .toString()
                                                  .trim();
                                              final baseQty = _asDouble(
                                                ing['quantity'],
                                                fallback: 0,
                                              );
                                              final scaledQty =
                                                  baseQty * factor;
                                              final qtyText = baseQty == 0
                                                  ? ''
                                                  : '${_fmtQty(scaledQty)}${unit.isEmpty ? '' : ' $unit'}';

                                              return ListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(
                                                  ingName.isEmpty
                                                      ? 'Ingredient'
                                                      : ingName,
                                                ),
                                                trailing: Text(
                                                  qtyText,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              );
                                            }),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _AddRecipeDialog extends StatefulWidget {
  const _AddRecipeDialog({required this.inventory});

  final List<Map<String, dynamic>> inventory;

  @override
  State<_AddRecipeDialog> createState() => _AddRecipeDialogState();
}

class _AddRecipeDialogState extends State<_AddRecipeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _baseServingsController = TextEditingController(text: '1');
  bool _isSaving = false;

  final List<_IngredientDraft> _ingredients = [_IngredientDraft()];

  @override
  void dispose() {
    _nameController.dispose();
    _baseServingsController.dispose();
    for (final ing in _ingredients) {
      ing.dispose();
    }
    super.dispose();
  }

  int _asInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.round();
    final parsed = int.tryParse((value ?? '').toString().trim());
    return parsed ?? fallback;
  }

  double _asDouble(dynamic value, {required double fallback}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    final parsed = double.tryParse((value ?? '').toString().trim());
    return parsed ?? fallback;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final baseServings =
        _asInt(_baseServingsController.text, fallback: 1).clamp(1, 1000000);

    final ingredients = <Map<String, dynamic>>[];
    for (final d in _ingredients) {
      final invId = d.inventoryItemId.trim();
      if (invId.isEmpty) continue;
      final qty = _asDouble(d.qtyController.text, fallback: 0.0);
      if (qty <= 0) continue;

      final inv = widget.inventory.firstWhere(
        (e) => (e['id'] ?? '').toString().trim() == invId,
        orElse: () => const {},
      );
      final name = (inv['name'] ?? '').toString().trim();
      final unit = (inv['unit'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      ingredients.add({
        'inventoryItemId': invId,
        'name': name,
        'quantity': qty,
        'unit': unit,
      });
    }

    if (ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add at least 1 ingredient with quantity')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ApiService.createRecipe(
        name: _nameController.text.trim(),
        baseServings: baseServings,
        ingredients: ingredients,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create recipe: $e')),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Recipe'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Recipe name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _baseServingsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Base servings',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim()) ?? 0;
                    if (n <= 0) return 'Must be greater than 0';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Ingredients',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _ingredients.add(_IngredientDraft());
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._ingredients.asMap().entries.map((entry) {
                  final index = entry.key;
                  final ing = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: DropdownButtonFormField<String>(
                            value: ing.inventoryItemId,
                            decoration: const InputDecoration(
                              labelText: 'Inventory item',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Select item'),
                              ),
                              ...widget.inventory.map((inv) {
                                final id = (inv['id'] ?? '').toString();
                                final name = (inv['name'] ?? '').toString();
                                final unit = (inv['unit'] ?? '').toString();
                                final label = unit.trim().isEmpty
                                    ? name
                                    : '$name ($unit)';
                                return DropdownMenuItem(
                                  value: id,
                                  child: Text(
                                    label.trim().isEmpty
                                        ? 'Unnamed item'
                                        : label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: (v) {
                              setState(() {
                                ing.inventoryItemId = v ?? '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: ing.qtyController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Qty',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (ing.inventoryItemId.trim().isEmpty)
                                return null;
                              final n = double.tryParse((v ?? '').trim()) ?? 0;
                              if (n <= 0) return 'Required';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          onPressed: _ingredients.length <= 1
                              ? null
                              : () {
                                  setState(() {
                                    final removed =
                                        _ingredients.removeAt(index);
                                    removed.dispose();
                                  });
                                },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _IngredientDraft {
  String inventoryItemId = '';
  final TextEditingController qtyController = TextEditingController();

  void dispose() {
    qtyController.dispose();
  }
}
