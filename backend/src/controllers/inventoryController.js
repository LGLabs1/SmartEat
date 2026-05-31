const Inventory = require('../models/Inventory');
const InventoryLog = require('../models/InventoryLog');
const DamagedItem = require('../models/DamagedItem');

/**
 * Create new inventory item
 */
exports.createInventoryItem = async (req, res) => {
  try {
    const {
      name,
      category,
      currentStock,
      unit,
      minStock,
      unitCost,
      supplier,
    } = req.body;

    // Validate input
    if (!name || !category || currentStock === undefined || !unit || minStock === undefined || unitCost === undefined) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    const inventoryData = {
      name,
      category,
      currentStock: Number(currentStock),
      unit,
      minStock: Number(minStock),
      unitCost: Number(unitCost),
      supplier: supplier || '',
      eateryId: req.user.eateryId,
    };

    const inventory = await Inventory.create(inventoryData);

    res.status(201).json({
      message: 'Inventory item created successfully',
      data: inventory,
    });
  } catch (error) {
    console.error('Create inventory error:', error);
    res.status(500).json({ error: 'Failed to create inventory item' });
  }
};

/**
 * Get all inventory items
 */
exports.getInventoryItems = async (req, res) => {
  try {
    const { category } = req.query;
    let inventory;

    if (category) {
      inventory = await Inventory.getByCategory(req.user.eateryId, category);
    } else {
      inventory = await Inventory.getAll(req.user.eateryId);
    }

    res.json({
      data: inventory,
    });
  } catch (error) {
    console.error('Get inventory error:', error);
    res.status(500).json({ error: 'Failed to fetch inventory' });
  }
};

/**
 * Get single inventory item
 */
