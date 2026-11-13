import '../../data/models/stock_movement.dart';

class CogsUseCase {
  double compute(List<StockMovement> movements, {DateTime? from, DateTime? to}) {
    double sum = 0.0;
    for (final m in movements) {
      if (m.type != StockMovementType.saleConsumption) continue;
      final t = m.timestamp;
      if (from != null && t.isBefore(from)) continue;
      if (to != null && t.isAfter(to)) continue;
      sum += m.totalCostImpact;
    }
    return sum;
  }
}
