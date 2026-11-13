import '../../../../../models/inventory_item.dart';
import '../../data/models/stock_movement.dart';

class HealthScoreResult {
  final double score;
  final String band;
  final Map<String, double> factors;

  HealthScoreResult({
    required this.score,
    required this.band,
    required this.factors,
  });
}

class InventoryHealthScoreUseCase {
  HealthScoreResult compute({
    required List<InventoryItem> items,
    required List<StockMovement> movements,
  }) {
    final active = items.where((i) => i.isActive).toList();
    if (active.isEmpty) {
      return HealthScoreResult(score: 100, band: 'Excellent', factors: const {});
    }
    int outOfStock = active.where((i) => i.currentStock <= 0).length;
    int lowStock = active
        .where((i) => i.currentStock > 0 && i.isLowStock)
        .length;
    final total = active.length;
    double stockoutComponent = 100 -
        ((outOfStock * 40 + lowStock * 15) / total).clamp(0, 100);
    stockoutComponent = stockoutComponent.clamp(0, 100);

    int overstockCount = 0;
    for (final i in active) {
      if (i.maxStock > 0 && i.currentStock > i.maxStock * 1.10) {
        overstockCount++;
      }
    }
    double overstockComponent =
        100 - ((overstockCount * 30) / total).clamp(0, 100);
    overstockComponent = overstockComponent.clamp(0, 100);

    double shrinkageComponent = 100;
    double activityComponent = 100;

    double score = (stockoutComponent * 0.40 +
            overstockComponent * 0.30 +
            shrinkageComponent * 0.20 +
            activityComponent * 0.10)
        .clamp(0, 100);

    String band;
    if (score >= 90) {
      band = 'Excellent';
    } else if (score >= 80) {
      band = 'Good';
    } else if (score >= 70) {
      band = 'Fair';
    } else if (score >= 50) {
      band = 'Needs Attention';
    } else {
      band = 'Critical';
    }

    return HealthScoreResult(
      score: score,
      band: band,
      factors: {
        'stockout': stockoutComponent,
        'overstock': overstockComponent,
        'shrinkage': shrinkageComponent,
        'activity': activityComponent,
      },
    );
  }
}
