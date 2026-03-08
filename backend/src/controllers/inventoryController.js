const Inventory = require('../models/Inventory');

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
    const { quantity, operation = 'set' } = req.body;

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

    const updatedInventory = await Inventory.updateStock(id, Number(quantity), operation);

    res.json({
      message: 'Stock updated successfully',
      data: updatedInventory,
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
