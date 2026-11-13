import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/business_context.dart';
import 'firebase_service.dart';

/// Derives rich [Insight] maps from a pre-built [BusinessContext].
/// Falls back to minimal Firestore queries only when no context is supplied.
///
/// THE AI NEVER CALLS THIS CLASS — it is the UI insight layer only.
class FirestoreInsightsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _col(
      String eateryId, String name) {
    return _firestore
        .collection(FirebaseService.eateriesCollection)
        .doc(eateryId)
        .collection(name);
  }

  // ── Unified entry point ────────────────────────────────────────────────────

  /// Returns insight cards for [page], using [context] when available.
  static Future<List<Map<String, dynamic>>> getInsightsForPage(
    String page, {
    BusinessContext? context,
  }) async {
    switch (page) {
      case 'dashboard':
        return getDashboardInsights(context: context);
      case 'inventory':
        return getInventoryInsights(context: context);
      case 'orders':
        return getOrdersInsights(context: context);
      case 'menu':
        return getMenuInsights(context: context);
      case 'reports':
        return getReportsInsights(context: context);
      case 'finance':
        return getFinanceInsights(context: context);
      default:
        return [];
    }
  }

  // ── Dashboard ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getDashboardInsights({
    BusinessContext? context,
  }) async {
    final insights = <Map<String, dynamic>>[];

    try {
      final ctx = context ?? await _buildMinimalContext();

      // 1. Revenue with day-over-day change
      final changeLabel = ctx.dayChangePercent >= 0
          ? '+${ctx.dayChangePercent.toStringAsFixed(1)}%'
          : '${ctx.dayChangePercent.toStringAsFixed(1)}%';
      final revenueColor =
          ctx.dayChangePercent >= 0 ? Colors.green : Colors.redAccent;

      insights.add({
        'title': "Today's Revenue",
        'message':
            '₱${ctx.todayRevenue.toStringAsFixed(2)} across ${ctx.todayOrderCount} orders ($changeLabel vs yesterday).',
        'icon': Icons.monetization_on_outlined,
        'color': revenueColor,
        'isImportant': ctx.dayChangePercent >= 15 || ctx.dayChangePercent <= -20,
      });

      // 2. Best seller
      if (ctx.todayBestSeller != 'None') {
        insights.add({
          'title': "Today's Best Seller",
          'message':
              '${ctx.todayBestSeller} leads with ${ctx.todayBestSellerQty} sold today.',
          'icon': Icons.star_rounded,
          'color': Colors.amber,
          'isImportant': false,
        });
      }

      // 3. Business health
      final healthColor = ctx.healthScore >= 80
          ? Colors.green
          : ctx.healthScore >= 60
              ? Colors.lightGreen
              : ctx.healthScore >= 40
                  ? Colors.orange
                  : Colors.redAccent;
      insights.add({
        'title': 'Business Health',
        'message':
            'Health score: ${ctx.healthScore.toStringAsFixed(0)}/100 (${ctx.healthLabel}). '
            'Monthly trend: ${ctx.monthlyGrowthPercent >= 0 ? '+' : ''}${ctx.monthlyGrowthPercent.toStringAsFixed(1)}% vs last month.',
        'icon': Icons.monitor_heart_outlined,
        'color': healthColor,
        'isImportant': ctx.healthScore < 40,
      });

      // 4. Stock alert (if any)
      if (ctx.criticalStockCount > 0) {
        insights.add({
          'title': 'Critical Stock Alert',
          'message':
              '${ctx.criticalStockCount} item(s) are completely out of stock. This may affect menu availability.',
          'icon': Icons.error_outline_rounded,
          'color': Colors.redAccent,
          'isImportant': true,
        });
      } else if (ctx.lowStockCount > 0) {
        final names =
            ctx.lowStockItems.take(2).map((i) => i['name'] as String).join(', ');
        insights.add({
          'title': 'Low Stock',
          'message':
              '${ctx.lowStockCount} item(s) below minimum: $names${ctx.lowStockCount > 2 ? ' and more' : ''}.',
          'icon': Icons.warning_amber_rounded,
          'color': Colors.orange,
          'isImportant': ctx.lowStockCount >= 3,
        });
      }

      // 5. Peak hour
      if (ctx.peakHour != 'N/A') {
        insights.add({
          'title': 'Peak Hour',
          'message':
              '${ctx.peakHour} is your busiest time. ${ctx.bestDayOfWeek} is your best-performing day of the week.',
          'icon': Icons.access_time_rounded,
          'color': Colors.blueAccent,
          'isImportant': false,
        });
      }
    } catch (e) {
      debugPrint('getDashboardInsights error: $e');
    }

    return insights;
  }

  // ── Inventory ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getInventoryInsights({
    BusinessContext? context,
  }) async {
    final insights = <Map<String, dynamic>>[];

    try {
      final ctx = context ?? await _buildMinimalContext();

      if (ctx.criticalStockCount > 0) {
        final names = ctx.lowStockItems
            .where((i) => i['isCritical'] == true)
            .take(3)
            .map((i) => '${i['name']} (${i['unit']})')
            .join(', ');
        insights.add({
          'title': 'OUT OF STOCK',
          'message':
              '${ctx.criticalStockCount} item(s) at zero: $names. Restock immediately.',
          'icon': Icons.error_rounded,
          'color': Colors.red,
          'isImportant': true,
        });
      }

      if (ctx.lowStockCount > ctx.criticalStockCount) {
        final lowOnly = ctx.lowStockItems
            .where((i) => i['isCritical'] != true)
            .take(4)
            .map((i) =>
                '${i['name']} (${(i['currentStock'] as num).toStringAsFixed(1)}/${(i['minStock'] as num).toStringAsFixed(1)} ${i['unit']})')
            .join(', ');
        insights.add({
          'title': 'Low Stock Alert',
          'message': '$lowOnly',
          'icon': Icons.warning_amber_rounded,
          'color': Colors.orange,
          'isImportant': ctx.lowStockCount >= 3,
        });
      }

      if (ctx.expiringItems.isNotEmpty) {
        final expiryList = ctx.expiringItems
            .take(3)
            .map((i) => '${i['name']} in ${i['daysUntilExpiry']}d')
            .join(', ');
        insights.add({
          'title': 'Expiring Soon',
          'message': 'Use or sell before expiry: $expiryList.',
          'icon': Icons.schedule_rounded,
          'color': Colors.deepOrange,
          'isImportant': ctx.expiringItems
              .any((i) => (i['daysUntilExpiry'] as int? ?? 99) <= 2),
        });
      }

      if (ctx.suggestedRestocks.isNotEmpty) {
        final restockList = ctx.suggestedRestocks
            .take(3)
            .map((i) =>
                '${i['name']} — order ${i['suggestedOrderQty']} ${i['unit']}')
            .join('; ');
        insights.add({
          'title': 'Suggested Restocks',
          'message': restockList,
          'icon': Icons.shopping_cart_outlined,
          'color': Colors.teal,
          'isImportant': false,
        });
      }

      if (insights.isEmpty) {
        insights.add({
          'title': 'Stock Levels Healthy',
          'message':
              'All ${ctx.totalInventoryItems} inventory items are above minimum stock levels.',
          'icon': Icons.check_circle_outline,
          'color': Colors.green,
          'isImportant': false,
        });
      }
    } catch (e) {
      debugPrint('getInventoryInsights error: $e');
    }

    return insights;
  }

  // ── Orders / POS ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getOrdersInsights({
    BusinessContext? context,
  }) async {
    final insights = <Map<String, dynamic>>[];

    try {
      final ctx = context ?? await _buildMinimalContext();

      insights.add({
        'title': 'Active Queue',
        'message': ctx.pendingOrderCount == 0
            ? 'No pending orders. Ready for new sales.'
            : '${ctx.pendingOrderCount} order(s) pending (₱${ctx.pendingOrderValue.toStringAsFixed(2)} value).',
        'icon': ctx.pendingOrderCount == 0
            ? Icons.assignment_turned_in_outlined
            : Icons.hourglass_empty_rounded,
        'color': ctx.pendingOrderCount >= 5 ? Colors.orange : Colors.blue,
        'isImportant': ctx.pendingOrderCount >= 5,
      });

      insights.add({
        'title': "Today's Orders",
        'message':
            '${ctx.todayOrderCount} completed, ₱${ctx.averageOrderValue.toStringAsFixed(2)} avg order value.',
        'icon': Icons.receipt_long_outlined,
        'color': Colors.green,
        'isImportant': false,
      });

      if (ctx.cancellationRatePercent >= 10) {
        insights.add({
          'title': 'High Cancellation Rate',
          'message':
              '${ctx.cancellationRatePercent.toStringAsFixed(1)}% of orders this week were voided. Investigate causes.',
          'icon': Icons.cancel_outlined,
          'color': Colors.redAccent,
          'isImportant': true,
        });
      }
    } catch (e) {
      debugPrint('getOrdersInsights error: $e');
    }

    return insights;
  }

  // ── Menu ──────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getMenuInsights({
    BusinessContext? context,
  }) async {
    final insights = <Map<String, dynamic>>[];

    try {
      final ctx = context ?? await _buildMinimalContext();

      // Top category
      if (ctx.topCategory != 'N/A') {
        insights.add({
          'title': 'Top Category',
          'message':
              '${ctx.topCategory} is your best-performing category this month.',
          'icon': Icons.category_outlined,
          'color': Colors.blueAccent,
          'isImportant': false,
        });
      }

      // Zero-sales items
      if (ctx.zeroSalesItemCount > 0) {
        final worstNames = ctx.worstItems
            .where((i) => i['soldLast30Days'] == 0)
            .take(3)
            .map((i) => i['name'] as String)
            .join(', ');
        insights.add({
          'title': 'Dead Stock Menu Items',
          'message':
              '${ctx.zeroSalesItemCount} item(s) with zero sales in 30 days: $worstNames. Consider removing or promoting.',
          'icon': Icons.trending_down_rounded,
          'color': Colors.redAccent,
          'isImportant': ctx.zeroSalesItemCount >= 3,
        });
      }

      // Best seller cross-sell
      if (ctx.overallBestSeller != 'None') {
        insights.add({
          'title': '30-Day Best Seller',
          'message':
              '${ctx.overallBestSeller} sold ${ctx.overallBestSellerQty} times generating ₱${ctx.overallBestSellerRevenue.toStringAsFixed(2)}.',
          'icon': Icons.star_border_rounded,
          'color': Colors.amber,
          'isImportant': false,
        });
      }

      if (insights.isEmpty) {
        insights.add({
          'title': 'Menu Performance',
          'message':
              '${ctx.totalMenuItems} items on the menu. Check Analytics for detailed performance.',
          'icon': Icons.restaurant_menu_outlined,
          'color': Colors.purple,
          'isImportant': false,
        });
      }
    } catch (e) {
      debugPrint('getMenuInsights error: $e');
    }

    return insights;
  }

  // ── Reports / Analytics ───────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getReportsInsights({
    BusinessContext? context,
  }) async {
    final insights = <Map<String, dynamic>>[];

    try {
      final ctx = context ?? await _buildMinimalContext();

      // Trend direction
      final trendIcon = ctx.trendDirection == 'improving'
          ? Icons.trending_up
          : ctx.trendDirection == 'declining'
              ? Icons.trending_down
              : Icons.trending_flat;
      final trendColor = ctx.trendDirection == 'improving'
          ? Colors.green
          : ctx.trendDirection == 'declining'
              ? Colors.redAccent
              : Colors.blueGrey;
      insights.add({
        'title': '14-Day Revenue Trend',
        'message':
            'Revenue is ${ctx.trendDirection} over the last 14 days. Best day: ${ctx.bestDayOfWeek} (₱${ctx.bestDayRevenue.toStringAsFixed(2)} avg).',
        'icon': trendIcon,
        'color': trendColor,
        'isImportant': ctx.trendDirection == 'declining',
      });

      // Monthly growth
      final growthColor =
          ctx.monthlyGrowthPercent >= 0 ? Colors.green : Colors.redAccent;
      insights.add({
        'title': 'Monthly Growth',
        'message':
            '${ctx.thisMonth}: ₱${ctx.monthRevenue.toStringAsFixed(2)} (${ctx.monthlyGrowthPercent >= 0 ? '+' : ''}${ctx.monthlyGrowthPercent.toStringAsFixed(1)}% vs ${ctx.lastMonth}).',
        'icon': Icons.bar_chart_rounded,
        'color': growthColor,
        'isImportant': false,
      });

      // Forecast highlight
      if (ctx.salesForecast.isNotEmpty) {
        final next = ctx.salesForecast.first;
        insights.add({
          'title': 'Tomorrow\'s Forecast',
          'message':
              'Expected ₱${((next['predictedRevenue'] as num?) ?? 0).toStringAsFixed(2)} on ${next['dayName']} based on historical patterns.',
          'icon': Icons.auto_graph_rounded,
          'color': Colors.cyan,
          'isImportant': false,
        });
      }
    } catch (e) {
      debugPrint('getReportsInsights error: $e');
    }

    return insights;
  }

  // ── Finance ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getFinanceInsights({
    BusinessContext? context,
  }) async {
    final insights = <Map<String, dynamic>>[];

    try {
      final ctx = context ?? await _buildMinimalContext();

      final growthColor =
          ctx.monthlyGrowthPercent >= 0 ? Colors.green : Colors.redAccent;
      final sign = ctx.monthlyGrowthPercent >= 0 ? '+' : '';
      insights.add({
        'title': 'Monthly Revenue',
        'message':
            '${ctx.thisMonth}: ₱${ctx.monthRevenue.toStringAsFixed(2)} ($sign${ctx.monthlyGrowthPercent.toStringAsFixed(1)}% vs ${ctx.lastMonth}).',
        'icon': Icons.account_balance_wallet_outlined,
        'color': growthColor,
        'isImportant': ctx.monthlyGrowthPercent >= 15,
      });

      insights.add({
        'title': 'Average Order Value',
        'message':
            '₱${ctx.averageOrderValue.toStringAsFixed(2)} average per order this month across ${ctx.monthOrderCount} orders.',
        'icon': Icons.receipt_outlined,
        'color': Colors.blueAccent,
        'isImportant': false,
      });

      if (ctx.cancellationRatePercent > 0) {
        insights.add({
          'title': 'Voids This Week',
          'message':
              '${ctx.cancelledLast7Days} voided order(s) (${ctx.cancellationRatePercent.toStringAsFixed(1)}% rate). Monitor for unusual patterns.',
          'icon': Icons.money_off_outlined,
          'color': ctx.cancellationRatePercent >= 10
              ? Colors.redAccent
              : Colors.grey,
          'isImportant': ctx.cancellationRatePercent >= 10,
        });
      }
    } catch (e) {
      debugPrint('getFinanceInsights error: $e');
    }

    return insights;
  }

  // ── Backward-compat shim (old fetchBusinessSummary callers) ───────────────

  static Future<Map<String, dynamic>> fetchBusinessSummary() async {
    try {
      final eateryId = await FirebaseService.getCurrentEateryId();
      if (eateryId == null || eateryId.isEmpty) return _emptySummary();

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final results = await Future.wait([
        _col(eateryId, FirebaseService.ordersCollection)
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
            .get(),
        _col(eateryId, FirebaseService.inventoryCollection).get(),
        _col(eateryId, FirebaseService.menuCollection).get(),
      ]);

      final ordersSnap = results[0];
      final inventorySnap = results[1];
      final menuSnap = results[2];

      double todayRevenue = 0.0;
      int completedOrdersCount = 0;
      int pendingOrdersCount = 0;
      final itemSales = <String, int>{};

      for (final doc in ordersSnap.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'completed') {
          todayRevenue +=
              (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
          completedOrdersCount++;
        } else if (status == 'pending') {
          pendingOrdersCount++;
        }
        for (final item in (data['items'] as List? ?? [])) {
          if (item is Map) {
            final name = (item['name'] ?? 'Unknown').toString();
            final qty = (item['quantity'] as num?)?.toInt() ?? 0;
            itemSales[name] = (itemSales[name] ?? 0) + qty;
          }
        }
      }

      String topSeller = 'None';
      int maxQty = 0;
      itemSales.forEach((name, qty) {
        if (qty > maxQty) {
          maxQty = qty;
          topSeller = name;
        }
      });

      int lowStockCount = 0;
      final List<String> lowStockNames = [];
      for (final doc in inventorySnap.docs) {
        final data = doc.data();
        final current = (data['currentStock'] as num?)?.toDouble() ?? 0.0;
        final min = (data['minStock'] as num?)?.toDouble() ?? 0.0;
        if (current <= min) {
          lowStockCount++;
          if (lowStockNames.length < 3) {
            lowStockNames.add((data['name'] ?? '').toString());
          }
        }
      }

      return {
        'todayRevenue': todayRevenue,
        'todayOrdersCount': completedOrdersCount,
        'pendingOrdersCount': pendingOrdersCount,
        'topSeller': topSeller,
        'lowStockCount': lowStockCount,
        'lowStockNames': lowStockNames,
        'menuNoImageCount': 0,
        'totalInventoryCount': inventorySnap.docs.length,
        'totalMenuCount': menuSnap.docs.length,
      };
    } catch (e) {
      debugPrint('fetchBusinessSummary error: $e');
      return _emptySummary();
    }
  }

  static Map<String, dynamic> _emptySummary() => {
        'todayRevenue': 0.0,
        'todayOrdersCount': 0,
        'pendingOrdersCount': 0,
        'topSeller': 'None',
        'lowStockCount': 0,
        'lowStockNames': <String>[],
        'menuNoImageCount': 0,
        'totalInventoryCount': 0,
        'totalMenuCount': 0,
      };

  // ── Minimal context fallback ───────────────────────────────────────────────

  /// Builds a minimal BusinessContext using only today's orders + inventory.
  /// Used as a fallback when the full builder hasn't run yet.
  static Future<BusinessContext> _buildMinimalContext() async {
    final summary = await fetchBusinessSummary();
    return BusinessContext(
      eateryId: '',
      eateryName: '',
      generatedAt: DateTime.now().toIso8601String(),
      todayRevenue: (summary['todayRevenue'] as num?)?.toDouble() ?? 0,
      todayOrderCount: (summary['todayOrdersCount'] as num?)?.toInt() ?? 0,
      pendingOrderCount: (summary['pendingOrdersCount'] as num?)?.toInt() ?? 0,
      todayBestSeller: (summary['topSeller'] as String?) ?? 'None',
      lowStockCount: (summary['lowStockCount'] as num?)?.toInt() ?? 0,
      lowStockItems: (summary['lowStockNames'] as List<String>? ?? [])
          .map((n) => <String, dynamic>{'name': n, 'isCritical': false})
          .toList(),
    );
  }
}
