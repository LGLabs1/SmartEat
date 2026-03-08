const { db } = require('../config/firebase');

class Inventory {
  /**
   * Create new inventory item
   */
  static async create(inventoryData) {
    try {
      const inventoryRef = db.collection('inventory').doc();
      const inventory = {
        ...inventoryData,
        createdAt: new Date(),
        updatedAt: new Date(),
      };

      await inventoryRef.set(inventory);
      return { id: inventoryRef.id, ...inventory };
    } catch (error) {
      throw error;
    }
  }

  /**
   * Get inventory item by ID
   */
  static async getById(inventoryId) {
    try {
      const inventoryRef = await db.collection('inventory').doc(inventoryId).get();
      if (!inventoryRef.exists) return null;
      return { id: inventoryRef.id, ...inventoryRef.data() };
    } catch (error) {
      throw error;
    }
  }

  /**
   * Get all inventory items for eatery
   */
  static async getAll(eateryId) {
    try {
      const snapshot = await db
        .collection('inventory')
        .where('eateryId', '==', eateryId)
        .orderBy('category')
        .get();

      return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      throw error;
    }
  }

  /**
   * Get low stock items
   */
  static async getLowStock(eateryId) {
    try {
      const snapshot = await db
        .collection('inventory')
        .where('eateryId', '==', eateryId)
        .where('currentStock', '<=', db.FieldValue.increment('minStock'))
        .orderBy('currentStock', 'asc')
        .get();

      return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      throw error;
    }
  }

  /**
   * Get inventory by category
   */
  static async getByCategory(eateryId, category) {
    try {
      const snapshot = await db
        .collection('inventory')
        .where('eateryId', '==', eateryId)
        .where('category', '==', category)
        .orderBy('name')
        .get();

      return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      throw error;
    }
  }

  /**
   * Update inventory item
   */
  static async update(inventoryId, updateData) {
    try {
      const updatePayload = {
        ...updateData,
        updatedAt: new Date(),
      };
      await db.collection('inventory').doc(inventoryId).update(updatePayload);
      return this.getById(inventoryId);
    } catch (error) {
      throw error;
    }
  }

  /**
   * Update stock quantity
   */
  static async updateStock(inventoryId, quantity, operation = 'set') {
    try {
      const inventoryRef = db.collection('inventory').doc(inventoryId);
      
      if (operation === 'add') {
        await inventoryRef.update({
          currentStock: db.FieldValue.increment(quantity),
          updatedAt: new Date(),
        });
      } else if (operation === 'subtract') {
        await inventoryRef.update({
          currentStock: db.FieldValue.increment(-quantity),
          updatedAt: new Date(),
        });
      } else {
        await inventoryRef.update({
          currentStock: quantity,
          updatedAt: new Date(),
        });
      }
      
      return this.getById(inventoryId);
    } catch (error) {
      throw error;
    }
  }

  /**
   * Record inventory usage
   */
  static async recordUsage(usageData) {
    try {
      const usageRef = db.collection('inventory_usage').doc();
      const usage = {
        ...usageData,
        createdAt: new Date(),
      };

      await usageRef.set(usage);
      
      // Update inventory stock
      await this.updateStock(usageData.ingredientId, usageData.quantityUsed, 'subtract');
      
      return { id: usageRef.id, ...usage };
    } catch (error) {
      throw error;
    }
  }

  /**
   * Get inventory usage history
   */
  static async getUsageHistory(eateryId, startDate, endDate) {
    try {
      let query = db
        .collection('inventory_usage')
        .where('eateryId', '==', eateryId);

      if (startDate) {
        query = query.where('createdAt', '>=', startDate);
      }
      if (endDate) {
        query = query.where('createdAt', '<=', endDate);
      }

      const snapshot = await query.orderBy('createdAt', 'desc').get();
      return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      throw error;
    }
  }

  /**
   * Delete inventory item
   */
  static async delete(inventoryId) {
    try {
      await db.collection('inventory').doc(inventoryId).delete();
      return true;
    } catch (error) {
      throw error;
    }
  }

  /**
   * Get inventory analytics
   */
  static async getAnalytics(eateryId) {
    try {
      const inventory = await this.getAll(eateryId);
      const lowStock = await this.getLowStock(eateryId);
      
      const totalValue = inventory.reduce((sum, item) => 
        sum + (item.currentStock * item.unitCost), 0
      );
      
      const categoryBreakdown = inventory.reduce((acc, item) => {
        acc[item.category] = (acc[item.category] || 0) + 1;
        return acc;
      }, {});

      return {
        totalItems: inventory.length,
        lowStockItems: lowStock.length,
        totalValue: Math.round(totalValue * 100) / 100,
        categoryBreakdown,
        lowStockItems: lowStock,
      };
    } catch (error) {
      throw error;
    }
  }
}

module.exports = Inventory;
