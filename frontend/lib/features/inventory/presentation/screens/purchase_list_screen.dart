import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../../models/inventory_item.dart';
import '../../data/models/purchase_list_item.dart';
import '../../data/models/purchase_receipt.dart';
import '../../data/services/purchase_list_pdf_service.dart';
import '../../presentation/providers/purchase_list_notifier.dart';
import 'record_purchase_screen.dart';

class PurchaseListScreen extends StatefulWidget {
  final List<InventoryItem> items;
  final Future<void> Function(PurchaseReceipt receipt)? onRecordPurchase;

  const PurchaseListScreen({
    Key? key,
    required this.items,
    this.onRecordPurchase,
  }) : super(key: key);

  @override
  State<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends State<PurchaseListScreen> {
  String _allItemsQuery = '';
  String _allItemsCategory = 'All';

  String _formatCurrency(double amount) {
    return NumberFormat.currency(symbol: '₱', decimalDigits: 2).format(amount);
  }

  Future<void> _editQtyDialog(PurchaseListItem entry) async {
    final controller = TextEditingController(text: entry.qty.toString());
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quantity — ${entry.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          decoration: InputDecoration(
            labelText: 'Quantity (${entry.unit})',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text);
              if (v != null && v >= 0) Navigator.of(ctx).pop(v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      context.read<PurchaseListNotifier>().updateQty(entry.itemId, result);
    }
  }

  Future<void> _exportPdf() async {
    final notifier = context.read<PurchaseListNotifier>();
    final list = notifier.list;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add items to the list before exporting.')),
      );
      return;
    }
    final total = list.fold<double>(0.0, (sum, e) => sum + e.lineCost);
    await PurchaseListPdfService.export(list: list, totalCost: total);
  }

  Future<void> _record() async {
    final notifier = context.read<PurchaseListNotifier>();
    if (notifier.list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add items to the list before recording.')),
      );
      return;
    }
    final receipt = await Navigator.of(context).push<PurchaseReceipt>(
      MaterialPageRoute(
        builder: (_) => RecordPurchaseScreen(list: notifier.list),
      ),
    );
    if (receipt == null || !mounted) return;

