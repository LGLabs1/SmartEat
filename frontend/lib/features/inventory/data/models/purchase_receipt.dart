import 'package:cloud_firestore/cloud_firestore.dart';

class PurchaseReceiptItem {
  final String itemId;
  final double qtyBase;
  final double qtyPurchased;
  final String? purchaseUnit;
  final double conversionFactor;
  final double unitCostPerBase;

  PurchaseReceiptItem({
    required this.itemId,
    required this.qtyBase,
    required this.qtyPurchased,
    this.purchaseUnit,
    this.conversionFactor = 1.0,
    required this.unitCostPerBase,
  });

  factory PurchaseReceiptItem.fromJson(Map<String, dynamic> json) {
    return PurchaseReceiptItem(
      itemId: json['itemId'] ?? '',
      qtyBase: (json['qtyBase'] ?? 0).toDouble(),
      qtyPurchased: (json['qtyPurchased'] ?? 0).toDouble(),
      purchaseUnit: json['purchaseUnit'],
      conversionFactor: (json['conversionFactor'] ?? 1.0).toDouble(),
      unitCostPerBase: (json['unitCostPerBase'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'qtyBase': qtyBase,
        'qtyPurchased': qtyPurchased,
        'purchaseUnit': purchaseUnit,
        'conversionFactor': conversionFactor,
        'unitCostPerBase': unitCostPerBase,
      };
}

class PurchaseReceipt {
  final String id;
  final String receiptNumber;
  final String? supplierName;
  final String? supplierId;
  final String? receivedBy;
  final DateTime receivedAt;
  final String status;
  final String? notes;
  final List<PurchaseReceiptItem> items;

  PurchaseReceipt({
    required this.id,
    required this.receiptNumber,
    this.supplierName,
    this.supplierId,
    this.receivedBy,
    DateTime? receivedAt,
    this.status = 'received',
    this.notes,
    List<PurchaseReceiptItem>? items,
  })  : receivedAt = receivedAt ?? DateTime.now(),
        items = items ?? const [];

  factory PurchaseReceipt.fromJson(Map<String, dynamic> json) {
    final dynamic ts = json['receivedAt'];
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
    return PurchaseReceipt(
      id: json['id'] ?? '',
      receiptNumber: json['receiptNumber'] ?? '',
      supplierName: json['supplierName'],
      supplierId: json['supplierId'],
      receivedBy: json['receivedBy'],
      receivedAt: tsParsed,
      status: json['status'] ?? 'received',
      notes: json['notes'],
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => PurchaseReceiptItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'receiptNumber': receiptNumber,
        'supplierName': supplierName,
        'supplierId': supplierId,
        'receivedBy': receivedBy,
        'receivedAt': receivedAt.toIso8601String(),
        'status': status,
        'notes': notes,
        'items': items.map((e) => e.toJson()).toList(),
      };
}
