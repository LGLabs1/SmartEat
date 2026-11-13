import 'package:flutter_test/flutter_test.dart';
import 'package:smarteat/utils/order_query_key.dart';

/// Guards the in-flight de-duplication of ranged orders queries: identical
/// callers must produce the same key (so they share one fetch) while different
/// eateries or windows must not collide.
void main() {
  test('identical windows share one key', () {
    final start = DateTime(2026, 1, 1);
    final end = DateTime(2026, 1, 31);
    expect(
      orderQueryKey('eateryA', start, end),
      orderQueryKey('eateryA', DateTime(2026, 1, 1), DateTime(2026, 1, 31)),
    );
  });

  test('different eateries never share a key', () {
    expect(
      orderQueryKey('eateryA', null, null),
      isNot(orderQueryKey('eateryB', null, null)),
    );
  });

  test('different windows never share a key', () {
    final start = DateTime(2026, 1, 1);
    expect(
      orderQueryKey('eateryA', start, null),
      isNot(orderQueryKey('eateryA', null, null)),
    );
    expect(
      orderQueryKey('eateryA', start, null),
      isNot(orderQueryKey('eateryA', DateTime(2026, 2, 1), null)),
    );
  });

  test('unbounded all-orders call is its own bucket', () {
    expect(
      orderQueryKey('eateryA', null, null),
      orderQueryKey('eateryA', null, null),
    );
  });
}