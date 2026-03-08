const { db } = require('../config/firebase');
const { formatDate, calculatePercentageChange, roundAmount } = require('../utils/helpers');
const axios = require('axios');

/**
 * Get daily sales analytics
 */
exports.getDailySalesAnalytics = async (req, res) => {
  try {
    const { days = 30 } = req.query;
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - parseInt(days));

    const ordersSnapshot = await db
      .collection('orders')
      .where('eateryId', '==', req.user.eateryId)
      .where('createdAt', '>=', startDate)
      .where('status', '==', 'completed')
      .orderBy('createdAt', 'asc')
      .get();

    const dailyData = {};
    const totalRevenue = { revenue: 0, orders: 0 };
    
    ordersSnapshot.docs.forEach(doc => {
      const order = doc.data();
      const date = formatDate(order.createdAt);
      
      if (!dailyData[date]) {
        dailyData[date] = {
          date,
          revenue: 0,
          orders: 0,
          averageOrderValue: 0,
          items: []
        };
      }
      
      dailyData[date].revenue += order.totalAmount;
      dailyData[date].orders += 1;
      dailyData[date].items.push(...order.items);
      
      totalRevenue.revenue += order.totalAmount;
      totalRevenue.orders += 1;
    });

    // Calculate averages and format data
    const analyticsData = Object.values(dailyData).map(day => {
      day.averageOrderValue = day.orders > 0 ? roundAmount(day.revenue / day.orders) : 0;
      day.revenue = roundAmount(day.revenue);
      return day;
    });

    res.json({
      data: {
        dailySales: analyticsData,
        summary: {
          totalRevenue: roundAmount(totalRevenue.revenue),
          totalOrders: totalRevenue.orders,
          averageOrderValue: totalRevenue.orders > 0 ? roundAmount(totalRevenue.revenue / totalRevenue.orders) : 0,
          period: `${days} days`
        }
      }
    });
  } catch (error) {
    console.error('Daily sales analytics error:', error);
    res.status(500).json({ error: 'Failed to fetch daily sales analytics' });
  }
};

/**
 * Get item performance analytics
 */
exports.getItemPerformance = async (req, res) => {
  try {
    const { days = 30 } = req.query;
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - parseInt(days));

    const ordersSnapshot = await db
      .collection('orders')
      .where('eateryId', '==', req.user.eateryId)
      .where('createdAt', '>=', startDate)
      .where('status', '==', 'completed')
      .get();

    const itemStats = {};
    
    ordersSnapshot.docs.forEach(doc => {
      const order = doc.data();
      order.items.forEach(item => {
        if (!itemStats[item.menuItemId]) {
          itemStats[item.menuItemId] = {
            id: item.menuItemId,
            name: item.name,
            quantitySold: 0,
            revenue: 0,
            orders: 0
          };
        }
        
        itemStats[item.menuItemId].quantitySold += item.quantity;
        itemStats[item.menuItemId].revenue += item.subtotal;
        itemStats[item.menuItemId].orders += 1;
      });
    });

    const performanceData = Object.values(itemStats)
      .sort((a, b) => b.revenue - a.revenue)
      .map(item => ({
        ...item,
        revenue: roundAmount(item.revenue),
        averagePrice: item.quantitySold > 0 ? roundAmount(item.revenue / item.quantitySold) : 0
      }));

    res.json({
      data: {
        items: performanceData,
        topSelling: performanceData.slice(0, 10),
        leastSelling: performanceData.slice(-10).reverse(),
        summary: {
          totalItems: performanceData.length,
          totalRevenue: roundAmount(performanceData.reduce((sum, item) => sum + item.revenue, 0)),
          totalQuantity: performanceData.reduce((sum, item) => sum + item.quantitySold, 0)
        }
      }
    });
  } catch (error) {
    console.error('Item performance error:', error);
    res.status(500).json({ error: 'Failed to fetch item performance' });
  }
};

/**
 * Get summary statistics
 */
exports.getSummaryStats = async (req, res) => {
  try {
    const today = new Date();
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    const weekStart = new Date(today);
    weekStart.setDate(today.getDate() - 7);
    const monthStart = new Date(today.getFullYear(), today.getMonth(), 1);

    // Today's orders
    const todayOrders = await db
      .collection('orders')
      .where('eateryId', '==', req.user.eateryId)
      .where('createdAt', '>=', todayStart)
      .where('status', '==', 'completed')
      .get();

    // This week's orders
    const weekOrders = await db
      .collection('orders')
      .where('eateryId', '==', req.user.eateryId)
      .where('createdAt', '>=', weekStart)
      .where('status', '==', 'completed')
      .get();

    // This month's orders
    const monthOrders = await db
      .collection('orders')
      .where('eateryId', '==', req.user.eateryId)
      .where('createdAt', '>=', monthStart)
      .where('status', '==', 'completed')
      .get();

    // Calculate stats
    const calculateStats = (snapshot) => {
      const orders = snapshot.docs.map(doc => doc.data());
      return {
        revenue: roundAmount(orders.reduce((sum, order) => sum + order.totalAmount, 0)),
        orders: orders.length,
        averageOrderValue: orders.length > 0 ? 
          roundAmount(orders.reduce((sum, order) => sum + order.totalAmount, 0) / orders.length) : 0
      };
    };

    const todayStats = calculateStats(todayOrders);
    const weekStats = calculateStats(weekOrders);
    const monthStats = calculateStats(monthOrders);

    // Get menu items count
    const menuSnapshot = await db
      .collection('menu_items')
      .where('eateryId', '==', req.user.eateryId)
      .where('isAvailable', '==', true)
      .get();

    // Get low stock count
    const lowStockSnapshot = await db
      .collection('inventory')
      .where('eateryId', '==', req.user.eateryId)
      .where('currentStock', '<=', db.FieldValue.increment('minStock'))
      .get();

    res.json({
      data: {
        today: todayStats,
        week: weekStats,
        month: monthStats,
        menuItems: menuSnapshot.size,
        lowStockItems: lowStockSnapshot.size,
        revenueGrowth: {
          daily: calculatePercentageChange(todayStats.revenue, weekStats.revenue / 7),
          weekly: calculatePercentageChange(weekStats.revenue, monthStats.revenue / 4.3)
        }
      }
    });
  } catch (error) {
    console.error('Summary stats error:', error);
    res.status(500).json({ error: 'Failed to fetch summary statistics' });
  }
};

