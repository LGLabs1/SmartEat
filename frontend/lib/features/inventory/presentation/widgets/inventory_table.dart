import 'package:flutter/material.dart';
import '../../../../../models/inventory_item.dart';

class InventoryTable extends StatefulWidget {
  final List<InventoryItem> items;
  final ValueChanged<InventoryItem> onRowTap;

  const InventoryTable({
    Key? key,
    required this.items,
    required this.onRowTap,
  }) : super(key: key);

  @override
  State<InventoryTable> createState() => _InventoryTableState();
}

class _InventoryTableState extends State<InventoryTable> {
  int? _sortColumnIndex;
  bool _sortAscending = true;
  late List<InventoryItem> _sorted;

  @override
  void initState() {
    super.initState();
    _sorted = List<InventoryItem>.from(widget.items);
  }

  @override
  void didUpdateWidget(covariant InventoryTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _sorted = List<InventoryItem>.from(widget.items);
      if (_sortColumnIndex != null) {
        _applySort(_sortColumnIndex!, _sortAscending);
      }
    }
  }

  String _lc(String s) => s.toLowerCase();

  void _applySort(int columnIndex, bool ascending) {
    int cmp(Comparable a, Comparable b) =>
        ascending ? a.compareTo(b) : b.compareTo(a);

    _sorted.sort((a, b) {
      switch (columnIndex) {
        case 0:
          return cmp(_lc(a.name), _lc(b.name));
        case 1:
          return cmp(_lc(a.category), _lc(b.category));
        case 2:
          return cmp(_lc(a.unit), _lc(b.unit));
        case 3:
          return cmp(a.unitCost, b.unitCost);
        case 4:
          return cmp(a.currentStock, b.currentStock);
        default:
          return 0;
      }
    });
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _applySort(columnIndex, ascending);
    });
  }

  Widget _headerLabel(BuildContext context, String text) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
              color: theme.colorScheme.onSurfaceVariant,
            ) ??
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.9,
          color: theme.colorScheme.onSurfaceVariant,
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text.toUpperCase(), style: style),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = 760.0;
        final theme = Theme.of(context);
        final headingBg = theme.colorScheme.surfaceVariant;
        final dataStyle = theme.textTheme.bodyMedium;

        final table = DataTableTheme(
          data: DataTableThemeData(
            headingRowColor: MaterialStatePropertyAll(headingBg),
            headingTextStyle: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            dataTextStyle: dataStyle,
            dividerThickness: 0.8,
          ),
          child: DataTable(
            showCheckboxColumn: false,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            columnSpacing: 20,
            horizontalMargin: 14,
            headingRowHeight: 44,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 56,
            columns: [
              DataColumn(
                label: _headerLabel(context, 'Item Name'),
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn(
                label: _headerLabel(context, 'Group'),
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn(
                label: _headerLabel(context, 'UoM'),
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn(
                label: _headerLabel(context, 'Cost / Unit'),
                numeric: true,
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn(
                label: _headerLabel(context, 'On Hand'),
                numeric: true,
                onSort: (i, asc) => _onSort(i, asc),
              ),
            ],
            rows: _sorted.map((item) {
              final isLowStock = item.isLowStock;
              final stockStyle = TextStyle(
                fontWeight: FontWeight.w700,
                color: isLowStock
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              );
              return DataRow(
                onSelectChanged: (_) => widget.onRowTap(item),
                cells: [
                  DataCell(Text(item.name)),
                  DataCell(Text(item.category)),
                  DataCell(Text(item.unit)),
                  DataCell(Text('₱' + item.unitCost.toStringAsFixed(2))),
                  DataCell(
                    Text(item.currentStock.toString() + item.unit, style: stockStyle),
                  ),
                ],
              );
            }).toList(),
          ),
        );

        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth < minWidth
                      ? minWidth
                      : constraints.maxWidth,
                ),
                child: table,
              ),
            ),
          ),
        );
      },
    );
  }
}
