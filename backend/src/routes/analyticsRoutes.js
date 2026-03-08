const express = require('express');
const { verifyToken, checkRole } = require('../middleware/auth');
const analyticsController = require('../controllers/analyticsController');

const router = express.Router();

// All analytics routes require authentication
router.use(verifyToken);

// GET /api/analytics/summary - Get summary statistics
router.get('/summary', analyticsController.getSummaryStats);

// GET /api/analytics/sales/daily - Get daily sales analytics
router.get('/sales/daily', analyticsController.getDailySalesAnalytics);

// GET /api/analytics/items/performance - Get item performance
router.get('/items/performance', analyticsController.getItemPerformance);

// GET /api/analytics/peak-hours - Get peak hours analysis
router.get('/peak-hours', analyticsController.getPeakHours);

// GET /api/analytics/forecast/demand - Get demand forecast
router.get('/forecast/demand', analyticsController.getDemandForecast);

// GET /api/analytics/forecast/sales - Get sales forecast
router.get('/forecast/sales', analyticsController.getSalesForecast);

// GET /api/analytics/recommendations - Get recommendations
router.get('/recommendations', analyticsController.getRecommendations);

module.exports = router;