exports.getInventoryItem = async (req, res) => {
  try {
    const { id } = req.params;
    const inventory = await Inventory.getById(id);

    if (!inventory) {
      return res.status(404).json({ error: 'Inventory item not found' });
    }

    // Check if user has access to this eatery's inventory
    if (inventory.eateryId !== req.user.eateryId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    res.json({
      data: inventory,
    });
  } catch (error) {
    console.error('Get inventory item error:', error);
    res.status(500).json({ error: 'Failed to fetch inventory item' });
  }
};

/**
 * Update inventory item
 */
exports.updateInventoryItem = async (req, res) => {
  try {
    const { id } = req.params;
    const updateData = req.body;

    // Get existing item to verify ownership
    const existingItem = await Inventory.getById(id);
    if (!existingItem) {
      return res.status(404).json({ error: 'Inventory item not found' });
    }

    if (existingItem.eateryId !== req.user.eateryId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Remove eateryId from updateData to prevent changing ownership
    delete updateData.eateryId;

    const updatedInventory = await Inventory.update(id, updateData);

    res.json({
      message: 'Inventory item updated successfully',
      data: updatedInventory,
    });
  } catch (error) {
    console.error('Update inventory error:', error);
    res.status(500).json({ error: 'Failed to update inventory item' });
  }
};

/**
 * Update stock quantity
 */
exports.updateStock = async (req, res) => {
  try {
    const { id } = req.params;
    const { quantity, operation = 'set', isBadStock = false, badStockQuantity = 0 } = req.body;

    if (quantity === undefined || isNaN(quantity)) {
      return res.status(400).json({ error: 'Valid quantity required' });
    }

    // Get existing item to verify ownership
    const existingItem = await Inventory.getById(id);
    if (!existingItem) {
      return res.status(404).json({ error: 'Inventory item not found' });
    }

    if (existingItem.eateryId !== req.user.eateryId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Update stock based on operation
    const updatedInventory = await Inventory.updateStock(id, Number(quantity), operation);

    // If this is a bad stock adjustment, mark the item accordingly
    if (isBadStock && Number(badStockQuantity) > 0) {
      await Inventory.update(id, {
        isBadStock: true,
        badStockQuantity: Number(badStockQuantity),
      });
    }
    // After potential bad stock update, fetch latest item
    const finalInventory = await Inventory.getById(id);
    // Record a stock log entry for this operation
    await InventoryLog.create({
      inventoryItemId: id,
      quantityChange: Number(quantity) * (operation === 'add' ? 1 : operation === 'subtract' ? -1 : 0),
      reason: isBadStock ? 'Bad Stock' : 'Stock Update',
      performedBy: req.user.id,
    });
    res.json({
      message: 'Stock updated successfully',
      data: finalInventory,
    });
  } catch (error) {
    console.error('Update stock error:', error);
    res.status(500).json({ error: 'Failed to update stock' });
  }
};

/**
 * Get low stock items
 */
exports.getLowStockItems = async (req, res) => {
  try {
    const lowStockItems = await Inventory.getLowStock(req.user.eateryId);

    res.json({
      data: lowStockItems,
    });
  } catch (error) {
    console.error('Get low stock error:', error);
    res.status(500).json({ error: 'Failed to fetch low stock items' });
  }
};

/**
 * Mark inventory quantity as damaged/bad and record damaged item
 */
exports.markDamaged = async (req, res) => {
  try {
    const { id } = req.params;
    const { badQuantity, reason = 'Damaged' } = req.body;

    if (badQuantity === undefined || isNaN(badQuantity) || Number(badQuantity) <= 0) {
      return res.status(400).json({ error: 'Valid badQuantity is required' });
    }

    const item = await Inventory.getById(id);
    if (!item) return res.status(404).json({ error: 'Inventory item not found' });
    if (item.eateryId !== req.user.eateryId) return res.status(403).json({ error: 'Access denied' });

    const qty = Number(badQuantity);
    if (item.currentStock < qty) {
      return res.status(400).json({ error: 'Not enough stock to mark as damaged' });
    }

    // Subtract from current stock
    const updated = await Inventory.updateStock(id, qty, 'subtract');

    // Compute cost
    const unitCost = Number(item.unitCost || 0);
    const totalCost = Math.round((unitCost * qty) * 100) / 100;

    // Create damaged item record
    const damagedRecord = await DamagedItem.create({
      inventoryItemId: id,
      name: item.name,
      quantity: qty,
      unit: item.unit || '',
      unitCost,
      totalCost,
      reason,
      eateryId: req.user.eateryId,
      recordedBy: req.user.id,
    });

    // Log the change
    await InventoryLog.create({
      inventoryItemId: id,
      quantityChange: -qty,
      reason: 'Damaged',
      performedBy: req.user.id,
    });

    res.status(201).json({ message: 'Marked as damaged', data: { damagedRecord, updatedInventory: updated } });
  } catch (error) {
    console.error('Mark damaged error:', error);
    res.status(500).json({ error: 'Failed to mark damaged' });
  }
};

/**
 * Get damaged items for eatery
 */
exports.getDamagedItems = async (req, res) => {
  try {
    const damaged = await DamagedItem.getByEatery(req.user.eateryId);
    res.json({ data: damaged });
  } catch (error) {
    console.error('Get damaged items error:', error);
    res.status(500).json({ error: 'Failed to fetch damaged items' });
  }
};

/**
 * Record inventory usage
 */
exports.recordUsage = async (req, res) => {
  try {
    const { ingredientId, orderId, quantityUsed, unitCost } = req.body;

    if (!ingredientId || !orderId || quantityUsed === undefined || unitCost === undefined) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Verify ingredient ownership
    const ingredient = await Inventory.getById(ingredientId);
    if (!ingredient) {
      return res.status(404).json({ error: 'Ingredient not found' });
    }

    if (ingredient.eateryId !== req.user.eateryId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const usageData = {
      ingredientId,
      orderId,
      quantityUsed: Number(quantityUsed),
      unitCost: Number(unitCost),
      eateryId: req.user.eateryId,
    };

    const usage = await Inventory.recordUsage(usageData);

    res.status(201).json({
      message: 'Inventory usage recorded successfully',
      data: usage,
    });
  } catch (error) {
    console.error('Record usage error:', error);
    res.status(500).json({ error: 'Failed to record inventory usage' });
  }
};

/**
 * Get inventory usage history
 */
exports.getUsageHistory = async (req, res) => {
  try {
    const { startDate, endDate } = req.query;
    
    let start = null;
    let end = null;
    
    if (startDate) {
      start = new Date(startDate);
    }
    if (endDate) {
      end = new Date(endDate);
    }

    const usageHistory = await Inventory.getUsageHistory(req.user.eateryId, start, end);

    res.json({
      data: usageHistory,
    });
  } catch (error) {
    console.error('Get usage history error:', error);
    res.status(500).json({ error: 'Failed to fetch usage history' });
  }
};

/**
 * Get inventory analytics
 */
exports.getInventoryAnalytics = async (req, res) => {
  try {
    const analytics = await Inventory.getAnalytics(req.user.eateryId);

    res.json({
      data: analytics,
    });
  } catch (error) {
    console.error('Get inventory analytics error:', error);
    res.status(500).json({ error: 'Failed to fetch inventory analytics' });
  }
};

/**
 * Delete inventory item
 */
exports.deleteInventoryItem = async (req, res) => {
  try {
    const { id } = req.params;

    // Get existing item to verify ownership
    const existingItem = await Inventory.getById(id);
    if (!existingItem) {
      return res.status(404).json({ error: 'Inventory item not found' });
    }

    if (existingItem.eateryId !== req.user.eateryId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    await Inventory.delete(id);

    res.json({
      message: 'Inventory item deleted successfully',
    });
  } catch (error) {
    console.error('Delete inventory error:', error);
    res.status(500).json({ error: 'Failed to delete inventory item' });
  }
};
