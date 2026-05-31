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
 * Get order count forecast using statistical model (day-of-week moving averages)
 */
exports.getOrderCountForecast = async (req, res) => {
  try {
    const { days = 7 } = req.query;
    const forecastDays = parseInt(days);
    const eateryId = req.user.eateryId;

    // Fetch last 12 weeks of order data for pattern analysis
    const weeksToAnalyze = 12;
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - (weeksToAnalyze * 7));

    // Use simpler query to avoid composite index requirements
    const ordersSnapshot = await db
      .collection('orders')
      .where('eateryId', '==', eateryId)
      .where('createdAt', '>=', startDate)
      .orderBy('createdAt', 'asc')
      .get();

    // Aggregate orders by date and day of week
    const dailyOrders = {};
    const dayOfWeekCounts = { 0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: [] }; // Sun=0 to Sat=6

    ordersSnapshot.docs.forEach(doc => {
      const order = doc.data();
      
      // Filter out cancelled/voided orders only (keep completed, pending, preparing, etc.)
      const status = order.status?.toString().toLowerCase();
      if (status === 'cancelled' || status === 'void' || status === 'voided') {
        return;
      }
      
      const date = order.createdAt?.toDate ? order.createdAt.toDate() : new Date(order.createdAt);
      if (isNaN(date.getTime())) return; // Skip invalid dates
      
      const dateKey = date.toISOString().split('T')[0];
      const dayOfWeek = date.getDay();

      if (!dailyOrders[dateKey]) {
        dailyOrders[dateKey] = { count: 0, dayOfWeek, totalRevenue: 0 };
      }
      dailyOrders[dateKey].count += 1;
      dailyOrders[dateKey].totalRevenue += (order.totalAmount || 0);
    });

    // Calculate average orders for each day of the week (skip days with 0 orders)
    Object.values(dailyOrders).forEach(day => {
      if (day.count > 0) {
        dayOfWeekCounts[day.dayOfWeek].push(day.count);
      }
    });

    const dayOfWeekAverages = {};
    const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    for (let dow = 0; dow <= 6; dow++) {
      const counts = dayOfWeekCounts[dow];
      if (counts.length > 0) {
        // Calculate average and apply trend adjustment
        const avg = counts.reduce((a, b) => a + b, 0) / counts.length;
        // Calculate standard deviation for confidence
        const variance = counts.reduce((sum, val) => sum + Math.pow(val - avg, 2), 0) / counts.length;
        const stdDev = Math.sqrt(variance);
        dayOfWeekAverages[dow] = {
          average: Math.round(avg),
          stdDev: Math.round(stdDev),
          sampleSize: counts.length
        };
      } else {
        // Fallback if no data for this day
        dayOfWeekAverages[dow] = { average: 15, stdDev: 5, sampleSize: 0 };
      }
    }

    // Calculate overall trend (are orders increasing or decreasing?)
    const dates = Object.keys(dailyOrders).sort();
    let trendFactor = 1.0;
    if (dates.length >= 14) {
      const firstWeekAvg = dates.slice(0, 7).reduce((sum, d) => sum + dailyOrders[d].count, 0) / 7;
      const lastWeekAvg = dates.slice(-7).reduce((sum, d) => sum + dailyOrders[d].count, 0) / 7;
      if (firstWeekAvg > 0) {
        trendFactor = lastWeekAvg / firstWeekAvg;
        trendFactor = Math.max(0.8, Math.min(1.2, trendFactor)); // Cap trend between -20% and +20%
      }
    }

    // Generate forecast for requested days
    const now = new Date();
    const forecast = [];

    for (let i = 1; i <= forecastDays; i++) {
      const forecastDate = new Date(now);
      forecastDate.setDate(forecastDate.getDate() + i);
      const dayOfWeek = forecastDate.getDay();
      const dayAvg = dayOfWeekAverages[dayOfWeek];

      // Apply trend factor
      const predictedOrders = Math.round(dayAvg.average * trendFactor);
      const confidence = Math.min(0.95, Math.max(0.5, 1 - (dayAvg.stdDev / (dayAvg.average || 1))));

      forecast.push({
        day: i,
        date: forecastDate.toISOString().split('T')[0],
        dayName: dayNames[dayOfWeek],
        predictedOrders: Math.max(0, predictedOrders),
        confidence: Math.round(confidence * 100) / 100,
        sampleSize: dayAvg.sampleSize,
        isWeekend: dayOfWeek === 0 || dayOfWeek === 6
      });
    }

    res.json({
      data: forecast,
      model: 'statistical_day_of_week',
      trendFactor: Math.round(trendFactor * 100) / 100,
      historicalWeeksAnalyzed: weeksToAnalyze,
      note: `Based on ${weeksToAnalyze} weeks of historical order data`
    });
  } catch (error) {
    console.error('Order count forecast error:', error);
    res.status(500).json({ error: 'Failed to generate order count forecast' });
  }
};