/**
 * Get demand forecast from ML service
 */
exports.getDemandForecast = async (req, res) => {
  try {
    const { days = 7 } = req.query;
    
    // Call ML service
    const mlServiceUrl = process.env.ML_SERVICE_URL || 'http://localhost:8000';
    const response = await axios.get(`${mlServiceUrl}/api/forecast/demand`, {
      params: {
        eateryId: req.user.eateryId,
        days: parseInt(days)
      }
    });

    res.json(response.data);
  } catch (error) {
    console.error('Demand forecast error:', error);
    
    // Return mock data if ML service is unavailable
    const mockData = [];
    for (let i = 1; i <= parseInt(days || 7); i++) {
      mockData.push({
        day: i,
        predictedDemand: 20 + (i * 3),
        confidence: 0.85
      });
    }
    
    res.json({
      data: mockData,
      note: 'Mock forecast - ML service unavailable'
    });
  }
};

/**
 * Get sales forecast from ML service
 */
exports.getSalesForecast = async (req, res) => {
  try {
    const { days = 7 } = req.query;
    
    // Call ML service
    const mlServiceUrl = process.env.ML_SERVICE_URL || 'http://localhost:8000';
    const response = await axios.get(`${mlServiceUrl}/api/forecast/sales`, {
      params: {
        eateryId: req.user.eateryId,
        days: parseInt(days)
      }
    });

    res.json(response.data);
  } catch (error) {
    console.error('Sales forecast error:', error);
    
    // Return mock data if ML service is unavailable
    const mockData = [];
    for (let i = 1; i <= parseInt(days || 7); i++) {
      mockData.push({
        day: i,
        predictedSales: 2000 + (i * 100),
        confidence: 0.82
      });
    }
    
    res.json({
      data: mockData,
      note: 'Mock forecast - ML service unavailable'
    });
  }
};

/**
 * Get recommendations from ML service
 */
exports.getRecommendations = async (req, res) => {
  try {
    // Call ML service
    const mlServiceUrl = process.env.ML_SERVICE_URL || 'http://localhost:8000';
    const response = await axios.get(`${mlServiceUrl}/api/recommendations`, {
      params: {
        eateryId: req.user.eateryId
      }
    });

    res.json(response.data);
  } catch (error) {
    console.error('Recommendations error:', error);
    
    // Return mock data if ML service is unavailable
    res.json({
      data: {
        promoteItems: [
          { id: '1', name: 'Burger Special', reason: 'High profit potential', expectedIncrease: '25%' },
          { id: '2', name: 'Fried Rice', reason: 'Strong customer demand', expectedIncrease: '18%' }
        ],
        removeItems: [
          { id: '5', name: 'Rare Dish', reason: 'Low sales', wasteReduction: '40%' }
        ],
        optimizeInventory: [
          { ingredient: 'Tomatoes', action: 'Reduce order by 20%', reason: 'Excess stock' },
          { ingredient: 'Chicken', action: 'Increase order by 15%', reason: 'High demand' }
        ]
      },
      note: 'Mock recommendations - ML service unavailable'
    });
  }
};

/**
 * Get peak hours analysis
 */
exports.getPeakHours = async (req, res) => {
  try {
    const { days = 30 } = req.query;
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - parseInt(days));

    const ordersSnapshot = await db
      .collection('orders')
      .where('eateryId', '==', req.user.eateryId)
      .where('createdAt', '>=', startDate)
      .where('status', '==', 'completed')
      .get();

    const hourlyData = {};
    
    ordersSnapshot.docs.forEach(doc => {
      const order = doc.data();
      const hour = new Date(order.createdAt.toDate ? order.createdAt.toDate() : order.createdAt).getHours();
      
      if (!hourlyData[hour]) {
        hourlyData[hour] = {
          hour,
          orders: 0,
          revenue: 0
        };
      }
      
      hourlyData[hour].orders += 1;
      hourlyData[hour].revenue += order.totalAmount;
    });

    const peakHours = Object.values(hourlyData)
      .sort((a, b) => b.revenue - a.revenue)
      .map(hour => ({
        ...hour,
        revenue: roundAmount(hour.revenue),
        averageOrderValue: hour.orders > 0 ? roundAmount(hour.revenue / hour.orders) : 0
      }));

    res.json({
      data: {
        peakHours,
        busiestHour: peakHours[0]?.hour || 12,
        slowestHour: peakHours[peakHours.length - 1]?.hour || 3
      }
    });
  } catch (error) {
    console.error('Peak hours error:', error);
    res.status(500).json({ error: 'Failed to fetch peak hours analysis' });
  }
};