    try {
      await widget.onRecordPurchase?.call(receipt);
      notifier.removeItems(receipt.items.map((e) => e.itemId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recorded ${receipt.items.length} item(s) to inventory.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to record purchase: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PurchaseListNotifier>();
    final list = notifier.list;
    final critical = notifier.criticalItems(widget.items);
    final safe = notifier.safeItems(widget.items);
    final all = notifier.allItems(widget.items);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase List'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Download PDF',
            onPressed: _exportPdf,
          ),
          if (list.isNotEmpty && widget.onRecordPurchase != null)
            IconButton(
              icon: const Icon(Icons.playlist_add_check),
              tooltip: 'Record to Inventory',
              onPressed: _record,
            ),
          if (list.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Clear checked'),
              onPressed: () => notifier.clearChecked(),
            ),
          if (list.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Regenerate from critical',
              onPressed: () => _confirmRegenerate(critical),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;
          final listWidget = _buildMyList(context, notifier, list);
          final rightColumn = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSuggestions(context, notifier, critical, safe),
              const SizedBox(height: 12),
              _buildAllItems(context, notifier, all),
            ],
          );
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(child: listWidget),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(child: rightColumn),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [listWidget, const SizedBox(height: 12), rightColumn],
          );
        },
      ),
    );
  }

  Widget _buildMyList(
      BuildContext context, PurchaseListNotifier notifier, List<PurchaseListItem> list) {
    final theme = Theme.of(context);
    return Card(
      margin: isWideLayout(context) ? const EdgeInsets.all(12) : EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.shopping_basket_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Your Purchase List',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${notifier.pendingCount} pending',
                    style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
              ],
            ),
            const Divider(height: 16),
            if (list.isEmpty)
              _emptyList(context)
            else
              ...list.map((entry) => _listRow(context, notifier, entry)),
            const Divider(height: 16),
            _totalRow(context, notifier),
          ],
        ),
      ),
    );
  }

  Widget _emptyList(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.shopping_cart_outlined,
                size: 40, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text('No items yet',
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Tap items in Critical / Safe / All below, or use Generate to fill from critical items.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listRow(
      BuildContext context, PurchaseListNotifier notifier, PurchaseListItem entry) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: entry.checked,
            onChanged: (_) => notifier.toggleChecked(entry.itemId),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: entry.checked ? TextDecoration.lineThrough : null,
                        color: entry.checked ? theme.colorScheme.onSurfaceVariant : null,
                      ),
                ),
                Text(
                  '${_formatCurrency(entry.unitCost)} / ${entry.unit}',
                  style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          _qtyStepper(context, notifier, entry),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              _formatCurrency(entry.lineCost),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: entry.checked ? theme.colorScheme.onSurfaceVariant : null,
                  ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: theme.colorScheme.error),
            onPressed: () => notifier.removeItem(entry.itemId),
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _qtyStepper(
      BuildContext context, PurchaseListNotifier notifier, PurchaseListItem entry) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => notifier.decrementQty(entry.itemId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(Icons.remove, size: 16, color: theme.colorScheme.primary),
            ),
          ),
          InkWell(
            onTap: () => _editQtyDialog(entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                entry.qty % 1 == 0
                    ? entry.qty.toInt().toString()
                    : entry.qty.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          InkWell(
            onTap: () => notifier.incrementQty(entry.itemId),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(BuildContext context, PurchaseListNotifier notifier) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Total (pending)',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Text(
          _formatCurrency(notifier.pendingCost),
          style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
        ),
      ],
    );
  }

  Widget _buildSuggestions(BuildContext context, PurchaseListNotifier notifier,
      List<InventoryItem> critical, List<InventoryItem> safe) {
    final theme = Theme.of(context);
    return Card(
      margin: isWideLayout(context) ? const EdgeInsets.all(12) : EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Suggested Items',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: const Text('Generate'),
                  onPressed: critical.isEmpty ? null : () => _confirmGenerate(critical),
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
            const Divider(height: 16),
            _suggestionHeader(context, 'Critical — restock now', Colors.red),
            if (critical.isEmpty)
              _noSuggestion(context, 'No critical items. All stock is healthy.')
            else
              ...critical.map((item) => _suggestionRow(context, notifier, item, accent: Colors.red)),
            const SizedBox(height: 12),
            _suggestionHeader(context, 'Safe — optional top-up', Colors.green),
            if (safe.isEmpty)
              _noSuggestion(context, 'No safe items to top up right now.')
            else
              ...safe.map((item) => _suggestionRow(context, notifier, item, accent: Colors.green)),
          ],
        ),
      ),
    );
  }

  Widget _buildAllItems(BuildContext context, PurchaseListNotifier notifier,
      List<InventoryItem> all) {
    final theme = Theme.of(context);
    final query = _allItemsQuery.trim().toLowerCase();

    // Categories available for filtering: "All" plus every category actually
    // present in the inventory (defaults first, then any custom ones).
    const defaultCats = ['Vegetables', 'Meat', 'Dairy', 'Grains', 'Spices', 'Beverages'];
    final present = all
        .map((e) => e.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final categories = <String>[
      'All',
      ...defaultCats.where(present.contains),
      ...present.where((c) => !defaultCats.contains(c)),
    ];
    // Keep the selection valid if the current category disappears.
    final selectedCat = categories.contains(_allItemsCategory) ? _allItemsCategory : 'All';

    final filtered = all.where((e) {
      final matchesCategory = selectedCat == 'All' || e.category == selectedCat;
      final matchesQuery = query.isEmpty ||
          e.name.toLowerCase().contains(query) ||
          e.category.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList();

    return Card(
      margin: isWideLayout(context) ? const EdgeInsets.all(12) : EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('All Items',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(
                    selectedCat == 'All' && query.isEmpty
                        ? '${all.length} total'
                        : '${filtered.length} of ${all.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (v) => setState(() => _allItemsQuery = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search items…',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final category = categories[i];
                  final selected = category == selectedCat;
                  return ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (_) =>
                        setState(() => _allItemsCategory = category),
                  );
                },
              ),
            ),
            const Divider(height: 16),
            if (filtered.isEmpty)
              _noSuggestion(context, 'No items match your search.')
            else
              ...filtered.map((item) => _suggestionRow(
                    context,
                    notifier,
                    item,
                    accent: theme.colorScheme.primary,
                  )),
          ],
        ),
      ),
    );
  }

  Widget _suggestionHeader(BuildContext context, String text, Color color) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }

  Widget _noSuggestion(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _suggestionRow(BuildContext context, PurchaseListNotifier notifier,
      InventoryItem item, {required Color accent}) {
    final theme = Theme.of(context);
    final inList = notifier.isInList(item.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        onTap: inList ? null : () => notifier.addItem(item),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: inList ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: inList ? theme.colorScheme.onSurfaceVariant : null,
                          ),
                    ),
                    Text(
                      '${item.currentStock.toStringAsFixed(1)} / ${item.maxStock.toStringAsFixed(1)} ${item.unit}',
                      style: theme.textTheme.labelSmall?.copyWith(
                            color: accent.withValues(alpha: 0.9),
                          ),
                    ),
                  ],
                ),
              ),
              if (inList)
                Icon(Icons.check_circle, size: 20, color: theme.colorScheme.primary)
              else
                Icon(Icons.add_circle_outline, size: 20, color: accent),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmGenerate(List<InventoryItem> critical) {
    final notifier = context.read<PurchaseListNotifier>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate purchase list?'),
        content: Text(
            'This replaces your current list with ${critical.length} critical item(s). Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              notifier.generateFromCritical(widget.items);
              Navigator.of(ctx).pop();
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  void _confirmRegenerate(List<InventoryItem> critical) {
    final notifier = context.read<PurchaseListNotifier>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate list?'),
        content: const Text('Your current list will be replaced with critical items.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              notifier.generateFromCritical(widget.items);
              Navigator.of(ctx).pop();
            },
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
  }
}

bool isWideLayout(BuildContext context) {
  return MediaQuery.of(context).size.width >= 800;
}
