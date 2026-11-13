import '../../data/models/stock_movement.dart';
import '../../data/models/menu_item_ingredient.dart';

class ConsumedItem {
  final String ingredientItemId;
  final double qtyBase;
  ConsumedItem({required this.ingredientItemId, required this.qtyBase});
}

class TopConsumedUseCase {
  List<ConsumedItem> compute(
    List<StockMovement> movements,
    List<MenuItemIngredient> ingredients, {
    DateTime? from,
    DateTime? to,
  }) {
    final Map<String, double> map = {};
    for (final m in movements) {
      if (m.type != StockMovementType.saleConsumption) continue;
      final t = m.timestamp;
      if (from != null && t.isBefore(from)) continue;
      if (to != null && t.isAfter(to)) continue;
      map[m.itemId] = (map[m.itemId] ?? 0) + m.changeBase.abs();
    }
    final list = map.entries
        .map((e) => ConsumedItem(ingredientItemId: e.key, qtyBase: e.value))
        .toList();
    list.sort((a, b) => b.qtyBase.compareTo(a.qtyBase));
    return list;
  }
}

class DailyUsage {
  final DateTime date;
  final double qtyBase;
  DailyUsage({required this.date, required this.qtyBase});
}

class DailyUsageUseCase {
  List<DailyUsage> compute(
    List<StockMovement> movements,
    String ingredientItemId, {
    DateTime? from,
    DateTime? to,
  }) {
    final Map<String, double> map = {};
    for (final m in movements) {
      if (m.type != StockMovementType.saleConsumption) continue;
      if (m.itemId != ingredientItemId) continue;
      final t = m.timestamp;
      if (from != null && t.isBefore(from)) continue;
      if (to != null && t.isAfter(to)) continue;
      final key = DateTime(t.year, t.month, t.day).toIso8601String();
      map[key] = (map[key] ?? 0) + m.changeBase.abs();
    }
    final list = map.entries.map((e) {
      return DailyUsage(date: DateTime.parse(e.key), qtyBase: e.value);
    }).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }
}
