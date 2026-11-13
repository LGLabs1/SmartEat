import 'package:flutter/material.dart';

import '../services/firebase_service.dart';
import '../theme.dart';
import 'recipe_editor_page.dart';

class RecipeListPage extends StatefulWidget {
  const RecipeListPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<RecipeListPage> createState() => _RecipeListPageState();
}

class _RecipeListPageState extends State<RecipeListPage> {
  List<Map<String, dynamic>> _recipes = const [];
  List<Map<String, dynamic>> _menuItems = const [];
  bool _isLoading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        FirebaseService.getRecipes(),
        FirebaseService.getMenuItems(),
      ]);
      if (!mounted) return;
      setState(() {
        _recipes = List<Map<String, dynamic>>.from(results[0]);
        _menuItems = List<Map<String, dynamic>>.from(results[1]);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading recipes: $e')),
      );
    }
  }

  String _menuName(String id) {
    for (final m in _menuItems) {
      if (m['id']?.toString() == id) {
        return (m['name'] ?? 'Menu item').toString();
      }
    }
    return 'Menu item';
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _recipes;
    return _recipes.where((r) {
      final name = (r['name'] ?? '').toString().toLowerCase();
      final desc = (r['description'] ?? '').toString().toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();
  }

  Future<void> _openEditor([Map<String, dynamic>? recipe]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecipeEditorPage(recipe: recipe)),
    );
    if (mounted) _load();
  }

  Future<void> _deleteRecipe(Map<String, dynamic> recipe) async {
    final id = recipe['id']?.toString();
    if (id == null || id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete recipe?'),
        content: Text(
            'Delete "${recipe['name'] ?? 'this recipe'}"? Linked menu items will keep their current costing values until updated.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseService.deleteRecipe(id);
      if (mounted) _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete recipe: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                widget.embedded ? 12 : 16,
                16,
                widget.embedded ? 96 : 24,
              ),
              children: [
                _buildHero(context),
                const SizedBox(height: 14),
                _buildSearch(context),
                const SizedBox(height: 14),
                if (_filtered.isEmpty)
                  _EmptyRecipes(onAdd: () => _openEditor())
                else
                  ..._filtered.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _RecipeCard(
                          recipe: r,
                          menuName: _menuName,
                          onTap: () => _openEditor(r),
                          onDelete: () => _deleteRecipe(r),
                        ),
                      )),
              ],
            ),
          );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Recipes'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Recipe'),
      ),
      body: body,
    );
  }

  Widget _buildHero(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _recipes.length;
    final withCost = _recipes.where((r) {
      final cps = (r['costPerServing'] as num?)?.toDouble();
      return cps != null && cps > 0;
    }).length;
    final linked = _recipes
        .where((r) => (r['linkedMenuItemIds'] as List?)?.isNotEmpty == true)
        .length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.12),
            scheme.primaryContainer.withValues(alpha: 0.35),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.restaurant_menu_rounded,
                    color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recipe Costing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      'Batch ingredients, cost per serving, and menu linkage.',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatPill(label: 'Recipes', value: '$total'),
              _StatPill(label: 'Costed', value: '$withCost'),
              _StatPill(label: 'Linked to menu', value: '$linked'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearch(BuildContext context) {
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Search recipes...',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$value $label',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.recipe,
    required this.menuName,
    required this.onTap,
    required this.onDelete,
  });

  final Map<String, dynamic> recipe;
  final String Function(String) menuName;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = (recipe['name'] ?? 'Unnamed Recipe').toString();
    final yieldVal = (recipe['batchYield'] ?? recipe['baseServings'] ?? 1);
    final cps = (recipe['costPerServing'] as num?)?.toDouble();
    final batch = (recipe['batchCost'] as num?)?.toDouble();
    final linked = (recipe['linkedMenuItemIds'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final ingredients = (recipe['ingredients'] as List?)?.length ?? 0;
    final hasCost = cps != null && cps > 0;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (hasCost ? AppTheme.success : AppTheme.warning)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      hasCost ? Icons.receipt_long_outlined : Icons.edit_note,
                      color: hasCost ? AppTheme.success : AppTheme.warning,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$ingredients ingredients • Yield $yieldVal • ${linked.length} menu item${linked.length == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    visualDensity: VisualDensity.compact,
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    label: 'Cost / serving',
                    value: cps != null ? '₱${cps.toStringAsFixed(2)}' : 'Not set',
                    color: hasCost ? AppTheme.success : scheme.outline,
                  ),
                  _MetricChip(
                    label: 'Batch cost',
                    value: batch != null ? '₱${batch.toStringAsFixed(2)}' : '—',
                    color: AppTheme.primary,
                  ),
                ],
              ),
              if (linked.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...linked.take(4).map((id) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                scheme.primaryContainer.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            menuName(id),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer),
                          ),
                        )),
                    if (linked.length > 4)
                      Text('+${linked.length - 4} more',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _EmptyRecipes extends StatelessWidget {
  const _EmptyRecipes({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.restaurant_menu_rounded,
              size: 52, color: scheme.outline),
          const SizedBox(height: 12),
          const Text('No recipes yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Create recipes to calculate ingredient costs and link them to menu items.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Recipe'),
          ),
        ],
      ),
    );
  }
}
