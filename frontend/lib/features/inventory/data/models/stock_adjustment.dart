import 'package:cloud_firestore/cloud_firestore.dart';

class StockAdjustment {
  final String id;
  final String adjustmentNumber;
  final String itemId;
  final String locationId;
  final double deltaBase;
  final double qtyBeforeBase;
  final double qtyAfterBase;
  final String reasonCode;
  final String? notes;
  final String? performedBy;
  final DateTime performedAt;
  final String status;

  StockAdjustment({
    required this.id,
    required this.adjustmentNumber,
    required this.itemId,
    this.locationId = 'main',
    required this.deltaBase,
    required this.qtyBeforeBase,
    required this.qtyAfterBase,
    required this.reasonCode,
    this.notes,
    this.performedBy,
    DateTime? performedAt,
    this.status = 'applied',
  }) : performedAt = performedAt ?? DateTime.now();

  factory StockAdjustment.fromJson(Map<String, dynamic> json) {
    final dynamic ts = json['performedAt'];
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
    return StockAdjustment(
      id: json['id'] ?? '',
      adjustmentNumber: json['adjustmentNumber'] ?? '',
      itemId: json['itemId'] ?? '',
      locationId: json['locationId'] ?? 'main',
      deltaBase: (json['deltaBase'] ?? 0).toDouble(),
      qtyBeforeBase: (json['qtyBeforeBase'] ?? 0).toDouble(),
      qtyAfterBase: (json['qtyAfterBase'] ?? 0).toDouble(),
      reasonCode: json['reasonCode'] ?? '',
      notes: json['notes'],
      performedBy: json['performedBy'],
      performedAt: tsParsed,
      status: json['status'] ?? 'applied',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'adjustmentNumber': adjustmentNumber,
        'itemId': itemId,
        'locationId': locationId,
        'deltaBase': deltaBase,
        'qtyBeforeBase': qtyBeforeBase,
        'qtyAfterBase': qtyAfterBase,
        'reasonCode': reasonCode,
        'notes': notes,
        'performedBy': performedBy,
        'performedAt': performedAt.toIso8601String(),
        'status': status,
      };
}
