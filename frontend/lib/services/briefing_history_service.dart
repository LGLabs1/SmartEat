import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../widgets/sage_briefing_card.dart';
import 'briefing_history.dart';
import 'firebase_service.dart';

/// Durable, per-eatery storage for Sage briefings.
///
/// Docs live at `eateries/{eateryId}/sage_briefings/{yyyy-MM-dd_period}` and
/// match the schema enforced by `firestore.rules`:
///   eateryId, title, summary, recommendation, businessHealth (number),
///   detailText, generatedAt (timestamp), period, snapshot (map),
///   schemaVersion (1).
class BriefingHistoryService {
  BriefingHistoryService._();

  static const String collection = 'sage_briefings';
  static const int schemaVersion = 1;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>>? _col(String? eateryId) {
    if (eateryId == null || eateryId.isEmpty) return null;
    return _firestore
        .collection(FirebaseService.eateriesCollection)
        .doc(eateryId)
        .collection(collection);
  }

  /// One briefing per period per day → deterministic, duplicate-proof id.
  static String docId(SageBriefingContent briefing) =>
      '${briefingDateKey(briefing.generatedAt)}_${briefing.period}';

  // ── Mapping ────────────────────────────────────────────────────────────────

  static Map<String, dynamic> toFirestore(
    String eateryId,
    SageBriefingContent briefing,
  ) {
    return {
      'eateryId': eateryId,
      'title': briefing.title,
      'summary': briefing.summary,
      'recommendation': briefing.recommendation,
      'businessHealth': _scoreFrom(briefing.businessHealth),
      'detailText': briefing.detailText,
      'generatedAt': Timestamp.fromDate(briefing.generatedAt),
      'period': briefing.period,
      'snapshot': {
        'healthLabel': _labelFrom(briefing.businessHealth),
        'periodLabel': briefing.periodLabel,
        'content': briefing.toJson(),
      },
      'schemaVersion': schemaVersion,
    };
  }

  static SageBriefingContent fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final rawTimestamp = data['generatedAt'];
    final generatedAt = rawTimestamp is Timestamp
        ? rawTimestamp.toDate()
        : DateTime.tryParse(rawTimestamp?.toString() ?? '') ?? DateTime.now();

    final snapshot =
        (data['snapshot'] as Map?)?.cast<String, dynamic>() ?? const {};
    final score = _asDouble(data['businessHealth']);
    final label = (snapshot['healthLabel'] as String?)?.trim() ?? '';
    final healthLabel = label.isEmpty ? 'Health' : label;

    final period = (data['period'] ?? '').toString();
    final periodLabel = (snapshot['periodLabel'] as String?)?.trim();

    return SageBriefingContent(
      id: id,
      title: (data['title'] ?? '').toString(),
      summary: (data['summary'] ?? '').toString(),
      periodLabel: (periodLabel == null || periodLabel.isEmpty)
          ? '${briefingPeriodShortLabel(period)} briefing'
          : periodLabel,
      generatedAt: generatedAt,
      recommendation: (data['recommendation'] ?? '').toString(),
      businessHealth: '$healthLabel (${score.toStringAsFixed(0)}/100)',
      detailText: (data['detailText'] ?? '').toString(),
      period: period,
    );
  }

  // ── IO ─────────────────────────────────────────────────────────────────────

  /// Creates the briefing document. Failures (offline, permissions, or a
  /// duplicate from another device) are logged and swallowed.
  static Future<void> save(
    String? eateryId,
    SageBriefingContent briefing,
  ) async {
    final col = _col(eateryId);
    if (col == null) return;
    try {
      await col
          .doc(docId(briefing))
          .set(toFirestore(eateryId!, briefing));
    } catch (e) {
      debugPrint('BriefingHistoryService.save failed: $e');
    }
  }

  static Future<List<SageBriefingContent>> fetch(
    String? eateryId, {
    int limit = 120,
  }) async {
    final col = _col(eateryId);
    if (col == null) return const [];
    try {
      final snap = await col
          .orderBy('generatedAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs
          .map((doc) => fromFirestore(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('BriefingHistoryService.fetch failed: $e');
      return const [];
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Extracts the numeric score from labels like "Good (75/100)".
  static double _scoreFrom(String businessHealth) {
    final match =
        RegExp(r'(\d+(?:\.\d+)?)\s*/\s*100').firstMatch(businessHealth);
    if (match == null) return 0;
    return double.tryParse(match.group(1)!) ?? 0;
  }

  /// Extracts the text part from labels like "Good (75/100)".
  static String _labelFrom(String businessHealth) {
    final open = businessHealth.indexOf('(');
    if (open <= 0) return businessHealth.trim();
    return businessHealth.substring(0, open).trim();
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
