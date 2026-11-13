import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';

/// Single source of truth for all business KPIs.
///
/// QUERY STRATEGY (matches the Dashboard exactly):
///   • Always query by [createdAt] range only — no composite status filter.
///   • Filter by status CLIENT-SIDE after fetching.
///   • This avoids missing Firestore composite indexes and guarantees that
///     AnalyticsService and FirebaseService.getSummaryStats() produce the
///     same numbers.
///
/// The AI NEVER queries Firestore — it reads the data this service produces.
class AnalyticsService {
  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // ── Internal helpers ───────────────────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> _col(
          String eateryId, String subcollection) =>
      _fs
          .collection(FirebaseService.eateriesCollection)
          .doc(eateryId)
          .collection(subcollection);

  /// Start-of-day (midnight) for [d] in local time.
  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _dayName(int weekday) {
    const n = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return n[(weekday - 1).clamp(0, 6)];
  }

  static String _monthName(int month) {
    const n = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return n[(month - 1).clamp(0, 11)];
  }

  /// Parse a Firestore timestamp field (Timestamp, DateTime, or String) into
  /// a local [DateTime]. Returns null if unparseable.
  static DateTime? _parseTs(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  /// Whether an order counts as "completed" for revenue purposes.
  static bool _isCompleted(Map<String, dynamic> d) =>
      (d['status'] ?? '').toString().trim().toLowerCase() == 'completed';

  // ══════════════════════════════════════════════════════════════════════════
  // MASTER ANALYTICS FUNCTION
  // Both the Dashboard AND the AI pull from this single function.
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetches every KPI the dashboard and AI need in a single Firestore batch.
  ///
  /// Uses the same query pattern as [FirebaseService.getSummaryStats()]:
  ///   • One query per date window (today, yesterday, week, month) on
  ///     [createdAt] only — no composite status filter.
  ///   • Status filtering is done client-side.
  ///
  /// Returns a [DashboardModel] that is the authoritative source for:
  ///   • Dashboard KPI cards (Today's Sales, Orders Today, Low Stock, etc.)
  ///   • SmartSnapshotBuilder (AI context)
  ///   • BusinessContextBuilder (panel summary metrics)
  static Future<List<Map<String, dynamic>>> _fetchCombinedDocs(
      String eateryId, String collectionName) async {
    final Map<String, Map<String, dynamic>> combined = {};

    // Fetched independently: the top-level collection is read-denied for some
    // collections (e.g. `menu` is `if false` in firestore.rules), and a single
    // shared try/catch would discard the subcollection data that already loaded.
    try {
      final subSnap = await _fs
          .collection(FirebaseService.eateriesCollection)
          .doc(eateryId)
          .collection(collectionName)
          .get();
      for (final doc in subSnap.docs) {
        combined[doc.id] = {'id': doc.id, ...doc.data()};
      }
    } catch (e) {
      debugPrint('Error fetching subcollection $collectionName: $e');
    }

    // Legacy top-level records awaiting migration.
    try {
      final topSnap = await _fs
          .collection(collectionName)
          .where('eateryId', isEqualTo: eateryId)
          .get();
      for (final doc in topSnap.docs) {
        combined[doc.id] = {'id': doc.id, ...doc.data()};
      }
    } catch (e) {
      debugPrint('Error fetching top-level $collectionName: $e');
    }

    return combined.values.toList();
  }

  // Concurrent callers for the same eatery share one build. A single dashboard
  // load / AI context build fans out into ~12 KPI helpers that all call this,
  // each costing 7 Firestore reads — de-duplicating collapses that to one.
  static Future<DashboardModel>? _modelInFlight;
  static String? _modelInFlightKey;

  /// Master analytics fetcher used by Dashboard and AI.
  static Future<DashboardModel> getDashboardModel(String eateryId) {
    final inFlight = _modelInFlight;
    if (inFlight != null && _modelInFlightKey == eateryId) {
      return inFlight;
    }
    final future = _computeDashboardModel(eateryId);
    _modelInFlight = future;
    _modelInFlightKey = eateryId;
    return future.whenComplete(() {
      if (identical(_modelInFlight, future)) {
        _modelInFlight = null;
        _modelInFlightKey = null;
      }
    });
  }

  static Future<DashboardModel> _computeDashboardModel(String eateryId) async {
    final now = DateTime.now();
    final todayStart     = _startOfDay(now);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart      = todayStart.subtract(const Duration(days: 7));
    final monthStart     = DateTime(now.year, now.month, 1);
    final last30Start    = todayStart.subtract(const Duration(days: 30));

    // Single-field queries (createdAt only) — no composite index needed.
    final orderSnaps = await Future.wait([
      // 0 — today's orders (all statuses)
      _col(eateryId, FirebaseService.ordersCollection)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .get(),
      // 1 — yesterday's orders (all statuses)
      _col(eateryId, FirebaseService.ordersCollection)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(yesterdayStart))
          .where('createdAt', isLessThan: Timestamp.fromDate(todayStart))
          .get(),
      // 2 — last 7 days (all statuses)
      _col(eateryId, FirebaseService.ordersCollection)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
          .get(),
      // 3 — this month (all statuses)
      _col(eateryId, FirebaseService.ordersCollection)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .get(),
      // 4 — last 30 days (for best sellers / menu)
      _col(eateryId, FirebaseService.ordersCollection)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(last30Start))
          .get(),
    ]);

    final invDocs  = await _fetchCombinedDocs(eateryId, FirebaseService.inventoryCollection);
    final menuDocs = await _fetchCombinedDocs(eateryId, FirebaseService.menuCollection);

    final todayDocs   = orderSnaps[0].docs.map((d) => {'id': d.id, ...d.data()}).toList();
    final yestDocs    = orderSnaps[1].docs.map((d) => {'id': d.id, ...d.data()}).toList();
    final weekDocs    = orderSnaps[2].docs.map((d) => {'id': d.id, ...d.data()}).toList();
    final monthDocs   = orderSnaps[3].docs.map((d) => {'id': d.id, ...d.data()}).toList();
    final last30Docs  = orderSnaps[4].docs.map((d) => {'id': d.id, ...d.data()}).toList();

    return DashboardModel._compute(
      eateryId: eateryId,
      todayDocs:  todayDocs,
      yestDocs:   yestDocs,
      weekDocs:   weekDocs,
      monthDocs:  monthDocs,
      last30Docs: last30Docs,
      invDocs:    invDocs,
      menuDocs:   menuDocs,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INDIVIDUAL KPI FUNCTIONS  (kept for backwards compat with BusinessContext)
  // All delegate to getDashboardModel() so values are always consistent.
  // ══════════════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> getRevenueSummary(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      final dayChange = m.yesterdayRevenue == 0
          ? (m.todayRevenue > 0 ? 100.0 : 0.0)
          : ((m.todayRevenue - m.yesterdayRevenue) / m.yesterdayRevenue) * 100;
      return {
        'todayRevenue':     m.todayRevenue,
        'yesterdayRevenue': m.yesterdayRevenue,
        'weekRevenue':      m.weekRevenue,
        'monthRevenue':     m.monthRevenue,
        'dayChangePercent': double.parse(dayChange.toStringAsFixed(1)),
        'todayOrderCount':  m.todayCompletedCount,
        'weekOrderCount':   m.weekCompletedCount,
        'monthOrderCount':  m.monthCompletedCount,
      };
    } catch (e) {
      debugPrint('getRevenueSummary error: $e');
      return {};
    }
  }

  static Future<Map<String, dynamic>> getTodayBestSeller(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      return {
        'bestSeller': m.todayBestSellerName,
        'quantity':   m.todayBestSellerQty,
      };
    } catch (e) {
      debugPrint('getTodayBestSeller error: $e');
      return {'bestSeller': 'None', 'quantity': 0};
    }
  }

  static Future<Map<String, dynamic>> getOverallBestSeller(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      return {
        'bestSeller': m.overallBestSellerName,
        'quantity':   m.overallBestSellerQty,
        'revenue':    m.overallBestSellerRevenue,
        'topFive':    m.topFiveItems,
      };
    } catch (e) {
      debugPrint('getOverallBestSeller error: $e');
      return {'bestSeller': 'None', 'quantity': 0};
    }
  }

  static Future<Map<String, dynamic>> getSalesSummary(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      return {
        'todayItemCounts':    m.todayItemCounts,
        'weekItemCounts':     m.weekItemCounts,
        'todayTotalItemsSold': m.todayTotalItemsSold,
        'weekTotalItemsSold': m.weekTotalItemsSold,
      };
    } catch (e) {
      debugPrint('getSalesSummary error: $e');
      return {};
    }
  }

  static Future<Map<String, dynamic>> getWorstSellingItems(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      return {
        'worstItems':     m.worstItems,
        'zeroSalesCount': m.zeroSalesItemCount,
      };
    } catch (e) {
      debugPrint('getWorstSellingItems error: $e');
      return {'worstItems': [], 'zeroSalesCount': 0};
    }
  }

  static Future<Map<String, dynamic>> getInventorySummary(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      return {
        'totalItems':          m.totalInventoryItems,
        'healthyCount':        m.healthyStockCount,
        'lowStockCount':       m.lowStockCount,
        'criticalCount':       m.criticalStockCount,
        'totalInventoryValue': m.totalInventoryValue,
      };
    } catch (e) {
      debugPrint('getInventorySummary error: $e');
      return {};
    }
  }

  static Future<Map<String, dynamic>> getLowStockItems(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      return {'lowStockItems': m.lowStockItems, 'count': m.lowStockCount};
    } catch (e) {
      debugPrint('getLowStockItems error: $e');
      return {'lowStockItems': [], 'count': 0};
    }
  }

  static Future<Map<String, dynamic>> getPendingOrders(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      return {
        'count':             m.pendingOrderCount,
        'totalPendingValue': m.pendingOrderValue,
      };
    } catch (e) {
      debugPrint('getPendingOrders error: $e');
      return {'count': 0, 'totalPendingValue': 0.0};
    }
  }

  static Future<Map<String, dynamic>> getCancelledOrders(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      final rate = m.weekTotalOrders == 0
          ? 0.0
          : (m.weekCancelledCount / m.weekTotalOrders) * 100;
      return {
        'cancelledLast7Days':       m.weekCancelledCount,
        'totalLast7Days':           m.weekTotalOrders,
        'cancellationRatePercent':  double.parse(rate.toStringAsFixed(1)),
      };
    } catch (e) {
      debugPrint('getCancelledOrders error: $e');
      return {'cancelledLast7Days': 0, 'cancellationRatePercent': 0.0};
    }
  }

  static Future<Map<String, dynamic>> getAverageOrderValue(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      return {
        'averageOrderValue': m.averageOrderValue,
        'sampleSize':        m.monthCompletedCount,
        'totalRevenue':      m.monthRevenue,
      };
    } catch (e) {
      debugPrint('getAverageOrderValue error: $e');
      return {'averageOrderValue': 0.0, 'sampleSize': 0};
    }
  }

  static Future<Map<String, dynamic>> getMenuPerformance(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      return {
        'items':           m.menuPerformance,
        'totalMenuItems':  m.totalMenuItems,
        'itemsWithNoSales': m.menuItemsWithNoSales,
      };
    } catch (e) {
      debugPrint('getMenuPerformance error: $e');
      return {'items': [], 'totalMenuItems': 0};
    }
  }

  static Future<Map<String, dynamic>> getCategoryPerformance(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      return {
        'categoryBreakdown': m.categoryBreakdown,
        'topCategory':       m.topCategory,
      };
    } catch (e) {
      debugPrint('getCategoryPerformance error: $e');
      return {'categoryBreakdown': [], 'topCategory': 'N/A'};
    }
  }

  // ── Standalone queries (don't need DashboardModel data) ───────────────

  static Future<Map<String, dynamic>> getExpiringIngredients(
      String eateryId, {int withinDays = 5}) async {
    try {
      final cutoff = DateTime.now().add(Duration(days: withinDays));
      final snap = await _col(eateryId, FirebaseService.inventoryCollection).get();
      final expiring = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final expField = d['expirationDate'] ?? d['expiry'];
        if (expField == null) continue;
        DateTime? expDate;
        if (expField is Timestamp) {
          expDate = expField.toDate();
        } else if (expField is String) {
          expDate = DateTime.tryParse(expField);
        }
        if (expDate != null && expDate.isBefore(cutoff)) {
          expiring.add({
            'name':            (d['name'] ?? '').toString(),
            'expirationDate':  expDate.toIso8601String().split('T')[0],
            'daysUntilExpiry': expDate.difference(DateTime.now()).inDays,
            'currentStock':    (d['currentStock'] as num?)?.toDouble() ?? 0.0,
            'unit':            (d['unit'] ?? '').toString(),
          });
        }
      }
      expiring.sort((a, b) =>
          (a['daysUntilExpiry'] as int).compareTo(b['daysUntilExpiry'] as int));
      return {'expiringItems': expiring, 'count': expiring.length};
    } catch (e) {
      debugPrint('getExpiringIngredients error: $e');
      return {'expiringItems': [], 'count': 0};
    }
  }

  static Future<Map<String, dynamic>> getSuggestedRestocks(String eateryId) async {
    try {
      final lowResult = await getLowStockItems(eateryId);
      final items = lowResult['lowStockItems'] as List<dynamic>? ?? [];
      final suggestions = items.map((item) {
        final deficit  = (item['deficit'] as double? ?? 0.0);
        final min      = (item['minStock'] as double? ?? 0.0);
        final suggested = deficit <= 0 ? min * 2 : deficit * 2;
        return {
          'name':             item['name'],
          'currentStock':     item['currentStock'],
          'unit':             item['unit'],
          'suggestedOrderQty': double.parse(suggested.toStringAsFixed(1)),
          'priority':         item['isCritical'] == true ? 'CRITICAL' : 'HIGH',
        };
      }).toList();
      return {'suggestions': suggestions};
    } catch (e) {
      debugPrint('getSuggestedRestocks error: $e');
      return {'suggestions': []};
    }
  }

  static Future<Map<String, dynamic>> getReturningCustomerRate(String eateryId) async {
    try {
      final since = DateTime.now().subtract(const Duration(days: 30));
      final snap = await _col(eateryId, FirebaseService.ordersCollection)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      final counts = <String, int>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        if (!_isCompleted(d)) continue;
        final key = (d['customerName'] ?? d['customerId'] ?? d['tableNumber'] ?? '')
            .toString().trim();
        if (key.isNotEmpty) counts[key] = (counts[key] ?? 0) + 1;
      }
      final returning = counts.values.where((v) => v > 1).length;
      final total = counts.length;
      final rate = total == 0 ? 0.0 : (returning / total) * 100;
      return {
        'returningCustomerRatePercent': double.parse(rate.toStringAsFixed(1)),
        'uniqueCustomers': total,
        'returningCustomers': returning,
      };
    } catch (e) {
      debugPrint('getReturningCustomerRate error: $e');
      return {'returningCustomerRatePercent': 0.0};
    }
  }

  static Future<Map<String, dynamic>> getPeakHours(String eateryId) async {
    try {
      final since = DateTime.now().subtract(const Duration(days: 14));
      final snap = await _col(eateryId, FirebaseService.ordersCollection)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      final hourCounts  = <int, int>{};
      final hourRevenue = <int, double>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        if (!_isCompleted(d)) continue;
        final dt = _parseTs(d['createdAt']);
        if (dt == null) continue;
        final h = dt.hour;
        hourCounts[h]  = (hourCounts[h] ?? 0) + 1;
        hourRevenue[h] = (hourRevenue[h] ?? 0.0)
            + ((d['totalAmount'] as num?)?.toDouble() ?? 0.0);
      }
      if (hourCounts.isEmpty) return {'peakHour': 'N/A', 'hourlyBreakdown': []};
      final sorted = hourCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      String fmt(int h) =>
          '${h == 0 ? 12 : h > 12 ? h - 12 : h}:00 ${h < 12 ? 'AM' : 'PM'}';
      return {
        'peakHour':           fmt(sorted.first.key),
        'peakHourOrderCount': sorted.first.value,
        'slowestHour':        fmt(sorted.last.key),
        'hourlyBreakdown': sorted.take(6).map((e) => {
          'hour':    fmt(e.key),
          'orders':  e.value,
          'revenue': double.parse((hourRevenue[e.key] ?? 0.0).toStringAsFixed(2)),
        }).toList(),
      };
    } catch (e) {
      debugPrint('getPeakHours error: $e');
      return {'peakHour': 'N/A', 'hourlyBreakdown': []};
    }
  }

  static Future<Map<String, dynamic>> getSalesTrend(
      String eateryId, {int days = 14}) async {
    try {
      final since = _startOfDay(DateTime.now()).subtract(Duration(days: days - 1));
      final snap  = await _col(eateryId, FirebaseService.ordersCollection)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      final daily = <String, double>{};
      for (var i = 0; i < days; i++) {
        final d = since.add(Duration(days: i));
        daily[d.toIso8601String().split('T')[0]] = 0.0;
      }
      for (final doc in snap.docs) {
        final d  = doc.data();
        if (!_isCompleted(d)) continue;
        final dt = _parseTs(d['createdAt']);
        if (dt == null) continue;
        final key = dt.toIso8601String().split('T')[0];
        daily[key] = (daily[key] ?? 0.0)
            + ((d['totalAmount'] as num?)?.toDouble() ?? 0.0);
      }
      final trendList = daily.entries
          .map((e) => {'date': e.key, 'revenue': double.parse(e.value.toStringAsFixed(2))})
          .toList();
      final mid = trendList.length ~/ 2;
      final firstHalf  = trendList.take(mid).fold(0.0, (t, e) => t + (e['revenue'] as double));
      final secondHalf = trendList.skip(mid).fold(0.0, (t, e) => t + (e['revenue'] as double));
      final trend = secondHalf > firstHalf ? 'improving'
          : secondHalf < firstHalf ? 'declining' : 'stable';
      return {
        'dailyTrend':    trendList,
        'trendDirection': trend,
        'periodDays':    days,
        'totalRevenue':  double.parse(
            daily.values.fold(0.0, (a, b) => a + b).toStringAsFixed(2)),
      };
    } catch (e) {
      debugPrint('getSalesTrend error: $e');
      return {'dailyTrend': [], 'trendDirection': 'unknown'};
    }
  }

  static Future<Map<String, dynamic>> getWeeklyTrend(String eateryId) async {
    try {
      final since = DateTime.now().subtract(const Duration(days: 28));
      final snap  = await _col(eateryId, FirebaseService.ordersCollection)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      final dayRevenue = <int, double>{for (int i = 1; i <= 7; i++) i: 0.0};
      final dayOrders  = <int, int>{for (int i = 1; i <= 7; i++) i: 0};
      for (final doc in snap.docs) {
        final d  = doc.data();
        if (!_isCompleted(d)) continue;
        final dt = _parseTs(d['createdAt']);
        if (dt == null) continue;
        dayRevenue[dt.weekday] = (dayRevenue[dt.weekday] ?? 0.0)
            + ((d['totalAmount'] as num?)?.toDouble() ?? 0.0);
        dayOrders[dt.weekday] = (dayOrders[dt.weekday] ?? 0) + 1;
      }
      final breakdown = List.generate(7, (i) {
        final wd = i + 1;
        return {
          'day':     _dayName(wd),
          'revenue': double.parse((dayRevenue[wd] ?? 0.0).toStringAsFixed(2)),
          'orders':  dayOrders[wd] ?? 0,
        };
      });
      final best = breakdown.reduce(
          (a, b) => (a['revenue'] as double) >= (b['revenue'] as double) ? a : b);
      return {
        'weeklyBreakdown': breakdown,
        'bestDay':         best['day'],
        'bestDayRevenue':  best['revenue'],
      };
    } catch (e) {
      debugPrint('getWeeklyTrend error: $e');
      return {'weeklyBreakdown': [], 'bestDay': 'N/A'};
    }
  }

  static Future<Map<String, dynamic>> getMonthlyGrowth(String eateryId) async {
    try {
      final now            = DateTime.now();
      final thisMonthStart = DateTime(now.year, now.month, 1);
      final lastMonthStart = DateTime(now.year, now.month - 1, 1);
      final snaps = await Future.wait([
        _col(eateryId, FirebaseService.ordersCollection)
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(thisMonthStart))
            .get(),
        _col(eateryId, FirebaseService.ordersCollection)
            .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(lastMonthStart))
            .where('createdAt', isLessThan: Timestamp.fromDate(thisMonthStart))
            .get(),
      ]);
      double rev(QuerySnapshot<Map<String, dynamic>> s) => s.docs
          .where((d) => _isCompleted(d.data()))
          .fold(0.0, (t, d) => t + ((d.data()['totalAmount'] as num?) ?? 0).toDouble());
      final thisRev = rev(snaps[0]);
      final lastRev = rev(snaps[1]);
      final growth  = lastRev == 0
          ? (thisRev > 0 ? 100.0 : 0.0)
          : ((thisRev - lastRev) / lastRev) * 100;
      return {
        'thisMonthRevenue':    thisRev,
        'lastMonthRevenue':    lastRev,
        'monthlyGrowthPercent': double.parse(growth.toStringAsFixed(1)),
        'thisMonthOrders':     snaps[0].docs.where((d) => _isCompleted(d.data())).length,
        'lastMonthOrders':     snaps[1].docs.where((d) => _isCompleted(d.data())).length,
        'thisMonth':           _monthName(now.month),
        'lastMonth':           _monthName(now.month == 1 ? 12 : now.month - 1),
      };
    } catch (e) {
      debugPrint('getMonthlyGrowth error: $e');
      return {};
    }
  }

  static Future<Map<String, dynamic>> getBusinessHealthScore(String eateryId) async {
    try {
      final m = await getDashboardModel(eateryId);
      final dayChange = m.yesterdayRevenue == 0
          ? (m.todayRevenue > 0 ? 100.0 : 0.0)
          : ((m.todayRevenue - m.yesterdayRevenue) / m.yesterdayRevenue) * 100;
      final cancelRate = m.weekTotalOrders == 0
          ? 0.0
          : (m.weekCancelledCount / m.weekTotalOrders) * 100;
      final revScore    = (dayChange >= 10 ? 30.0 : dayChange >= 0 ? 20.0 + dayChange : (20.0 + dayChange)).clamp(0.0, 30.0);
      final stockScore  = (25.0 - m.lowStockCount * 3.0).clamp(0.0, 25.0);
      final cancelScore = (20.0 - cancelRate * 2).clamp(0.0, 20.0);
      final menuScore   = (15.0 - m.zeroSalesItemCount.toDouble()).clamp(0.0, 15.0);
      final total       = revScore + stockScore + cancelScore + menuScore;
      final clamped     = total.clamp(0.0, 100.0);
      final label       = clamped >= 80 ? 'Excellent'
          : clamped >= 60 ? 'Good' : clamped >= 40 ? 'Fair' : 'Needs Attention';
      return {'score': double.parse(clamped.toStringAsFixed(1)), 'label': label};
    } catch (e) {
      debugPrint('getBusinessHealthScore error: $e');
      return {'score': 0.0, 'label': 'Unknown'};
    }
  }

  static Future<Map<String, dynamic>> getSalesForecast(
      String eateryId, {int forecastDays = 7}) async {
    try {
      final since = DateTime.now().subtract(const Duration(days: 56));
      final snap  = await _col(eateryId, FirebaseService.ordersCollection)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      final dayRevenues = <int, List<double>>{for (int i = 1; i <= 7; i++) i: []};
      for (final doc in snap.docs) {
        final d  = doc.data();
        if (!_isCompleted(d)) continue;
        final dt = _parseTs(d['createdAt']);
        if (dt == null) continue;
        dayRevenues[dt.weekday]!.add((d['totalAmount'] as num?)?.toDouble() ?? 0.0);
      }
      final avgs = <int, double>{};
      for (int i = 1; i <= 7; i++) {
        final list = dayRevenues[i]!;
        avgs[i] = list.isEmpty ? 0.0 : list.reduce((a, b) => a + b) / list.length;
      }
      final forecast = <Map<String, dynamic>>[];
      for (int i = 1; i <= forecastDays; i++) {
        final date = DateTime.now().add(Duration(days: i));
        forecast.add({
          'date':             date.toIso8601String().split('T')[0],
          'dayName':          _dayName(date.weekday),
          'predictedRevenue': double.parse((avgs[date.weekday] ?? 0.0).toStringAsFixed(2)),
          'isWeekend':        date.weekday == 6 || date.weekday == 7,
        });
      }
      return {'forecast': forecast, 'basisDays': 56, 'method': 'day_of_week_average'};
    } catch (e) {
      debugPrint('getSalesForecast error: $e');
      return {'forecast': []};
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════
// DashboardModel — authoritative KPI container
//
// Computed once from raw Firestore documents.
// Dashboard reads from it.  SmartSnapshotBuilder serialises it.
// No other code should compute these KPIs independently.
// ══════════════════════════════════════════════════════════════════════════
class DashboardModel {
  // ── Identity ─────────────────────────────────────────────────────────
  final String eateryId;
  final DateTime generatedAt;

  // ── Today revenue / orders ────────────────────────────────────────────
  final double todayRevenue;
  final int    todayCompletedCount;
  final int    todayPendingCount;
  final int    todayCancelledCount;
  final int    todayTotalOrders;     // all statuses (matches dashboard's "Orders Today")

  // ── Yesterday ─────────────────────────────────────────────────────────
  final double yesterdayRevenue;
  final int    yesterdayCompletedCount;

  // ── Week (last 7 days) ─────────────────────────────────────────────────
  final double weekRevenue;
  final int    weekCompletedCount;
  final int    weekCancelledCount;
  final int    weekTotalOrders;

  // ── Month ──────────────────────────────────────────────────────────────
  final double monthRevenue;
  final int    monthCompletedCount;
  final double averageOrderValue;

  // ── Best sellers — TODAY ───────────────────────────────────────────────
  final String todayBestSellerName;
  final int    todayBestSellerQty;
  final double todayBestSellerRevenue;
  final double todayBestSellerPct;    // % of today's total items sold
  /// Full ranked list: {name, qty, revenue, pct}
  final List<Map<String, dynamic>> todayTopItems;

  // ── Item counts ────────────────────────────────────────────────────────
  final Map<String, int> todayItemCounts;
  final int              todayTotalItemsSold;
  final Map<String, int> weekItemCounts;
  final int              weekTotalItemsSold;

  // ── Best sellers — OVERALL (last 30 days) ─────────────────────────────
  final String overallBestSellerName;
  final int    overallBestSellerQty;
  final double overallBestSellerRevenue;
  final List<Map<String, dynamic>> topFiveItems;    // {name, qty, revenue}

  // ── Worst sellers ─────────────────────────────────────────────────────
  final List<Map<String, dynamic>> worstItems;     // {name, soldLast30Days}
  final int zeroSalesItemCount;

  // ── Menu ──────────────────────────────────────────────────────────────
  final int totalMenuItems;
  final int menuItemsWithNoSales;
  final List<Map<String, dynamic>> menuPerformance;  // {name, category, price, soldLast30Days, revenueLast30Days, status}
  final String topCategory;
  final List<Map<String, dynamic>> categoryBreakdown;

  // ── Inventory ─────────────────────────────────────────────────────────
  final int    totalInventoryItems;
  final int    healthyStockCount;
  final int    lowStockCount;
  final int    criticalStockCount;
  final double totalInventoryValue;
  final List<Map<String, dynamic>> lowStockItems;   // {name, currentStock, minStock, unit, isCritical, deficit}

  // ── Pending / voided ──────────────────────────────────────────────────
  final int    pendingOrderCount;
  final double pendingOrderValue;

  const DashboardModel._({
    required this.eateryId,
    required this.generatedAt,
    required this.todayRevenue,
    required this.todayCompletedCount,
    required this.todayPendingCount,
    required this.todayCancelledCount,
    required this.todayTotalOrders,
    required this.yesterdayRevenue,
    required this.yesterdayCompletedCount,
    required this.weekRevenue,
    required this.weekCompletedCount,
    required this.weekCancelledCount,
    required this.weekTotalOrders,
    required this.monthRevenue,
    required this.monthCompletedCount,
    required this.averageOrderValue,
    required this.todayBestSellerName,
    required this.todayBestSellerQty,
    required this.todayBestSellerRevenue,
    required this.todayBestSellerPct,
    required this.todayTopItems,
    required this.todayItemCounts,
    required this.todayTotalItemsSold,
    required this.weekItemCounts,
    required this.weekTotalItemsSold,
    required this.overallBestSellerName,
    required this.overallBestSellerQty,
    required this.overallBestSellerRevenue,
    required this.topFiveItems,
    required this.worstItems,
    required this.zeroSalesItemCount,
    required this.totalMenuItems,
    required this.menuItemsWithNoSales,
    required this.menuPerformance,
    required this.topCategory,
    required this.categoryBreakdown,
    required this.totalInventoryItems,
    required this.healthyStockCount,
    required this.lowStockCount,
    required this.criticalStockCount,
    required this.totalInventoryValue,
    required this.lowStockItems,
    required this.pendingOrderCount,
    required this.pendingOrderValue,
  });

  // ── Derived helpers ────────────────────────────────────────────────────

  double get dayChangePercent {
    if (yesterdayRevenue == 0) return todayRevenue > 0 ? 100.0 : 0.0;
    return ((todayRevenue - yesterdayRevenue) / yesterdayRevenue) * 100;
  }

  double get cancellationRatePercent {
    if (weekTotalOrders == 0) return 0.0;
    return (weekCancelledCount / weekTotalOrders) * 100;
  }

  // ── Factory ────────────────────────────────────────────────────────────

  factory DashboardModel._compute({
    required String eateryId,
    required List<Map<String, dynamic>> todayDocs,
    required List<Map<String, dynamic>> yestDocs,
    required List<Map<String, dynamic>> weekDocs,
    required List<Map<String, dynamic>> monthDocs,
    required List<Map<String, dynamic>> last30Docs,
    required List<Map<String, dynamic>> invDocs,
    required List<Map<String, dynamic>> menuDocs,
  }) {
    // ── helpers ────────────────────────────────────────────────────────
    bool isCompleted(Map d) =>
        (d['status'] ?? '').toString().trim().toLowerCase() == 'completed';
    bool isVoided(Map d) {
      final s = (d['status'] ?? '').toString().trim().toLowerCase();
      return s == 'voided' || s == 'cancelled';
    }
    bool isPending(Map d) =>
        (d['status'] ?? '').toString().trim().toLowerCase() == 'pending';

    double sumRevenue(List<Map<String, dynamic>> docs) => docs
        .where(isCompleted)
        .fold(0.0, (t, d) => t + ((d['totalAmount'] as num?)?.toDouble() ?? 0.0));

    // ── Today ──────────────────────────────────────────────────────────
    final todayRevenue         = sumRevenue(todayDocs);
    final todayCompletedCount  = todayDocs.where(isCompleted).length;
    final todayPendingCount    = todayDocs.where(isPending).length;
    final todayCancelledCount  = todayDocs.where(isVoided).length;
    final todayTotalOrders     = todayDocs.length;

    // ── Yesterday ──────────────────────────────────────────────────────
    final yesterdayRevenue        = sumRevenue(yestDocs);
    final yesterdayCompletedCount = yestDocs.where(isCompleted).length;

    // ── Week ──────────────────────────────────────────────────────────
    final weekRevenue       = sumRevenue(weekDocs);
    final weekCompletedCount = weekDocs.where(isCompleted).length;
    final weekCancelledCount = weekDocs.where(isVoided).length;
    final weekTotalOrders    = weekDocs.length;

    // ── Month ─────────────────────────────────────────────────────────
    final monthRevenue        = sumRevenue(monthDocs);
    final monthCompletedCount = monthDocs.where(isCompleted).length;
    final aov = monthCompletedCount == 0
        ? 0.0
        : monthRevenue / monthCompletedCount;

    // ── Pending ───────────────────────────────────────────────────────
    // Count pending across ALL today's docs (not just completed)
    final pendingDocs = todayDocs.where(isPending).toList();
    final pendingOrderCount = pendingDocs.length;
    final pendingOrderValue = pendingDocs.fold(
        0.0, (t, d) => t + ((d['totalAmount'] as num?)?.toDouble() ?? 0.0));

    // ── Today item tallies ─────────────────────────────────────────────
    // Count items from ALL today's orders (all statuses — matches dashboard)
    final todayItemCounts  = <String, int>{};
    final todayItemRevenue = <String, double>{};
    for (final d in todayDocs) {
      for (final raw in (d['items'] as List? ?? [])) {
        if (raw is! Map) continue;
        final name  = (raw['name'] ?? 'Unknown').toString();
        final qty   = (raw['quantity'] as num?)?.toInt() ?? 1;
        final price = (raw['price'] as num?)?.toDouble() ?? 0.0;
        todayItemCounts[name]  = (todayItemCounts[name] ?? 0) + qty;
        todayItemRevenue[name] = (todayItemRevenue[name] ?? 0.0) + price * qty;
      }
    }
    final todayTotalItemsSold =
        todayItemCounts.values.fold(0, (a, b) => a + b);

    // Today top items ranked by qty
    final todayRanked = todayItemCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final todayTopItems = todayRanked.map((e) {
      final pct = todayTotalItemsSold == 0
          ? 0.0
          : (e.value / todayTotalItemsSold) * 100;
      return {
        'name':    e.key,
        'qty':     e.value,
        'revenue': todayItemRevenue[e.key] ?? 0.0,
        'pct':     double.parse(pct.toStringAsFixed(1)),
      };
    }).toList();

    final todayBestSellerName    = todayRanked.isEmpty ? 'None' : todayRanked.first.key;
    final todayBestSellerQty     = todayRanked.isEmpty ? 0 : todayRanked.first.value;
    final todayBestSellerRevenue = todayItemRevenue[todayBestSellerName] ?? 0.0;
    final todayBestSellerPct     = todayTotalItemsSold == 0
        ? 0.0
        : double.parse((todayBestSellerQty / todayTotalItemsSold * 100)
            .toStringAsFixed(1));

    // ── Week item tallies ──────────────────────────────────────────────
    final weekItemCounts = <String, int>{};
    for (final d in weekDocs) {
      if (!isCompleted(d)) continue;
      for (final raw in (d['items'] as List? ?? [])) {
        if (raw is! Map) continue;
        final name = (raw['name'] ?? 'Unknown').toString();
        final qty  = (raw['quantity'] as num?)?.toInt() ?? 1;
        weekItemCounts[name] = (weekItemCounts[name] ?? 0) + qty;
      }
    }
    final weekTotalItemsSold = weekItemCounts.values.fold(0, (a, b) => a + b);

    // ── Overall best seller (last 30 days) ─────────────────────────────
    final overallCounts  = <String, int>{};
    final overallRevenue = <String, double>{};
    for (final d in last30Docs) {
      if (!isCompleted(d)) continue;
      for (final raw in (d['items'] as List? ?? [])) {
        if (raw is! Map) continue;
        final name  = (raw['name'] ?? 'Unknown').toString();
        final qty   = (raw['quantity'] as num?)?.toInt() ?? 1;
        final price = (raw['price'] as num?)?.toDouble() ?? 0.0;
        overallCounts[name]  = (overallCounts[name] ?? 0) + qty;
        overallRevenue[name] = (overallRevenue[name] ?? 0.0) + price * qty;
      }
    }
    final overallRanked = overallCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final overallBestSellerName    = overallRanked.isEmpty ? 'None' : overallRanked.first.key;
    final overallBestSellerQty     = overallRanked.isEmpty ? 0 : overallRanked.first.value;
    final overallBestSellerRevenue = overallRevenue[overallBestSellerName] ?? 0.0;
    final topFiveItems = overallRanked.take(5).map((e) => {
      'name':    e.key,
      'qty':     e.value,
      'revenue': overallRevenue[e.key] ?? 0.0,
    }).toList();

    // ── Worst sellers ──────────────────────────────────────────────────
    final worstItems = <Map<String, dynamic>>[];
    for (final doc in menuDocs) {
      final name = (doc['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final sold = overallCounts[name] ?? 0;
      if (sold <= 3) worstItems.add({'name': name, 'soldLast30Days': sold});
    }
    worstItems.sort((a, b) =>
        (a['soldLast30Days'] as int).compareTo(b['soldLast30Days'] as int));
    final zeroSalesItemCount =
        worstItems.where((e) => (e['soldLast30Days'] as int) == 0).length;

    // ── Menu performance ───────────────────────────────────────────────
    final menuPerformance = menuDocs.map((doc) {
      final name = (doc['name'] ?? '').toString();
      final sold = overallCounts[name] ?? 0;
      return {
        'name':              name,
        'category':          (doc['category'] ?? '').toString(),
        'price':             (doc['price'] as num?)?.toDouble() ?? 0.0,
        'soldLast30Days':    sold,
        'revenueLast30Days': double.parse(
            (overallRevenue[name] ?? 0.0).toStringAsFixed(2)),
        'status': sold == 0
            ? 'no_sales'
            : sold < 5 ? 'low' : sold < 20 ? 'moderate' : 'high',
      };
    }).toList()
      ..sort((a, b) =>
          (b['soldLast30Days'] as int).compareTo(a['soldLast30Days'] as int));

    final totalMenuItems     = menuDocs.length;
    final menuItemsWithNoSales = menuPerformance
        .where((i) => i['status'] == 'no_sales').length;

    // ── Category breakdown ─────────────────────────────────────────────
    final catRevenue = <String, double>{};
    final catSold    = <String, int>{};
    for (final item in menuPerformance) {
      final cat = (item['category'] as String? ?? 'Uncategorised');
      catRevenue[cat] = (catRevenue[cat] ?? 0.0)
          + (item['revenueLast30Days'] as double? ?? 0.0);
      catSold[cat] = (catSold[cat] ?? 0)
          + (item['soldLast30Days'] as int? ?? 0);
    }
    final categoryBreakdown = catRevenue.entries.map((e) => {
      'category': e.key,
      'revenue':  double.parse(e.value.toStringAsFixed(2)),
      'unitsSold': catSold[e.key] ?? 0,
    }).toList()
      ..sort((a, b) =>
          (b['revenue'] as double).compareTo(a['revenue'] as double));
    final topCategory = categoryBreakdown.isEmpty
        ? 'N/A'
        : categoryBreakdown.first['category'] as String;

    // ── Inventory ─────────────────────────────────────────────────────
    int totalInv = 0, healthy = 0, lowStock = 0, critical = 0;
    double totalInvValue = 0.0;
    final lowStockItems = <Map<String, dynamic>>[];
    for (final doc in invDocs) {
      final current  = (doc['currentStock'] as num?)?.toDouble() ?? 0.0;
      final min      = (doc['minStock'] as num?)?.toDouble() ?? 0.0;
      final unitCost = (doc['unitCost'] as num?)?.toDouble() ?? 0.0;
      totalInv++;
      totalInvValue += current * unitCost;
      if (current <= 0) {
        critical++;
        lowStock++;
        lowStockItems.add({
          'name':         (doc['name'] ?? '').toString(),
          'currentStock': current,
          'minStock':     min,
          'unit':         (doc['unit'] ?? '').toString(),
          'isCritical':   true,
          'deficit':      min.clamp(0.0, double.infinity),
        });
      } else if (current <= min) {
        lowStock++;
        lowStockItems.add({
          'name':         (doc['name'] ?? '').toString(),
          'currentStock': current,
          'minStock':     min,
          'unit':         (doc['unit'] ?? '').toString(),
          'isCritical':   false,
          'deficit':      (min - current).clamp(0.0, double.infinity),
        });
      } else {
        healthy++;
      }
    }
    lowStockItems.sort((a, b) =>
        (a['currentStock'] as double).compareTo(b['currentStock'] as double));

    // ── Debug log — compare against dashboard visually ─────────────────
    debugPrint('════════════════════════════════════════════════');
    debugPrint('DASHBOARDMODEL — ${DateTime.now().toLocal()}');
    debugPrint('Eatery: $eateryId');
    debugPrint('Today Revenue     : ₱${todayRevenue.toStringAsFixed(2)}');
    debugPrint('Orders Today      : $todayTotalOrders '
        '(completed: $todayCompletedCount, pending: $todayPendingCount)');
    debugPrint('Best Seller Today : $todayBestSellerName '
        '(${todayBestSellerQty}x, ${todayBestSellerPct}% of items)');
    debugPrint('Week Revenue      : ₱${weekRevenue.toStringAsFixed(2)}');
    debugPrint('Month Revenue     : ₱${monthRevenue.toStringAsFixed(2)}');
    debugPrint('Avg Order Value   : ₱${aov.toStringAsFixed(2)}');
    debugPrint('Low Stock Items   : $lowStock ($critical critical)');
    debugPrint('════════════════════════════════════════════════');

    return DashboardModel._(
      eateryId:                eateryId,
      generatedAt:             DateTime.now(),
      todayRevenue:            todayRevenue,
      todayCompletedCount:     todayCompletedCount,
      todayPendingCount:       todayPendingCount,
      todayCancelledCount:     todayCancelledCount,
      todayTotalOrders:        todayTotalOrders,
      yesterdayRevenue:        yesterdayRevenue,
      yesterdayCompletedCount: yesterdayCompletedCount,
      weekRevenue:             weekRevenue,
      weekCompletedCount:      weekCompletedCount,
      weekCancelledCount:      weekCancelledCount,
      weekTotalOrders:         weekTotalOrders,
      monthRevenue:            monthRevenue,
      monthCompletedCount:     monthCompletedCount,
      averageOrderValue:       double.parse(aov.toStringAsFixed(2)),
      todayBestSellerName:     todayBestSellerName,
      todayBestSellerQty:      todayBestSellerQty,
      todayBestSellerRevenue:  todayBestSellerRevenue,
      todayBestSellerPct:      todayBestSellerPct,
      todayTopItems:           List<Map<String, dynamic>>.from(todayTopItems),
      todayItemCounts:         todayItemCounts,
      todayTotalItemsSold:     todayTotalItemsSold,
      weekItemCounts:          weekItemCounts,
      weekTotalItemsSold:      weekTotalItemsSold,
      overallBestSellerName:   overallBestSellerName,
      overallBestSellerQty:    overallBestSellerQty,
      overallBestSellerRevenue: overallBestSellerRevenue,
      topFiveItems:            List<Map<String, dynamic>>.from(topFiveItems),
      worstItems:              List<Map<String, dynamic>>.from(worstItems.take(10).toList()),
      zeroSalesItemCount:      zeroSalesItemCount,
      totalMenuItems:          totalMenuItems,
      menuItemsWithNoSales:    menuItemsWithNoSales,
      menuPerformance:         List<Map<String, dynamic>>.from(menuPerformance.take(15).toList()),
      topCategory:             topCategory,
      categoryBreakdown:       List<Map<String, dynamic>>.from(categoryBreakdown),
      totalInventoryItems:     totalInv,
      healthyStockCount:       healthy,
      lowStockCount:           lowStock,
      criticalStockCount:      critical,
      totalInventoryValue:     double.parse(totalInvValue.toStringAsFixed(2)),
      lowStockItems:           lowStockItems,
      pendingOrderCount:       pendingOrderCount,
      pendingOrderValue:       double.parse(pendingOrderValue.toStringAsFixed(2)),
    );
  }
}
