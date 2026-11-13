import 'package:cloud_firestore/cloud_firestore.dart';

class DamagedRecord {
  final String id;
  final String itemId;
  final double qtyBase;
  final double costImpact;
  final String reason;
  final String status;
  final String? reportedBy;
  final DateTime? disposedAt;
  final String? notes;
  final String? referenceId;

  DamagedRecord({
    required this.id,
    required this.itemId,
    required this.qtyBase,
    required this.costImpact,
    required this.reason,
    this.status = 'reported',
    this.reportedBy,
    this.disposedAt,
    this.notes,
    this.referenceId,
  });

  factory DamagedRecord.fromJson(Map<String, dynamic> json) {
    DateTime? disposedAtParsed;
    final dynamic d = json['disposedAt'];
    if (d != null) {
      if (d is String) {
        disposedAtParsed = DateTime.parse(d);
      } else if (d.runtimeType.toString().contains('Timestamp')) {
        disposedAtParsed = (d as Timestamp).toDate();
      } else {
        try {
          disposedAtParsed = DateTime.parse(d.toString());
        } catch (_) {
          disposedAtParsed = null;
        }
      }
    }
    return DamagedRecord(
      id: json['id'] ?? '',
      itemId: json['itemId'] ?? '',
      qtyBase: (json['qtyBase'] ?? 0).toDouble(),
      costImpact: (json['costImpact'] ?? 0).toDouble(),
      reason: json['reason'] ?? '',
      status: json['status'] ?? 'reported',
      reportedBy: json['reportedBy'],
      disposedAt: disposedAtParsed,
      notes: json['notes'],
      referenceId: json['referenceId'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemId': itemId,
        'qtyBase': qtyBase,
        'costImpact': costImpact,
        'reason': reason,
        'status': status,
        'reportedBy': reportedBy,
        'disposedAt': disposedAt?.toIso8601String(),
        'notes': notes,
        'referenceId': referenceId,
      };
}
