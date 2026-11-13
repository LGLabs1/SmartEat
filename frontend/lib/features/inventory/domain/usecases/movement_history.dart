import '../../data/models/stock_movement.dart';

class MovementsFilter {
  final String? itemId;
  final DateTime? from;
  final DateTime? to;
  final String? type;
  MovementsFilter({this.itemId, this.from, this.to, this.type});
}

class MovementHistoryUseCase {
  List<StockMovement> filter(List<StockMovement> movements, MovementsFilter f) {
    return movements.where((m) {
      if (f.itemId != null && m.itemId != f.itemId) return false;
      if (f.from != null && m.timestamp.isBefore(f.from!)) return false;
      if (f.to != null && m.timestamp.isAfter(f.to!)) return false;
      return true;
    }).toList();
  }
}
