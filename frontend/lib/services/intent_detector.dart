class IntentDetector {
  static String detectIntent(String message) {
    final lowerMessage = message.toLowerCase().trim();

    // Check Navigation Intent first
    if (lowerMessage.contains('where is') ||
        lowerMessage.contains('open') ||
        lowerMessage.contains('go to') ||
        lowerMessage.contains('navigate to') ||
        lowerMessage.contains('edit') ||
        lowerMessage.contains('show me')) {
      return 'navigation';
    }

    // Check Inventory Intent
    if (lowerMessage.contains('low stock') ||
        lowerMessage.contains('inventory') ||
        lowerMessage.contains('ingredients') ||
        lowerMessage.contains('expiration') ||
        lowerMessage.contains('supplies') ||
        lowerMessage.contains('stock') ||
        lowerMessage.contains('expire') ||
        lowerMessage.contains('reorder')) {
      return 'inventory';
    }

    // Check Sales Intent
    if (lowerMessage.contains('best seller') ||
        lowerMessage.contains('best-selling') ||
        lowerMessage.contains('revenue') ||
        lowerMessage.contains('sales') ||
        lowerMessage.contains('income') ||
        lowerMessage.contains('profit') ||
        lowerMessage.contains('selling') ||
        lowerMessage.contains('sold') ||
        lowerMessage.contains('earn') ||
        lowerMessage.contains('earned')) {
      return 'sales';
    }

    // Check Orders Intent
    if (lowerMessage.contains('pending orders') ||
        lowerMessage.contains('completed orders') ||
        lowerMessage.contains('cancelled orders') ||
        lowerMessage.contains('orders') ||
        lowerMessage.contains('order') ||
        lowerMessage.contains('queue') ||
        lowerMessage.contains('prep time') ||
        lowerMessage.contains('preparation')) {
      return 'orders';
    }

    // Default is General (greetings, help, general questions)
    return 'general';
  }
}
