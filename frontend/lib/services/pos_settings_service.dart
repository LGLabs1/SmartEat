import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_service.dart';

/// Eatery-level POS preferences, shared by all staff.
///
/// Stored on `eateries/{eateryId}/settings/pos`. Receipt printing is a
/// placeholder for a future wireless receipt printer integration: nothing
/// prints yet, but the configuration surface exists.
class PosSettings {
  const PosSettings({
    this.receiptPrintingEnabled = false,
    this.askForReceipt = false,
  });

  /// Master switch for the receipt printer. Off until a printer is connected.
  final bool receiptPrintingEnabled;

  /// When true, checkout offers a "print a receipt for this order?" option
  /// before the order is completed.
  final bool askForReceipt;

  factory PosSettings.fromMap(Map<String, dynamic>? data) {
    return PosSettings(
      receiptPrintingEnabled: data?['receiptPrintingEnabled'] == true,
      askForReceipt: data?['askForReceipt'] == true,
    );
  }

  PosSettings copyWith({
    bool? receiptPrintingEnabled,
    bool? askForReceipt,
  }) {
    return PosSettings(
      receiptPrintingEnabled: receiptPrintingEnabled ?? this.receiptPrintingEnabled,
      askForReceipt: askForReceipt ?? this.askForReceipt,
    );
  }
}

class PosSettingsService {
  PosSettingsService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _settingsRef(
      String eateryId) {
    return _firestore
        .collection('eateries')
        .doc(eateryId)
        .collection('settings')
        .doc('pos');
  }

  /// Loads the eatery's POS settings, falling back to defaults when the
  /// document (or eatery) is missing.
  static Future<PosSettings> load() async {
    final eateryId = await FirebaseService.getCurrentEateryId();
    if (eateryId == null || eateryId.trim().isEmpty) {
      return const PosSettings();
    }
    final snap = await _settingsRef(eateryId.trim()).get();
    return PosSettings.fromMap(snap.data());
  }

  static Future<void> save(PosSettings settings) async {
    final eateryId = await FirebaseService.getCurrentEateryId();
    if (eateryId == null || eateryId.trim().isEmpty) {
      throw Exception('No eatery linked');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await _settingsRef(eateryId.trim()).set(
      {
        'eateryId': eateryId.trim(),
        'receiptPrintingEnabled': settings.receiptPrintingEnabled,
        'askForReceipt': settings.askForReceipt,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
