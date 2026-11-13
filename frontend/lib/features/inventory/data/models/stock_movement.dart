import 'package:cloud_firestore/cloud_firestore.dart';

enum StockMovementType {
  purchase,
  adjustIncrease,
  adjustDecrease,
  saleConsumption,
  writeOff,
  damaged,
  countCorrection,
}

enum StockMovementRefType {
  purchase,
  adjustment,
  order,
  damaged,
  count,
}

class StockMovement {
  final String id;
  final String itemId;
  final String locationId;
  final StockMovementType type;
  final StockMovementRefType referenceType;
  final String? referenceId;
  final double qtyBeforeBase;
  final double qtyAfterBase;
  final double changeBase;
  final double unitCostAtEvent;
  final double totalCostImpact;
  final String? performedBy;
  final String? reasonCode;
  final String? notes;
  final DateTime timestamp;

  StockMovement({
    required this.id,
    required this.itemId,
    this.locationId = 'main',
    required this.type,
    required this.referenceType,
    this.referenceId,
    required this.qtyBeforeBase,
    required this.qtyAfterBase,
    required this.changeBase,
    this.unitCostAtEvent = 0.0,
    this.totalCostImpact = 0.0,
    this.performedBy,
    this.reasonCode,
    this.notes,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    final dynamic ts = json['timestamp'];
    DateTime tsParsed;
    if (ts == null) {
      tsParsed = DateTime.now();
    } else if (ts is String) {
      tsParsed = DateTime.parse(ts);
    } else if (ts.runtimeType.toString().contains('Timestamp')) {
      tsParsed = (ts as Timestamp).toDate();
    } else {
      try {
        tsParsed = DateTime.parse(ts.toString());
      } catch (_) {
        tsParsed = DateTime.now();
      }
    }
    return StockMovement(
      id: json['id'] ?? '',
      itemId: json['itemId'] ?? '',
      locationId: json['locationId'] ?? 'main',
      type: _parseType(json['type']),
      referenceType: _parseRefType(json['referenceType']),
      referenceId: json['referenceId'],
      qtyBeforeBase: (json['qtyBeforeBase'] ?? 0).toDouble(),
      qtyAfterBase: (json['qtyAfterBase'] ?? 0).toDouble(),
      changeBase: (json['changeBase'] ?? 0).toDouble(),
      unitCostAtEvent: (json['unitCostAtEvent'] ?? 0).toDouble(),
      totalCostImpact: (json['totalCostImpact'] ?? 0).toDouble(),
      performedBy: json['performedBy'],
      reasonCode: json['reasonCode'],
      notes: json['notes'],
      timestamp: tsParsed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemId': itemId,
        'locationId': locationId,
        'type': _typeToString(type),
        'referenceType': _refTypeToString(referenceType),
        'referenceId': referenceId,
        'qtyBeforeBase': qtyBeforeBase,
        'qtyAfterBase': qtyAfterBase,
        'changeBase': changeBase,
        'unitCostAtEvent': unitCostAtEvent,
        'totalCostImpact': totalCostImpact,
        'performedBy': performedBy,
        'reasonCode': reasonCode,
        'notes': notes,
        'timestamp': timestamp.toIso8601String(),
      };

  static StockMovementType _parseType(dynamic v) {
    if (v is String) {
      final s = v.toLowerCase();
      if (s == 'purchase') return StockMovementType.purchase;
      if (s == 'adjustincrease' || s == 'adjust_increase') return StockMovementType.adjustIncrease;
      if (s == 'adjustdecrease' || s == 'adjust_decrease') return StockMovementType.adjustDecrease;
      if (s == 'saleconsumption' || s == 'sale_consumption') return StockMovementType.saleConsumption;
      if (s == 'writeoff' || s == 'write_off') return StockMovementType.writeOff;
      if (s == 'damaged') return StockMovementType.damaged;
      if (s == 'countcorrection' || s == 'count_correction') return StockMovementType.countCorrection;
    }
    return StockMovementType.adjustIncrease;
  }

  static String _typeToString(StockMovementType t) {
    switch (t) {
      case StockMovementType.purchase:
        return 'purchase';
      case StockMovementType.adjustIncrease:
        return 'adjustIncrease';
      case StockMovementType.adjustDecrease:
        return 'adjustDecrease';
      case StockMovementType.saleConsumption:
        return 'saleConsumption';
      case StockMovementType.writeOff:
        return 'writeOff';
      case StockMovementType.damaged:
        return 'damaged';
      case StockMovementType.countCorrection:
        return 'countCorrection';
    }
  }

  static StockMovementRefType _parseRefType(dynamic v) {
    if (v is String) {
      final s = v.toLowerCase();
      if (s == 'purchase') return StockMovementRefType.purchase;
      if (s == 'adjustment') return StockMovementRefType.adjustment;
      if (s == 'order') return StockMovementRefType.order;
      if (s == 'damaged') return StockMovementRefType.damaged;
      if (s == 'count') return StockMovementRefType.count;
    }
    return StockMovementRefType.adjustment;
  }

  static String _refTypeToString(StockMovementRefType t) {
    switch (t) {
      case StockMovementRefType.purchase:
        return 'purchase';
      case StockMovementRefType.adjustment:
        return 'adjustment';
      case StockMovementRefType.order:
        return 'order';
      case StockMovementRefType.damaged:
        return 'damaged';
      case StockMovementRefType.count:
        return 'count';
    }
  }
}
