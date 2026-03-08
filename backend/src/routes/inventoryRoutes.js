const express = require('express');
const { verifyToken, checkRole } = require('../middleware/auth');
const inventoryController = require('../controllers/inventoryController');

const router = express.Router();

// All inventory routes require authentication
router.use(verifyToken);

// GET /api/inventory - Get all inventory items
router.get('/', inventoryController.getInventoryItems);

// GET /api/inventory/low-stock - Get low stock items
router.get('/low-stock', inventoryController.getLowStockItems);

// GET /api/inventory/analytics - Get inventory analytics
router.get('/analytics', inventoryController.getInventoryAnalytics);

// GET /api/inventory/usage - Get usage history
router.get('/usage', inventoryController.getUsageHistory);

// GET /api/inventory/:id - Get single inventory item
router.get('/:id', inventoryController.getInventoryItem);

// POST /api/inventory - Create new inventory item (Manager/Admin only)
router.post('/', checkRole(['admin', 'manager']), inventoryController.createInventoryItem);

// PUT /api/inventory/:id - Update inventory item (Manager/Admin only)
router.put('/:id', checkRole(['admin', 'manager']), inventoryController.updateInventoryItem);

// PUT /api/inventory/:id/stock - Update stock quantity (Staff+)
router.put('/:id/stock', inventoryController.updateStock);

// POST /api/inventory/usage - Record inventory usage (Staff+)
router.post('/usage', inventoryController.recordUsage);

// DELETE /api/inventory/:id - Delete inventory item (Admin only)
router.delete('/:id', checkRole(['admin']), inventoryController.deleteInventoryItem);

module.exports = router;
