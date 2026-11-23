String orderConsumptionMovementId(String orderId, String itemId) =>
    'sale_${orderId.trim()}_${itemId.trim()}';

Map<String, dynamic> buildOrderConsumptionMovement({
  required String orderId,
  required String eateryId,
  required String itemId,
  required double qtyBeforeBase,
  required double qtyAfterBase,
  required double changeBase,
  required double unitCostAtEvent,
  required dynamic timestamp,
  String? performedBy,
}) {
  return <String, dynamic>{
    'id': orderConsumptionMovementId(orderId, itemId),
    'eateryId': eateryId,
    'itemId': itemId,
    'locationId': 'main',
    'type': 'saleConsumption',
    'referenceType': 'order',
    'referenceId': orderId,
    'qtyBeforeBase': qtyBeforeBase,
    'qtyAfterBase': qtyAfterBase,
    'changeBase': changeBase,
    'unitCostAtEvent': unitCostAtEvent,
    'totalCostImpact': changeBase * unitCostAtEvent,
    'performedBy': performedBy ?? '',
    'reasonCode': 'pos_recipe_order',
    'notes': '',
    'timestamp': timestamp,
    'createdAt': timestamp,
  };
}