/**
 * Get sales forecast using statistical model (day-of-week moving averages)
 */
exports.getSalesForecast = async (req, res) => {
  try {
    const { days = 7 } = req.query;
    const forecastDays = parseInt(days);
    const eateryId = req.user.eateryId;

    // Fetch last 12 weeks of order data
    const weeksToAnalyze = 12;
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - (weeksToAnalyze * 7));

    const ordersSnapshot = await db
      .collection('orders')
      .where('eateryId', '==', eateryId)
      .where('createdAt', '>=', startDate)
      .orderBy('createdAt', 'asc')
      .get();

    // Aggregate daily revenue by day of week
    const dailyRevenue = {};
    const dayOfWeekRevenue = { 0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: [] };

    ordersSnapshot.docs.forEach(doc => {
      const order = doc.data();
      
      // Filter out cancelled/voided orders only (keep completed, pending, preparing, etc.)
      const status = order.status?.toString().toLowerCase();
      if (status === 'cancelled' || status === 'void' || status === 'voided') {
        return;
      }
      
      const date = order.createdAt?.toDate ? order.createdAt.toDate() : new Date(order.createdAt);
      if (isNaN(date.getTime())) return;
      
      const dateKey = date.toISOString().split('T')[0];
      const dayOfWeek = date.getDay();
      const amount = order.totalAmount || 0;

      if (!dailyRevenue[dateKey]) {
        dailyRevenue[dateKey] = { revenue: 0, dayOfWeek };
      }
      dailyRevenue[dateKey].revenue += amount;
    });

    // Calculate average revenue for each day of week (skip days with 0 revenue)
    Object.values(dailyRevenue).forEach(day => {
      if (day.revenue > 0) {
        dayOfWeekRevenue[day.dayOfWeek].push(day.revenue);
      }
    });

    const dayOfWeekAverages = {};
    const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    for (let dow = 0; dow <= 6; dow++) {
      const revenues = dayOfWeekRevenue[dow];
      if (revenues.length > 0) {
        const avg = revenues.reduce((a, b) => a + b, 0) / revenues.length;
        const variance = revenues.reduce((sum, val) => sum + Math.pow(val - avg, 2), 0) / revenues.length;
        const stdDev = Math.sqrt(variance);
        dayOfWeekAverages[dow] = {
          average: Math.round(avg),
          stdDev: Math.round(stdDev),
          sampleSize: revenues.length
        };
      } else {
        dayOfWeekAverages[dow] = { average: 5000, stdDev: 1000, sampleSize: 0 };
      }
    }

    // Calculate trend factor
    const dates = Object.keys(dailyRevenue).sort();
    let trendFactor = 1.0;
    if (dates.length >= 14) {
      const firstWeekAvg = dates.slice(0, 7).reduce((sum, d) => sum + dailyRevenue[d].revenue, 0) / 7;
      const lastWeekAvg = dates.slice(-7).reduce((sum, d) => sum + dailyRevenue[d].revenue, 0) / 7;
      if (firstWeekAvg > 0) {
        trendFactor = lastWeekAvg / firstWeekAvg;
        trendFactor = Math.max(0.8, Math.min(1.2, trendFactor));
      }
    }

    // Generate forecast
    const now = new Date();
    const forecast = [];

    for (let i = 1; i <= forecastDays; i++) {
      const forecastDate = new Date(now);
      forecastDate.setDate(forecastDate.getDate() + i);
      const dayOfWeek = forecastDate.getDay();
      const dayAvg = dayOfWeekAverages[dayOfWeek];

      const predictedRevenue = Math.round(dayAvg.average * trendFactor);
      const confidence = Math.min(0.95, Math.max(0.5, 1 - (dayAvg.stdDev / (dayAvg.average || 1))));

      forecast.push({
        day: i,
        date: forecastDate.toISOString().split('T')[0],
        dayName: dayNames[dayOfWeek],
        predictedRevenue: Math.max(0, predictedRevenue),
        confidence: Math.round(confidence * 100) / 100,
        sampleSize: dayAvg.sampleSize,
        isWeekend: dayOfWeek === 0 || dayOfWeek === 6
      });
    }

    res.json({
      data: forecast,
      model: 'statistical_day_of_week_revenue',
      trendFactor: Math.round(trendFactor * 100) / 100,
      historicalWeeksAnalyzed: weeksToAnalyze,
      note: `Based on ${weeksToAnalyze} weeks of historical revenue data`
    });
  } catch (error) {
    console.error('Sales forecast error:', error);
    res.status(500).json({ error: 'Failed to generate sales forecast' });
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
