const { db } = require('../config/firebase');

class InventoryLog {
  /**
   * Create a new inventory log entry
   * @param {Object} logData - { inventoryItemId, quantityChange, reason, performedBy }
   */
  static async create(logData) {
    try {
      const logRef = db.collection('inventory_logs').doc();
      const logEntry = {
        ...logData,
        timestamp: new Date(),
      };
      await logRef.set(logEntry);
      return { id: logRef.id, ...logEntry };
    } catch (error) {
      throw error;
    }
  }

  /**
   * Retrieve logs for a specific inventory item
   */
  static async getByItemId(itemId) {
    try {
      const snapshot = await db
        .collection('inventory_logs')
        .where('inventoryItemId', '==', itemId)
        .orderBy('timestamp', 'desc')
        .get();
      return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      throw error;
    }
  }
}

module.exports = InventoryLog;
