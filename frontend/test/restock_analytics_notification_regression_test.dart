import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/screens/notifications_screen.dart';
import 'package:smarteat/services/api_service.dart';

void main() {
  test('recommendations use completed orders from the last 30 days', () {
    final now = DateTime(2026, 11, 23, 12);
    final orders = <dynamic>[
      {
        'status': 'completed',
        'completedAt': now.subtract(const Duration(days: 1)),
        'items': [
          {
            'menuItemId': 'alpha',
            'name': 'Alpha',
            'quantity': 6,
            'price': 100,
          },
        ],
      },
      {
        'status': 'completed',
        'completedAt': now.subtract(const Duration(days: 2)),
        'items': [
          {
            'menuItemId': 'alpha',
            'name': 'Alpha',
            'quantity': 6,
            'price': 100,
          },
        ],
      },
      {
        'status': 'completed',
        'completedAt': now.subtract(const Duration(days: 3)),
        'items': [
          {
            'menuItemId': 'beta',
            'name': 'Beta',
            'quantity': 1,
            'price': 20,
          },
        ],
      },
      {
        'status': 'pending',
        'completedAt': now,
        'items': [
          {
            'menuItemId': 'gamma',
            'name': 'Gamma',
            'quantity': 50,
            'price': 20,
          },
        ],
      },
      {
        'status': 'completed',
        'completedAt': now.subtract(const Duration(days: 60)),
        'items': [
          {
            'menuItemId': 'old',
            'name': 'Old Item',
            'quantity': 50,
            'price': 20,
          },
        ],
      },
    ];

    final data = ApiService.buildRecommendationData(
      orders: orders,
      inventory: const [],
      now: now,
    );
    final promoteNames =
        (data['promoteItems'] as List).map((item) => item['name']).toSet();
    final removeNames =
        (data['removeItems'] as List).map((item) => item['name']).toSet();

    expect(promoteNames, contains('Alpha'));
    expect(removeNames, contains('Beta'));
    expect(promoteNames, isNot(contains('Gamma')));
    expect(promoteNames, isNot(contains('Old Item')));
    expect(promoteNames.intersection(removeNames), isEmpty);
  });

  test('notification feed ids use the eatery prefix required by rules', () {
    final id = notificationDocId('eatery_1', 'low_stock:rice-42');

    expect(id, startsWith('eatery_1_'));
    expect(id, contains('low_stock_rice-42'));
    expect(notificationDocId('', 'order_created_1'), startsWith('eatery_'));
  });
}
