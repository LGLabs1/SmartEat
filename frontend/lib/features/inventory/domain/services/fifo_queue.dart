class FifoLot {
  final double qtyRemainingBase;
  final double unitCostPerBase;

  FifoLot({
    required this.qtyRemainingBase,
    required this.unitCostPerBase,
  });

  FifoLot copyWith({
    double? qtyRemainingBase,
    double? unitCostPerBase,
  }) {
    return FifoLot(
      qtyRemainingBase: qtyRemainingBase ?? this.qtyRemainingBase,
      unitCostPerBase: unitCostPerBase ?? this.unitCostPerBase,
    );
  }
}

class FifoConsumptionResult {
  final double totalCostImpact;
  final List<FifoLot> remainingLots;

  FifoConsumptionResult({
    required this.totalCostImpact,
    required this.remainingLots,
  });
}

class FifoQueueService {
  static List<FifoLot> addPurchase(List<FifoLot> lots, double qtyBase, double unitCostPerBase) {
    if (qtyBase <= 0 || unitCostPerBase < 0) return List<FifoLot>.from(lots);
    final newLots = List<FifoLot>.from(lots);
    newLots.add(FifoLot(qtyRemainingBase: qtyBase, unitCostPerBase: unitCostPerBase));
    return newLots;
  }

  static FifoConsumptionResult consume(List<FifoLot> lots, double qtyBase) {
    if (qtyBase <= 0) {
      return FifoConsumptionResult(
        totalCostImpact: 0.0,
        remainingLots: List<FifoLot>.from(lots),
      );
    }
    final remaining = <FifoLot>[];
    double toConsume = qtyBase;
    double costImpact = 0.0;
    for (final lot in lots) {
      if (toConsume <= 0) {
        remaining.add(lot);
        continue;
      }
      if (lot.qtyRemainingBase <= 0) continue;
      final take = toConsume < lot.qtyRemainingBase ? toConsume : lot.qtyRemainingBase;
      costImpact += take * lot.unitCostPerBase;
      toConsume -= take;
      final left = lot.qtyRemainingBase - take;
      if (left > 0) {
        remaining.add(lot.copyWith(qtyRemainingBase: left));
      }
    }
    return FifoConsumptionResult(
      totalCostImpact: costImpact,
      remainingLots: remaining,
    );
  }

  static double computeTotalValue(List<FifoLot> lots) {
    double total = 0.0;
    for (final lot in lots) {
      total += lot.qtyRemainingBase * lot.unitCostPerBase;
    }
    return total;
  }

  static double computeAvgCost(List<FifoLot> lots) {
    double qty = 0.0;
    double cost = 0.0;
    for (final lot in lots) {
      qty += lot.qtyRemainingBase;
      cost += lot.qtyRemainingBase * lot.unitCostPerBase;
    }
    if (qty <= 0) return 0.0;
    return cost / qty;
  }
}
