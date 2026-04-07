import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math';

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static bool _looksLikeTransientFirestoreError(Object e) {
    dynamic current = e;
    for (int i = 0; i < 3; i++) {
      try {
        final next = current.error;
        if (next == null || next == current) break;
        current = next;
      } catch (_) {
        break;
      }
    }

    if (current is FirebaseException) {
      final code = (current.code).toString().toLowerCase().trim();
      if (code == 'unavailable' || code == 'deadline-exceeded') return true;
      final msg = (current.message ?? '').toLowerCase();
      if (msg.contains('unable to resolve host') ||
          msg.contains('firestore.googleapis.com')) {
        return true;
      }
    }

    final s = current.toString().toLowerCase();
    return s.contains('unavailable') &&
            (s.contains('unable to resolve host') ||
                s.contains('firestore.googleapis.com')) ||
        s.contains('deadline-exceeded');
  }

  static Future<T> _withRetry<T>(Future<T> Function() op) async {
    const maxAttempts = 3;
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await op();
      } catch (e) {
        final transient = _looksLikeTransientFirestoreError(e);
        if (!transient || attempt >= maxAttempts) rethrow;
        final backoffMs = 350 * (1 << (attempt - 1));
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
      }
    }
  }

  // Collections
  static const String usersCollection = 'users';
  static const String eateriesCollection = 'eateries';
  static const String menuCollection = 'menu';
  static const String ordersCollection = 'orders';
  static const String inventoryCollection = 'inventory';
  static const String inventoryUsageCollection = 'inventory_usage';
  static const String analyticsCollection = 'analytics';
  static const String recipesCollection = 'recipes';
  static const String expensesCollection = 'expenses';
  static const String payablesCollection = 'payables';
  static const String staffMealsCollection = 'staff_meals';

  static CollectionReference<Map<String, dynamic>> _eaterySubcollection(
    String eateryId,
    String name,
  ) {
    return _firestore
        .collection(eateriesCollection)
        .doc(eateryId)
        .collection(name);
  }

  static const String _eateryIdAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _randomEateryId(int length) {
    final rnd = Random.secure();
    return List.generate(
      length,
      (_) => _eateryIdAlphabet[rnd.nextInt(_eateryIdAlphabet.length)],
    ).join();
  }

  // Finance/Expenses methods
  static Future<List<Map<String, dynamic>>> getExpenses() async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final querySnapshot = await _withRetry(
        () => _eaterySubcollection(eateryId, expensesCollection)
            .orderBy('createdAt', descending: true)
            .get(),
      );
      return querySnapshot.docs.map((doc) {
        final Map<String, dynamic> result = {'id': doc.id};
        result.addAll(doc.data());
        return result;
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch expenses: $e');
    }
  }

  static Future<Map<String, dynamic>> createExpense(
    Map<String, dynamic> expenseData,
  ) async {
    try {
      await _requireAdmin();
      final eateryId = await _requireCurrentEateryId();
      final docRef =
          await _eaterySubcollection(eateryId, expensesCollection).add({
        ...expenseData,
        'eateryId': eateryId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final docSnapshot = await docRef.get();
      return {
        'id': docRef.id,
        ...?docSnapshot.data(),
      };
    } catch (e) {
      throw Exception('Failed to create expense: $e');
    }
  }

  static Future<void> deleteExpense(String id) async {
    try {
      await _requireAdmin();
      final eateryId = await _requireCurrentEateryId();
      await _eaterySubcollection(eateryId, expensesCollection).doc(id).delete();
    } catch (e) {
      throw Exception('Failed to delete expense: $e');
    }
  }

  // Finance/Payables methods
  static Future<List<Map<String, dynamic>>> getPayables() async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final querySnapshot = await _withRetry(
        () => _eaterySubcollection(eateryId, payablesCollection)
            .orderBy('createdAt', descending: true)
            .get(),
      );
      return querySnapshot.docs.map((doc) {
        final Map<String, dynamic> result = {'id': doc.id};
        result.addAll(doc.data());
        return result;
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch payables: $e');
    }
  }

  static Future<Map<String, dynamic>> createPayable(
    Map<String, dynamic> payableData,
  ) async {
    try {
      await _requireAdmin();
      final eateryId = await _requireCurrentEateryId();
      final docRef =
          await _eaterySubcollection(eateryId, payablesCollection).add({
        ...payableData,
        'eateryId': eateryId,
        'status': payableData['status'] ?? 'unpaid',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final docSnapshot = await docRef.get();
      return {
        'id': docRef.id,
        ...?docSnapshot.data(),
      };
    } catch (e) {
      throw Exception('Failed to create payable: $e');
    }
  }

  static Future<void> updatePayableStatus(String id,
      {required String status}) async {
    try {
      await _requireAdmin();
      final eateryId = await _requireCurrentEateryId();
      await _eaterySubcollection(eateryId, payablesCollection).doc(id).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update payable: $e');
    }
  }

  static Future<Map<String, dynamic>> updatePayable(
    String id,
    Map<String, dynamic> payableData,
  ) async {
    try {
      await _requireAdmin();
      final eateryId = await _requireCurrentEateryId();
      await _eaterySubcollection(eateryId, payablesCollection).doc(id).update({
        ...payableData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final docSnapshot =
          await _eaterySubcollection(eateryId, payablesCollection)
              .doc(id)
              .get();
      return {
        'id': id,
        ...?docSnapshot.data(),
      };
    } catch (e) {
      throw Exception('Failed to update payable: $e');
    }
  }

  static Future<void> deletePayable(String id) async {
    try {
      await _requireAdmin();
      final eateryId = await _requireCurrentEateryId();
      await _eaterySubcollection(eateryId, payablesCollection).doc(id).delete();
    } catch (e) {
      throw Exception('Failed to delete payable: $e');
    }
  }

  // Recipe methods (retained for compatibility)
  static Future<List<Map<String, dynamic>>> getRecipes() async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final querySnapshot =
          await _eaterySubcollection(eateryId, recipesCollection).get();

      final items = querySnapshot.docs.map((doc) {
        final Map<String, dynamic> result = {'id': doc.id};
        result.addAll(doc.data());
        return result;
      }).toList();

      items.sort((a, b) {
        final an = (a['name'] ?? '').toString().toLowerCase();
        final bn = (b['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });

      return items;
    } catch (e) {
      throw Exception('Failed to fetch recipes: $e');
    }
  }

  static Future<Map<String, dynamic>> createRecipe(
    Map<String, dynamic> recipeData,
  ) async {
    try {
      await _requireAdmin();
      final eateryId = await _requireCurrentEateryId();

      final docRef =
          await _eaterySubcollection(eateryId, recipesCollection).add({
        ...recipeData,
        'eateryId': eateryId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final docSnapshot = await docRef.get();
      return {
        'id': docRef.id,
        ...?docSnapshot.data(),
      };
    } catch (e) {
      throw Exception('Failed to create recipe: $e');
    }
  }

  static Future<Map<String, dynamic>> getOrderById(String orderId) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final doc = await _eaterySubcollection(eateryId, ordersCollection)
          .doc(orderId)
          .get();
      if (!doc.exists) {
        throw Exception('Order not found');
      }
      final data = doc.data() ?? <String, dynamic>{};
      return {
        'id': doc.id,
        ...data,
      };
    } catch (e) {
      throw Exception('Failed to fetch order: $e');
    }
  }

  static Future<String> generateUniqueEateryId({int length = 6}) async {
    for (var i = 0; i < 20; i++) {
      final id = _randomEateryId(length);
      final doc = await _firestore.collection(eateriesCollection).doc(id).get();
      if (!doc.exists) return id;
    }
    throw Exception('Failed to generate unique eatery id');
  }

  static Future<Map<String, dynamic>?> getEatery(String eateryId) async {
    final docSnapshot =
        await _firestore.collection(eateriesCollection).doc(eateryId).get();
    if (!docSnapshot.exists) return null;
    return {
      'id': docSnapshot.id,
      ...?docSnapshot.data(),
    };
  }

  static Future<Map<String, dynamic>> createEatery({
    required String eateryId,
    required String name,
    required String ownerUid,
  }) async {
    final docRef = _firestore.collection(eateriesCollection).doc(eateryId);
    final existing = await docRef.get();
    if (existing.exists) {
      throw Exception('Eatery ID already exists');
    }

    await docRef.set({
      'eateryId': eateryId,
      'name': name,
      'ownerUid': ownerUid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final docSnapshot = await docRef.get();
    return {
      'id': docSnapshot.id,
      ...docSnapshot.data()!,
    };
  }

  // Initialize Firebase
  static Future<void> initializeFirebase() async {
    if (kIsWeb) {
      // Web uses hardcoded Firebase options
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyAv-5-Db8gu2D1hzBZoCSFwSbeKcmWxuJM",
          authDomain: "smart-eat-2eaf7.firebaseapp.com",
          projectId: "smart-eat-2eaf7",
          storageBucket: "smart-eat-2eaf7.firebasestorage.app",
          messagingSenderId: "362576674400",
          appId: "1:362576674400:web:1ef49ac6e0d384f4eecd05",
          measurementId: "G-630LE42NK7",
        ),
      );
    } else {
      // Android/iOS use native configuration from google-services.json/GoogleService-Info.plist
      await Firebase.initializeApp();
    }
  }

  // Get current user
  static User? getCurrentUser() => _auth.currentUser;

  static Future<String> _requireCurrentEateryId() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }

    final docSnapshot =
        await _firestore.collection(usersCollection).doc(uid).get();
    if (!docSnapshot.exists) {
      throw Exception('User profile not found');
    }

    final data = docSnapshot.data();
    final eateryId = (data?['eateryId'] ?? '').toString().trim();
    if (eateryId.isEmpty) {
      throw Exception('Eatery is not set for this account');
    }
    return eateryId;
  }

  static Future<Map<String, dynamic>> _requireCurrentUserProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('Not authenticated');
    }

    final docSnapshot =
        await _firestore.collection(usersCollection).doc(uid).get();
    if (!docSnapshot.exists) {
      throw Exception('User profile not found');
    }

    final data = docSnapshot.data();
    return data == null ? <String, dynamic>{} : Map<String, dynamic>.from(data);
  }

  static Future<void> _requireAdmin() async {
    final profile = await _requireCurrentUserProfile();
    final role = (profile['role'] ?? '').toString().trim().toLowerCase();
    final dynamic isAdminRaw = profile['isAdmin'];
    final bool isAdminFlag = isAdminRaw == true ||
        isAdminRaw == 1 ||
        (isAdminRaw is String && isAdminRaw.toLowerCase().trim() == 'true');
    final isAdmin = isAdminFlag || role == 'admin';
    if (!isAdmin) {
      throw Exception('Access denied');
    }
  }

  static String _norm(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim();
  }

  // Aggressive error extraction for Flutter web boxed errors
  static String _extractErrorDetails(dynamic e) {
    // Debug: log what we received
    print('DEBUG: Error type: ${e.runtimeType}');
    print('DEBUG: Error toString: $e');

    if (e is FirebaseException) {
      final code = (e.code).toString().trim();
      final msg = (e.message ?? '').toString().trim();
      print('DEBUG: Is FirebaseException - code: $code, message: $msg');
      return msg.isEmpty
          ? 'Firebase error: $code'
          : 'Firebase error: $code — $msg';
    }

    // Handle the specific Flutter web boxed error case
    final errorString = e.toString();
    if (errorString.contains('Dart exception thrown from converted Future')) {
      print('DEBUG: Detected converted Future error, attempting safe unwrap');

      // Try to extract nested error using safe property access
      dynamic nestedError;
      try {
        // Use hasProperty check before accessing
        final hasErrorProp = (e as dynamic).hasProperty != null
            ? (e as dynamic).hasProperty('error')
            : true;
        if (hasErrorProp) {
          nestedError = (e as dynamic).error;
        }
      } catch (_) {
        nestedError = null;
      }

      if (nestedError != null) {
        print('DEBUG: Found nested error: ${nestedError.runtimeType}');
        // Recursively extract from nested error
        final nestedStr = _extractErrorDetails(nestedError);
        if (nestedStr.isNotEmpty &&
            !nestedStr
                .contains('Dart exception thrown from converted Future')) {
          return nestedStr;
        }
        // If recursive extraction didn't work, try toString on nested
        try {
          final nestedToStr = nestedError.toString();
          if (nestedToStr.isNotEmpty &&
              !nestedToStr
                  .contains('Dart exception thrown from converted Future')) {
            return nestedToStr;
          }
        } catch (_) {}
      }

      // Try to get message property safely
      dynamic messageObj;
      try {
        messageObj = (e as dynamic).message;
      } catch (_) {}

      if (messageObj != null) {
        final msgStr = messageObj.toString();
        if (msgStr.isNotEmpty &&
            !msgStr.contains('Dart exception thrown from converted Future')) {
          return msgStr;
        }
      }

      // Fallback: return a cleaned-up version
      return 'Transaction failed. Please try again or check inventory levels.';
    }

    dynamic current = e;
    for (int i = 0; i < 5; i++) {
      print('DEBUG: Unwrapping level $i - type: ${current.runtimeType}');

      if (current is FirebaseException) {
        final code = (current.code).toString().trim();
        final msg = (current.message ?? '').toString().trim();
        print(
            'DEBUG: Found FirebaseException at level $i - code: $code, message: $msg');
        return msg.isEmpty
            ? 'Firebase error: $code'
            : 'Firebase error: $code — $msg';
      }

      // Try to access JS properties using dynamic - with safe guards
      dynamic errorObj;
      dynamic messageObj;
      dynamic codeObj;

      try {
        errorObj = (current as dynamic).error;
      } catch (_) {}

      try {
        messageObj = (current as dynamic).message;
      } catch (_) {}

      try {
        codeObj = (current as dynamic).code;
      } catch (_) {}

      print(
          'DEBUG: Raw props - error: $errorObj (${errorObj?.runtimeType}), message: $messageObj, code: $codeObj');

      // If we have a nested error object, try to extract from it
      if (errorObj != null) {
        // If the wrapper error is the generic converted-future message,
        // try unwrapping the nested error directly.
        final wrapperStr = current.toString();
        if (wrapperStr.contains('Dart exception thrown from Future')) {
          try {
            final nested = _extractErrorDetails(errorObj);
            if (nested.isNotEmpty &&
                !nested
                    .contains('Dart exception thrown from converted Future')) {
              return nested;
            }
          } catch (_) {}
        }

        // Try to convert error object to string
        String errorStr;
        try {
          errorStr = errorObj.toString();
          print('DEBUG: error.toString(): $errorStr');
        } catch (_) {
          errorStr = '';
        }

        // If it's not a generic wrapper, use it
        if (errorStr.isNotEmpty &&
            !errorStr.contains('Dart exception thrown from converted Future') &&
            !errorStr.contains('[object Object]')) {
          print('DEBUG: Using error.toString(): $errorStr');
          return errorStr;
        }

        // Try to get nested error properties
        dynamic nestedError;
        dynamic nestedMessage;
        dynamic nestedCode;
        try {
          nestedError = (errorObj as dynamic).error;
        } catch (_) {}

        try {
          nestedMessage = (errorObj as dynamic).message;
        } catch (_) {}

        try {
          nestedCode = (errorObj as dynamic).code;
        } catch (_) {}

        print(
            'DEBUG: Nested props - error: $nestedError, message: $nestedMessage, code: $nestedCode');

        if (nestedMessage != null) {
          final msg = nestedMessage.toString();
          if (msg.isNotEmpty) {
            final code = nestedCode?.toString() ?? '';
            if (code.isNotEmpty) {
              return 'Firebase error: $code — $msg';
            }
            return msg;
          }
        }

        // Unwrap to next level
        current = errorObj;
        continue;
      }

      // If no nested error but we have a message, use it
      if (messageObj != null) {
        final msg = messageObj.toString();
        if (msg.isNotEmpty &&
            !msg.contains('Dart exception thrown from converted Future')) {
          final code = codeObj?.toString() ?? '';
          if (code.isNotEmpty) {
            return 'Firebase error: $code — $msg';
          }
          return msg;
        }
      }

      break;
    }

    print('DEBUG: Returning fallback: ${current.toString()}');
    return current.toString();
  }

  // Auth methods
  static Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password,
  ) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }

  // Firestore methods
  static CollectionReference<Map<String, dynamic>> getCollection(
    String collectionName,
  ) {
    return _firestore.collection(collectionName);
  }

  // Menu methods
  static Future<List<Map<String, dynamic>>> getMenuItems() async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final querySnapshot = await _withRetry(
        () => _eaterySubcollection(eateryId, menuCollection).get(),
      );

      final items = querySnapshot.docs.map((doc) {
        final Map<String, dynamic> result = {'id': doc.id};
        result.addAll(doc.data());
        return result;
      }).toList();

      items.sort((a, b) {
        final aCreated = a['createdAt'];
        final bCreated = b['createdAt'];
        final aDate = aCreated is Timestamp
            ? aCreated.toDate()
            : aCreated is DateTime
                ? aCreated
                : DateTime.tryParse(aCreated?.toString() ?? '');
        final bDate = bCreated is Timestamp
            ? bCreated.toDate()
            : bCreated is DateTime
                ? bCreated
                : DateTime.tryParse(bCreated?.toString() ?? '');
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      return items;
    } catch (e) {
      throw Exception('Failed to fetch menu items: $e');
    }
  }

  static Future<Map<String, dynamic>> createMenuItem(
    Map<String, dynamic> menuData,
  ) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final docRef = await _eaterySubcollection(eateryId, menuCollection).add({
        ...menuData,
        'eateryId': eateryId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final docSnapshot = await docRef.get();
      return {
        'id': docRef.id,
        ...docSnapshot.data()!,
      };
    } catch (e) {
      throw Exception('Failed to create menu item: $e');
    }
  }

  static Future<Map<String, dynamic>> updateMenuItem(
    String id,
    Map<String, dynamic> updates,
  ) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final existing =
          await _eaterySubcollection(eateryId, menuCollection).doc(id).get();
      if (!existing.exists) {
        throw Exception('Menu item not found');
      }
      final existingEateryId =
          (existing.data()?['eateryId'] ?? '').toString().trim();
      if (existingEateryId.isNotEmpty && existingEateryId != eateryId) {
        throw Exception('Access denied');
      }

      await _eaterySubcollection(eateryId, menuCollection).doc(id).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final docSnapshot =
          await _eaterySubcollection(eateryId, menuCollection).doc(id).get();
      return {
        'id': docSnapshot.id,
        ...docSnapshot.data()!,
      };
    } catch (e) {
      throw Exception('Failed to update menu item: $e');
    }
  }

  static Future<void> deleteMenuItem(String id) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final existing =
          await _eaterySubcollection(eateryId, menuCollection).doc(id).get();
      if (!existing.exists) {
        return;
      }
      final existingEateryId =
          (existing.data()?['eateryId'] ?? '').toString().trim();
      if (existingEateryId.isNotEmpty && existingEateryId != eateryId) {
        throw Exception('Access denied');
      }
      await _eaterySubcollection(eateryId, menuCollection).doc(id).delete();
    } catch (e) {
      throw Exception('Failed to delete menu item: $e');
    }
  }

  // Order methods
  static Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> orderData, {
    String? orderId,
  }) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final ordersRef = _eaterySubcollection(eateryId, ordersCollection);

      final DocumentReference<Map<String, dynamic>> docRef;
      if (orderId != null && orderId.trim().isNotEmpty) {
        // Use the provided order ID
        docRef = ordersRef.doc(orderId.trim());
        await docRef.set({
          ...orderData,
          'eateryId': eateryId,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
      } else {
        // Auto-generate ID
        docRef = await ordersRef.add({
          ...orderData,
          'eateryId': eateryId,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
      }

      final docSnapshot = await docRef.get();
      return {
        'id': docRef.id,
        ...docSnapshot.data()!,
      };
    } catch (e) {
      throw Exception('Failed to create order: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getPendingOrders(
      {int limit = 20}) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final querySnapshot =
          await _eaterySubcollection(eateryId, ordersCollection)
              .where('status', isEqualTo: 'pending')
              .get();

      final orders = querySnapshot.docs.map((doc) {
        final Map<String, dynamic> result = {'id': doc.id};
        result.addAll(doc.data());
        return result;
      }).toList();

      DateTime? parseCreatedAt(dynamic createdAt) {
        if (createdAt is Timestamp) return createdAt.toDate();
        if (createdAt is DateTime) return createdAt;
        return DateTime.tryParse(createdAt?.toString() ?? '');
      }

      orders.sort((a, b) {
        final aDate = parseCreatedAt(a['createdAt']);
        final bDate = parseCreatedAt(b['createdAt']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      if (limit > 0 && orders.length > limit) {
        return orders.take(limit).toList();
      }
      return orders;
    } catch (e) {
      throw Exception('Failed to fetch pending orders: $e');
    }
  }

  static Future<Map<String, dynamic>> addItemsToPendingOrder(
    String orderId,
    List<Map<String, dynamic>> itemsToAdd,
  ) async {
    if (orderId.trim().isEmpty) {
      throw Exception('Order ID is required');
    }
    if (itemsToAdd.isEmpty) {
      throw Exception('No items to add');
    }

    try {
      final eateryId = await _requireCurrentEateryId();
      final orderRef =
          _eaterySubcollection(eateryId, ordersCollection).doc(orderId);

      final sanitizedAddedItems = itemsToAdd.map((it) {
        final menuItemId = (it['menuItemId'] ?? '').toString().trim();
        final name = (it['name'] ?? '').toString();
        final qtyRaw = it['quantity'];
        final qty = qtyRaw is num
            ? qtyRaw.toInt()
            : int.tryParse((qtyRaw ?? '').toString()) ?? 0;
        final priceRaw = it['price'];
        final price = priceRaw is num
            ? priceRaw.toDouble()
            : double.tryParse((priceRaw ?? '').toString()) ?? 0.0;
        final subtotal = price * qty;
        return {
          'menuItemId': menuItemId,
          'name': name,
          'quantity': qty,
          'price': price,
          'subtotal': subtotal,
        };
      }).toList();

      final Map<String, dynamic> updated =
          await _firestore.runTransaction((tx) async {
        final orderSnap = await tx.get(orderRef);
        if (!orderSnap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            message: 'Order not found',
          );
        }
        final order = orderSnap.data() ?? <String, dynamic>{};
        final orderEateryId = (order['eateryId'] ?? '').toString().trim();
        if (orderEateryId.isEmpty || orderEateryId != eateryId) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            message: 'Access denied (eatery mismatch)',
          );
        }

        final status = (order['status'] ?? '').toString().trim().toLowerCase();
        if (status != 'pending') {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            message: 'Only pending orders can be updated (status: $status)',
          );
        }

        List<Map<String, dynamic>> existing = (order['items'] as List?)
                ?.map((e) {
                  if (e is Map<String, dynamic>) return e;
                  if (e is Map) return Map<String, dynamic>.from(e);
                  return <String, dynamic>{};
                })
                .where((e) => e.isNotEmpty)
                .toList() ??
            <Map<String, dynamic>>[];

        final byMenuId = <String, Map<String, dynamic>>{};
        for (final it in existing) {
          final menuItemId = (it['menuItemId'] ?? '').toString().trim();
          if (menuItemId.isEmpty) continue;
          byMenuId[menuItemId] = Map<String, dynamic>.from(it);
        }

        for (final it in itemsToAdd) {
          final menuItemId = (it['menuItemId'] ?? '').toString().trim();
          if (menuItemId.isEmpty) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              message: 'Invalid order item (missing menuItemId)',
            );
          }

          final qtyRaw = it['quantity'];
          final qty = qtyRaw is num
              ? qtyRaw.toInt()
              : int.tryParse((qtyRaw ?? '').toString()) ?? 0;
          if (qty <= 0) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              message: 'Invalid order quantity',
            );
          }

          final priceRaw = it['price'];
          final price = priceRaw is num
              ? priceRaw.toDouble()
              : double.tryParse((priceRaw ?? '').toString()) ?? 0.0;

          final existingLine = byMenuId[menuItemId];
          if (existingLine != null) {
            final existingQtyRaw = existingLine['quantity'];
            final existingQty = existingQtyRaw is num
                ? existingQtyRaw.toInt()
                : int.tryParse((existingQtyRaw ?? '').toString()) ?? 0;
            final nextQty = existingQty + qty;
            existingLine['quantity'] = nextQty;
            existingLine['price'] = price;
            existingLine['subtotal'] = price * nextQty;
            if ((it['name'] ?? '').toString().trim().isNotEmpty) {
              existingLine['name'] = it['name'];
            }
            byMenuId[menuItemId] = existingLine;
          } else {
            final name = (it['name'] ?? '').toString();
            byMenuId[menuItemId] = {
              'menuItemId': menuItemId,
              'name': name,
              'quantity': qty,
              'price': price,
              'subtotal': price * qty,
            };
          }
        }

        final mergedItems = byMenuId.values.toList();
        mergedItems.sort((a, b) {
          final an = (a['name'] ?? '').toString().toLowerCase();
          final bn = (b['name'] ?? '').toString().toLowerCase();
          return an.compareTo(bn);
        });

        double totalAmount = 0.0;
        for (final it in mergedItems) {
          final subRaw = it['subtotal'];
          final sub = subRaw is num
              ? subRaw.toDouble()
              : double.tryParse((subRaw ?? '').toString()) ?? 0.0;
          totalAmount += sub;
        }

        tx.update(orderRef, {
          'items': mergedItems,
          'totalAmount': totalAmount,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastAddedItems': sanitizedAddedItems,
          'lastAddedAt': FieldValue.serverTimestamp(),
        });

        return {
          'id': orderRef.id,
          ...order,
          'items': mergedItems,
          'totalAmount': totalAmount,
          'lastAddedItems': sanitizedAddedItems,
        };
      });

      return updated;
    } on FirebaseException catch (e) {
      throw e;
    } catch (e) {
      throw Exception('Failed to update order: $e');
    }
  }

  static Future<Map<String, dynamic>> completeOrder(String orderId) async {
    String eateryId = '';
    try {
      await _requireAdmin();
      eateryId = await _requireCurrentEateryId();

      final invQuery = _firestore
          .collection(eateriesCollection)
          .doc(eateryId)
          .collection(inventoryCollection);
      final invQuerySnap = await _withRetry(() => invQuery.get());
      final Map<String, DocumentReference> inventoryRefByName = {};
      for (final doc in invQuerySnap.docs) {
        final data = doc.data();
        final key = _norm((data['name'] ?? '').toString());
        if (key.isEmpty) continue;
        inventoryRefByName.putIfAbsent(key, () => doc.reference);
      }

      final orderRef =
          _eaterySubcollection(eateryId, ordersCollection).doc(orderId);

      final Map<String, dynamic> result = await _withRetry(
        () => _firestore.runTransaction((tx) async {
          final orderSnap = await tx.get(orderRef);
          if (!orderSnap.exists) {
            throw Exception('Order not found');
          }
          final order = orderSnap.data() ?? <String, dynamic>{};
          final orderEateryId = (order['eateryId'] ?? '').toString().trim();
          if (orderEateryId.isEmpty || orderEateryId != eateryId) {
            throw Exception('Access denied');
          }

          final status =
              (order['status'] ?? '').toString().trim().toLowerCase();
          if (status == 'completed') {
            return {'ok': true, 'status': 'completed'};
          }
          if (status == 'rejected') {
            return {'ok': true, 'status': 'rejected'};
          }

          final items = (order['items'] as List?)?.cast<dynamic>() ?? const [];
          if (items.isEmpty) {
            throw Exception('Invalid order payload');
          }

          final menuReads = <Map<String, dynamic>>[];
          for (final raw in items) {
            final it = raw as Map?;
            final menuItemId = (it?['menuItemId'] ?? '').toString().trim();
            final qtyNum = it?['quantity'];
            final quantity = qtyNum is num
                ? qtyNum.toInt()
                : int.tryParse(qtyNum?.toString() ?? '') ?? 0;
            if (menuItemId.isEmpty || quantity <= 0) {
              throw Exception('Invalid order item');
            }
            final menuRef =
                _eaterySubcollection(eateryId, menuCollection).doc(menuItemId);
            menuReads.add({'ref': menuRef, 'quantity': quantity});
          }

          final menuSnaps = await Future.wait(
            menuReads.map((m) => tx.get(m['ref'] as DocumentReference)),
          );

          final invLinkReads = <Map<String, dynamic>>[];
          final drinkFallbackReads = <Map<String, dynamic>>[];
          final recipeReads = <Map<String, dynamic>>[];
          final menuNoInvAdjustments = <Map<String, dynamic>>[];

          bool isDrinkMenu(Map<String, dynamic> menu) {
            final cat = _norm((menu['category'] ?? '').toString());
            if (cat == 'drink' || cat == 'drinks') return true;
            final cats = (menu['categories'] is List)
                ? (menu['categories'] as List)
                    .map((e) => _norm(e.toString()))
                    .where((e) => e.isNotEmpty)
                    .toList()
                : const <String>[];
            return cats.contains('drink') || cats.contains('drinks');
          }

          for (var i = 0; i < menuReads.length; i++) {
            final menuSnap = menuSnaps[i];
            if (!menuSnap.exists) {
              final menuRef = menuReads[i]['ref'] as DocumentReference;
              throw Exception('Menu item not found: ${menuRef.id}');
            }
            final menu = (menuSnap.data() as Map<String, dynamic>?) ??
                <String, dynamic>{};
            final menuEateryId = (menu['eateryId'] ?? '').toString().trim();
            if (menuEateryId.isEmpty || menuEateryId != eateryId) {
              throw Exception('Access denied');
            }

            final quantity = menuReads[i]['quantity'] as int;
            final menuRef = menuReads[i]['ref'] as DocumentReference;

            final inventoryItemId =
                (menu['inventoryItemId'] ?? '').toString().trim();
            if (inventoryItemId.isNotEmpty) {
              final invRef = _firestore
                  .collection(eateriesCollection)
                  .doc(eateryId)
                  .collection(inventoryCollection)
                  .doc(inventoryItemId);
              invLinkReads.add(
                  {'invRef': invRef, 'quantity': quantity, 'menuRef': menuRef});
            } else if (isDrinkMenu(menu)) {
              drinkFallbackReads.add(
                  {'menu': menu, 'quantity': quantity, 'menuRef': menuRef});
            } else {
              menuNoInvAdjustments.add(
                  {'menu': menu, 'quantity': quantity, 'menuRef': menuRef});
            }

            final recipeId = (menu['recipeId'] ?? '').toString().trim();
            if (recipeId.isNotEmpty) {
              final recipeRef =
                  _eaterySubcollection(eateryId, recipesCollection)
                      .doc(recipeId);
              recipeReads.add({'recipeRef': recipeRef, 'quantity': quantity});
            }
          }

          final recipeSnaps = recipeReads.isNotEmpty
              ? await Future.wait(
                  recipeReads
                      .map((r) => tx.get(r['recipeRef'] as DocumentReference)),
                )
              : const <DocumentSnapshot>[];

          final requiredByInvRef = <DocumentReference, double>{};
          final ingredientChecks = <String, Map<String, String>>{};

          if (recipeReads.isNotEmpty) {
            for (var i = 0; i < recipeReads.length; i++) {
              final recipeSnap = recipeSnaps[i];
              if (!recipeSnap.exists) {
                final recipeRef =
                    recipeReads[i]['recipeRef'] as DocumentReference;
                throw Exception('Recipe not found: ${recipeRef.id}');
              }
              final recipe = (recipeSnap.data() as Map<String, dynamic>?) ??
                  <String, dynamic>{};
              final quantity = recipeReads[i]['quantity'] as int;
              final baseServingsRaw = recipe['baseServings'];
              final baseServings = baseServingsRaw is num
                  ? baseServingsRaw.toDouble()
                  : double.tryParse(baseServingsRaw?.toString() ?? '') ?? 1.0;
              final factor = baseServings > 0
                  ? quantity / baseServings
                  : quantity.toDouble();

              final ingredients = (recipe['ingredients'] is List)
                  ? (recipe['ingredients'] as List)
                  : const [];

              for (final ing in ingredients) {
                final ingMap = ing as Map?;
                final ingName = (ingMap?['name'] ?? '').toString().trim();
                if (ingName.isEmpty) continue;
                final key = _norm(ingName);
                final invRef = inventoryRefByName[key];
                if (invRef == null) {
                  throw Exception('Missing inventory item: $ingName');
                }

                final baseQtyRaw = ingMap?['quantity'];
                final baseQty = baseQtyRaw is num
                    ? baseQtyRaw.toDouble()
                    : double.tryParse(baseQtyRaw?.toString() ?? '') ?? 0.0;
                if (baseQty <= 0) continue;

                final requiredQty = baseQty * factor;
                requiredByInvRef[invRef] =
                    (requiredByInvRef[invRef] ?? 0) + requiredQty;

                final ingUnit = (ingMap?['unit'] ?? '').toString().trim();
                if (ingUnit.isNotEmpty) {
                  ingredientChecks[invRef.path] = {
                    'name': ingName,
                    'unit': ingUnit,
                  };
                }
              }
            }
          }

          final invRefSet = <DocumentReference>{};
          for (final r in invLinkReads) {
            invRefSet.add(r['invRef'] as DocumentReference);
          }
          for (final r in drinkFallbackReads) {
            final menu = r['menu'] as Map<String, dynamic>;
            final menuName = (menu['name'] ?? '').toString().trim();
            final key = _norm(menuName);
            if (key.isEmpty) {
              throw Exception('Invalid drink menu name');
            }
            final invRef = inventoryRefByName[key];
            if (invRef == null) {
              throw Exception('Missing inventory item for drink: $menuName');
            }
            r['invRef'] = invRef;
            invRefSet.add(invRef);
          }
          invRefSet.addAll(requiredByInvRef.keys);

          final invSnaps = invRefSet.isNotEmpty
              ? await Future.wait(invRefSet.map((ref) => tx.get(ref)))
              : const <DocumentSnapshot>[];
          final invSnapByPath = <String, DocumentSnapshot>{};
          for (final snap in invSnaps) {
            invSnapByPath[snap.reference.path] = snap;
          }

          final currentStockByInvRef = <DocumentReference, double>{};
          for (final invRef in invRefSet) {
            final invSnap = invSnapByPath[invRef.path];
            if (invSnap == null || !invSnap.exists) {
              throw Exception('Inventory item not found: ${invRef.id}');
            }
            final invData = (invSnap.data() as Map<String, dynamic>?) ??
                <String, dynamic>{};
            final invEateryId = (invData['eateryId'] ?? '').toString().trim();
            if (invEateryId.isEmpty || invEateryId != eateryId) {
              throw Exception('Access denied');
            }
            final currentStockRaw = invData['currentStock'];
            final currentStock = currentStockRaw is num
                ? currentStockRaw.toDouble()
                : double.tryParse(currentStockRaw?.toString() ?? '') ?? 0.0;
            currentStockByInvRef[invRef] = currentStock;

            final check = ingredientChecks[invRef.path];
            if (check != null) {
              final invUnit = (invData['unit'] ?? '').toString().trim();
              final ingUnit = (check['unit'] ?? '').toString().trim();
              if (invUnit.isNotEmpty &&
                  ingUnit.isNotEmpty &&
                  _norm(invUnit) != _norm(ingUnit)) {
                throw Exception('Unit mismatch for: ${check['name']}');
              }
            }
          }

          final stockDeltaByInvRef = <DocumentReference, double>{};
          for (final r in invLinkReads) {
            final invRef = r['invRef'] as DocumentReference;
            final qty = (r['quantity'] as int).toDouble();
            stockDeltaByInvRef[invRef] =
                (stockDeltaByInvRef[invRef] ?? 0) + qty;
          }
          for (final r in drinkFallbackReads) {
            final invRef = r['invRef'] as DocumentReference;
            final qty = (r['quantity'] as int).toDouble();
            stockDeltaByInvRef[invRef] =
                (stockDeltaByInvRef[invRef] ?? 0) + qty;
          }
          for (final entry in requiredByInvRef.entries) {
            stockDeltaByInvRef[entry.key] =
                (stockDeltaByInvRef[entry.key] ?? 0) + entry.value;
          }

          final nextStockByInvRef = <DocumentReference, double>{};
          for (final invRef in invRefSet) {
            final current = currentStockByInvRef[invRef] ?? 0.0;
            final delta = stockDeltaByInvRef[invRef] ?? 0.0;
            final next = current - delta;
            if (next < 0) {
              throw Exception('Insufficient inventory stock');
            }
            nextStockByInvRef[invRef] = next;
          }

          for (final r in menuNoInvAdjustments) {
            final menu = r['menu'] as Map<String, dynamic>;
            final quantity = r['quantity'] as int;
            final menuRef = r['menuRef'] as DocumentReference;
            final curRaw = menu['availableServings'];
            final currentServings = curRaw is num
                ? curRaw.toInt()
                : int.tryParse(curRaw?.toString() ?? '') ?? 0;
            if (currentServings < quantity) {
              throw Exception('Insufficient available servings');
            }
            final next = currentServings - quantity;
            tx.update(menuRef, {
              'availableServings': next,
              'isAvailable': next > 0,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          for (final r in invLinkReads) {
            final invRef = r['invRef'] as DocumentReference;
            final menuRef = r['menuRef'] as DocumentReference;
            final nextStock = nextStockByInvRef[invRef] ?? 0.0;
            tx.update(invRef, {
              'currentStock': nextStock,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            tx.update(menuRef, {
              'availableServings': nextStock,
              'isAvailable': nextStock > 0,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          for (final r in drinkFallbackReads) {
            final invRef = r['invRef'] as DocumentReference;
            final menuRef = r['menuRef'] as DocumentReference;
            final nextStock = nextStockByInvRef[invRef] ?? 0.0;
            tx.update(invRef, {
              'currentStock': nextStock,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            tx.update(menuRef, {
              'inventoryItemId': invRef.id,
              'availableServings': nextStock,
              'isAvailable': nextStock > 0,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          for (final entry in requiredByInvRef.entries) {
            final invRef = entry.key;
            final nextStock = nextStockByInvRef[invRef] ?? 0.0;
            tx.update(invRef, {
              'currentStock': nextStock,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          tx.set(
              orderRef,
              {
                'status': 'completed',
                'completedAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));

          return {'ok': true, 'status': 'completed'};
        }),
      );

      return result;
    } on FirebaseException catch (e) {
      final msg = _extractErrorDetails(e);
      try {
        await _requireAdmin();
        if (eateryId.trim().isEmpty) {
          eateryId = await _requireCurrentEateryId();
        }
        final orderRef =
            _eaterySubcollection(eateryId, ordersCollection).doc(orderId);
        await orderRef.set({
          'rejectReason': msg,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
      throw Exception(msg);
    } catch (e) {
      final msg = _extractErrorDetails(e);
      try {
        await _requireAdmin();
        if (eateryId.trim().isEmpty) {
          eateryId = await _requireCurrentEateryId();
        }
        final orderRef =
            _eaterySubcollection(eateryId, ordersCollection).doc(orderId);
        await orderRef.set({
          'rejectReason': msg,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}

      throw Exception(msg);
    }
  }

  static Future<void> restoreOrderToPending(String orderId) async {
    try {
      await _requireAdmin();
      final eateryId = await _requireCurrentEateryId();
      final orderRef =
          _eaterySubcollection(eateryId, ordersCollection).doc(orderId);
      final snap = await orderRef.get();
      if (!snap.exists) {
        throw Exception('Order not found');
      }
      await orderRef.set({
        'status': 'pending',
        'rejectReason': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to restore order: $e');
    }
  }

  static Future<void> voidOrder(
    String orderId, {
    String reason = '',
  }) async {
    try {
      await _requireAdmin();
      final eateryId = await _requireCurrentEateryId();
      final orderRef =
          _eaterySubcollection(eateryId, ordersCollection).doc(orderId);
      final snap = await orderRef.get();
      if (!snap.exists) {
        throw Exception('Order not found');
      }
      final data = snap.data() ?? <String, dynamic>{};

      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'pending') {
        throw Exception('Only pending orders can be voided');
      }

      final uid = _auth.currentUser?.uid ?? '';
      await orderRef.set({
        'status': 'voided',
        'voidReason': reason.trim(),
        'voidedAt': FieldValue.serverTimestamp(),
        'voidedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to void order: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getOrders({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final querySnapshot = await _withRetry(
        () => _eaterySubcollection(eateryId, ordersCollection).get(),
      );

      final orders = querySnapshot.docs.map((doc) {
        final Map<String, dynamic> result = {'id': doc.id};
        result.addAll(doc.data());
        return result;
      }).toList();

      DateTime? parseCreatedAt(dynamic createdAt) {
        if (createdAt is Timestamp) return createdAt.toDate();
        if (createdAt is DateTime) return createdAt;
        return DateTime.tryParse(createdAt?.toString() ?? '');
      }

      final filtered = orders.where((o) {
        final created = parseCreatedAt(o['createdAt']);
        if (created == null) return true;
        if (startDate != null && created.isBefore(startDate)) return false;
        if (endDate != null && !created.isBefore(endDate)) return false;
        return true;
      }).toList();

      filtered.sort((a, b) {
        final aDate = parseCreatedAt(a['createdAt']);
        final bDate = parseCreatedAt(b['createdAt']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      return filtered;
    } catch (e) {
      throw Exception('Failed to fetch orders: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getTodayOrders() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return getOrders(startDate: startOfDay, endDate: endOfDay);
  }

  static Stream<List<Map<String, dynamic>>> getTodayOrdersStream() async* {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final eateryId = await _requireCurrentEateryId();

    yield* _eaterySubcollection(eateryId, ordersCollection)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final Map<String, dynamic> result = {'id': doc.id};
        result.addAll(doc.data());
        return result;
      }).toList();
    });
  }

  // Inventory methods
  static Future<List<Map<String, dynamic>>> getInventoryItems({
    String? category,
  }) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final querySnapshot = await _withRetry(
        () => _eaterySubcollection(eateryId, inventoryCollection).get(),
      );

      final items = querySnapshot.docs.map((doc) {
        final Map<String, dynamic> result = {'id': doc.id};
        result.addAll(doc.data());
        return result;
      }).toList();

      final filtered = (category != null && category.isNotEmpty)
          ? items
              .where((i) => (i['category'] ?? '').toString() == category)
              .toList()
          : items;

      filtered.sort((a, b) {
        final aCreated = a['createdAt'];
        final bCreated = b['createdAt'];
        final aDate = aCreated is Timestamp
            ? aCreated.toDate()
            : aCreated is DateTime
                ? aCreated
                : DateTime.tryParse(aCreated?.toString() ?? '');
        final bDate = bCreated is Timestamp
            ? bCreated.toDate()
            : bCreated is DateTime
                ? bCreated
                : DateTime.tryParse(bCreated?.toString() ?? '');
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      return filtered;
    } catch (e) {
      throw Exception('Failed to fetch inventory items: $e');
    }
  }

  static Future<Map<String, dynamic>> createInventoryItem(
    Map<String, dynamic> inventoryData,
  ) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final docRef =
          await _eaterySubcollection(eateryId, inventoryCollection).add({
        ...inventoryData,
        'eateryId': eateryId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final docSnapshot = await docRef.get();
      return {
        'id': docRef.id,
        ...docSnapshot.data()!,
      };
    } catch (e) {
      throw Exception('Failed to create inventory item: $e');
    }
  }

  static Future<Map<String, dynamic>> updateInventoryItem(
    String id,
    Map<String, dynamic> updates,
  ) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final existing = await _eaterySubcollection(eateryId, inventoryCollection)
          .doc(id)
          .get();
      if (!existing.exists) {
        throw Exception('Inventory item not found');
      }
      final existingEateryId =
          (existing.data()?['eateryId'] ?? '').toString().trim();
      if (existingEateryId.isNotEmpty && existingEateryId != eateryId) {
        throw Exception('Access denied');
      }

      await _eaterySubcollection(eateryId, inventoryCollection).doc(id).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final docSnapshot =
          await _eaterySubcollection(eateryId, inventoryCollection)
              .doc(id)
              .get();
      return {
        'id': docSnapshot.id,
        ...docSnapshot.data()!,
      };
    } catch (e) {
      throw Exception('Failed to update inventory item: $e');
    }
  }

  static Future<void> deleteInventoryItem(String id) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final existing = await _eaterySubcollection(eateryId, inventoryCollection)
          .doc(id)
          .get();
      if (!existing.exists) {
        return;
      }
      final existingEateryId =
          (existing.data()?['eateryId'] ?? '').toString().trim();
      if (existingEateryId.isNotEmpty && existingEateryId != eateryId) {
        throw Exception('Access denied');
      }
      await _eaterySubcollection(eateryId, inventoryCollection)
          .doc(id)
          .delete();
    } catch (e) {
      throw Exception('Failed to delete inventory item: $e');
    }
  }

  static Future<Map<String, dynamic>> updateInventoryStock(
    String id,
    double quantity,
    String operation,
  ) async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final docRef =
          _eaterySubcollection(eateryId, inventoryCollection).doc(id);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        throw Exception('Inventory item not found');
      }

      final existingEateryId =
          (docSnapshot.data()?['eateryId'] ?? '').toString().trim();
      if (existingEateryId.isNotEmpty && existingEateryId != eateryId) {
        throw Exception('Access denied');
      }

      final currentStock =
          (docSnapshot.data()!['currentStock'] as num).toDouble();
      double newStock;

      switch (operation) {
        case 'add':
          newStock = currentStock + quantity;
          break;
        case 'subtract':
          newStock = currentStock - quantity;
          break;
        case 'set':
        default:
          newStock = quantity;
          break;
      }

      await docRef.update({
        'currentStock': newStock,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final updatedSnapshot = await docRef.get();
      return {
        'id': updatedSnapshot.id,
        ...updatedSnapshot.data()!,
      };
    } catch (e) {
      throw Exception('Failed to update stock: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getLowStockItems() async {
    try {
      // Since Firestore doesn't support field comparisons with other fields directly,
      // we'll filter client-side
      final allItems = await getInventoryItems();
      return allItems.where((item) {
        final currentStock = (item['currentStock'] as num?)?.toDouble() ?? 0;
        final minStock = (item['minStock'] as num?)?.toDouble() ?? 0;
        return currentStock <= minStock;
      }).toList();
    } catch (e) {
      throw Exception('Failed to fetch low stock items: $e');
    }
  }

  // Analytics methods
  static Future<Map<String, dynamic>> getDailySalesAnalytics({
    int days = 30,
  }) async {
    try {
      final endDate = DateTime.now();
      final startDate = endDate.subtract(Duration(days: days));

      final orders = await getOrders(startDate: startDate, endDate: endDate);

      // Group by date and calculate metrics
      final dailyData = <String, Map<String, dynamic>>{};

      for (final order in orders) {
        final status = (order['status'] ?? '').toString().toLowerCase();
        if (status != 'completed') continue;

        final completedAt = order['completedAt'];
        final date = completedAt is Timestamp
            ? completedAt.toDate()
            : completedAt is DateTime
                ? completedAt
                : DateTime.tryParse(completedAt?.toString() ?? '') ?? endDate;
        final dateKey = '${date.year}-${date.month}-${date.day}';

        if (!dailyData.containsKey(dateKey)) {
          dailyData[dateKey] = {
            'date': dateKey,
            'orders': 0,
            'revenue': 0.0,
          };
        }

        dailyData[dateKey]!['orders'] = dailyData[dateKey]!['orders'] + 1;
        dailyData[dateKey]!['revenue'] =
            (dailyData[dateKey]!['revenue'] as double) +
                ((order['totalAmount'] as num?)?.toDouble() ?? 0.0);
      }

      return {
        'dailySales': dailyData.values.toList()
          ..sort((a, b) => b['date'].compareTo(a['date'])),
      };
    } catch (e) {
      throw Exception('Failed to fetch daily sales analytics: $e');
    }
  }

  static Future<Map<String, dynamic>> getItemPerformance() async {
    try {
      final itemStats = <String, Map<String, dynamic>>{};

      final orders = await getOrders();

      for (final order in orders) {
        final status = (order['status'] ?? '').toString().toLowerCase();
        if (status != 'completed') continue;
        final items = order['items'] as List<dynamic>? ?? [];

        for (final item in items) {
          final itemId = item['id'] as String?;
          final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
          final price = (item['price'] as num?)?.toDouble() ?? 0.0;

          if (itemId != null) {
            if (!itemStats.containsKey(itemId)) {
              itemStats[itemId] = {
                'id': itemId,
                'name': item['name'] ?? 'Unknown',
                'quantitySold': 0,
                'revenue': 0.0,
              };
            }

            itemStats[itemId]!['quantitySold'] =
                itemStats[itemId]!['quantitySold'] + quantity;
            itemStats[itemId]!['revenue'] =
                itemStats[itemId]!['revenue'] + (price * quantity);
          }
        }
      }

      return {
        'items': itemStats.values.toList()
          ..sort((a, b) =>
              (b['revenue'] as double).compareTo(a['revenue'] as double)),
      };
    } catch (e) {
      throw Exception('Failed to fetch item performance: $e');
    }
  }

  static Future<Map<String, dynamic>> getSummaryStats() async {
    try {
      final eateryId = await _requireCurrentEateryId();
      final orders = await getOrders();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(const Duration(days: 7));
      final monthStart = DateTime(now.year, now.month, 1);

      DateTime? parseCompletedAt(dynamic completedAt) {
        if (completedAt is Timestamp) return completedAt.toDate();
        if (completedAt is DateTime) return completedAt;
        return DateTime.tryParse(completedAt?.toString() ?? '');
      }

      final completedOnly = orders.where((o) {
        final status = (o['status'] ?? '').toString().trim().toLowerCase();
        return status == 'completed';
      }).toList();

      final todayOrders = completedOnly.where((o) {
        final completed = parseCompletedAt(o['completedAt']);
        return completed == null ? false : !completed.isBefore(todayStart);
      }).toList();

      final weekOrders = completedOnly.where((o) {
        final completed = parseCompletedAt(o['completedAt']);
        return completed == null ? false : !completed.isBefore(weekStart);
      }).toList();

      final monthOrders = completedOnly.where((o) {
        final completed = parseCompletedAt(o['completedAt']);
        return completed == null ? false : !completed.isBefore(monthStart);
      }).toList();

      final calculateStats = (List<Map<String, dynamic>> list) {
        int orders = 0;
        double revenue = 0.0;
        for (final data in list) {
          orders++;
          revenue += (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
        }
        return {'orders': orders, 'revenue': revenue};
      };

      final menuCount = await _withRetry(
        () => _eaterySubcollection(eateryId, menuCollection).count().get(),
      );

      return {
        'today': calculateStats(todayOrders),
        'week': calculateStats(weekOrders),
        'month': calculateStats(monthOrders),
        'menuItems': menuCount.count,
      };
    } catch (e) {
      throw Exception('Failed to fetch summary stats: $e');
    }
  }

  // User methods
  static Future<Map<String, dynamic>> createUserProfile(
    String uid,
    Map<String, dynamic> userData,
  ) async {
    try {
      await _firestore.collection(usersCollection).doc(uid).set({
        ...userData,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final docSnapshot =
          await _firestore.collection(usersCollection).doc(uid).get();
      return {
        'id': docSnapshot.id,
        ...docSnapshot.data()!,
      };
    } catch (e) {
      throw Exception('Failed to create user profile: $e');
    }
  }

  static Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final docSnapshot =
          await _firestore.collection(usersCollection).doc(uid).get();

      if (docSnapshot.exists) {
        return {
          'id': docSnapshot.id,
          ...docSnapshot.data()!,
        };
      }
      return null;
    } catch (e) {
      throw Exception('Failed to fetch user profile: $e');
    }
  }

  // Mock data for testing - made public for ApiService
  static Map<String, dynamic> mockDemandForecast(int days) {
    final List<Map<String, dynamic>> forecast = [];
    for (int i = 1; i <= days; i++) {
      forecast.add({
        'day': i,
        'predictedDemand': 20 + (i * 3),
        'confidence': 0.85,
      });
    }
    return {'data': forecast, 'note': 'Mock data'};
  }

  static Map<String, dynamic> mockSalesForecast(int days) {
    final List<Map<String, dynamic>> forecast = [];
    for (int i = 1; i <= days; i++) {
      forecast.add({
        'day': i,
        'predictedSales': 2000 + (i * 100),
        'confidence': 0.82,
      });
    }
    return {'data': forecast, 'note': 'Mock data'};
  }

  static Map<String, dynamic> mockRecommendations() {
    return {
      'data': {
        'promoteItems': [
          {
            'id': '1',
            'name': 'Burger Special',
            'reason': 'High profit potential',
            'expectedIncrease': '25%'
          },
          {
            'id': '2',
            'name': 'Fried Rice',
            'reason': 'Strong customer demand',
            'expectedIncrease': '18%'
          },
        ],
        'removeItems': [
          {
            'id': '5',
            'name': 'Rare Dish',
            'reason': 'Low sales',
            'wasteReduction': '40%'
          },
        ],
        'optimizeInventory': [
          {
            'ingredient': 'Tomatoes',
            'action': 'Reduce order by 20%',
            'reason': 'Excess stock'
          },
          {
            'ingredient': 'Chicken',
            'action': 'Increase order by 15%',
            'reason': 'High demand'
          },
        ],
      },
      'note': 'Mock data'
    };
  }

  // Staff meal methods
  static Future<Map<String, dynamic>> createStaffMealOrder(
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final eateryId = data['eateryId']?.toString();
    if (eateryId == null || eateryId.isEmpty) {
      throw Exception('Eatery ID is required');
    }

    final orderData = {
      ...data,
      'createdAt': data['createdAt'] ?? DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };

    // Store in eatery subcollection for proper data organization
    final docRef = await _eaterySubcollection(eateryId, staffMealsCollection)
        .add(orderData);

    return {
      'id': docRef.id,
      ...orderData,
    };
  }

  static Future<List<Map<String, dynamic>>> getStaffMealOrders({
    String? eateryId,
    String? staffId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (eateryId == null || eateryId.isEmpty) {
      return [];
    }

    Query<Map<String, dynamic>> query =
        _eaterySubcollection(eateryId, staffMealsCollection);

    if (staffId != null && staffId.isNotEmpty) {
      query = query.where('staffId', isEqualTo: staffId);
    }

    if (startDate != null) {
      query = query.where('createdAt',
          isGreaterThanOrEqualTo: startDate.toIso8601String());
    }

    if (endDate != null) {
      query = query.where('createdAt',
          isLessThanOrEqualTo: endDate.toIso8601String());
    }

    query = query.orderBy('createdAt', descending: true);

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  static Future<void> updateStaffMealOrderStatus(
    String id, {
    required String status,
    String? eateryId,
  }) async {
    if (eateryId == null || eateryId.isEmpty) {
      throw Exception('Eatery ID is required');
    }

    await _eaterySubcollection(eateryId, staffMealsCollection).doc(id).update({
      'status': status,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }
}
