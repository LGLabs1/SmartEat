const axios = require('axios');
const { db } = require('../config/firebase');

const OLLAMA_BASE_URL = process.env.OLLAMA_URL || 'http://localhost:11434';
const MODEL_NAME = process.env.OLLAMA_MODEL || 'llama3.2';

// Simple in-memory cache for recent queries (TTL: 5 minutes)
const responseCache = new Map();
const CACHE_TTL = 5 * 60 * 1000;

const getCacheKey = (eateryId, message) => `${eateryId}:${message.toLowerCase().trim()}`;

const getFromCache = (key) => {
  const cached = responseCache.get(key);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) {
    return cached.data;
  }
  responseCache.delete(key);
  return null;
};

const setCache = (key, data) => {
  responseCache.set(key, { data, timestamp: Date.now() });
};

// Helper to get eateryId
const getEateryId = async (req) => {
  if (req.body?.eateryId) return req.body.eateryId;
  if (req.query?.eateryId) return req.query.eateryId;
  if (req.headers?.['x-eatery-id']) return req.headers['x-eatery-id'];
  if (req.user?.eateryId) return req.user.eateryId;
  if (req.user?.uid) {
    try {
      const doc = await db.collection('users').doc(req.user.uid).get();
      if (doc.exists) {
        return doc.data().eateryId;
      }
    } catch (e) {
      console.error('Error fetching user eateryId:', e);
    }
  }
  return null;
};

// OPTIMIZED: Fetch restaurant data with aggressive limits and caching
const fetchRestaurantContext = async (eateryId) => {
  if (!eateryId) {
    return `\n\n--- RESTAURANT CURRENT DATA ---\nNo data available. Cannot authenticate restaurant.`;
  }

  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    const last7DaysDate = new Date();
    last7DaysDate.setDate(last7DaysDate.getDate() - 7);

    // OPTIMIZATION: Parallel queries with aggressive limits
    const [menuSnapshot, ordersSnapshot, inventorySnapshot] = await Promise.all([
      db.collection('eateries').doc(eateryId).collection('menu')
        .select('name', 'price')
        .limit(20)
        .get(),
      db.collection('eateries').doc(eateryId).collection('orders')
        .where('createdAt', '>=', last7DaysDate)
        .where('status', '==', 'completed')
        .select('totalAmount', 'createdAt', 'items')
        .limit(100)
        .get(),
      db.collection('eateries').doc(eateryId).collection('inventory')
        .select('name', 'currentStock', 'minStock')
        .limit(30)
        .get()
    ]);

    const menuItems = menuSnapshot.docs.map(d => d.data().name).join(', ') || '(No menu items)';
    
    let todayRevenue = 0;
    let todayOrders = 0;
    let weekRevenue = 0;
    let weekOrders = 0;
    let highestSale = 0;
    const itemSales = {};
    
    // OPTIMIZATION: Single pass through orders
    ordersSnapshot.docs.forEach(d => {
      const order = d.data();
      const amount = order.totalAmount || 0;
      
      weekRevenue += amount;
      weekOrders++;
      
      if (amount > highestSale) {
        highestSale = amount;
      }
      
      let orderDate = null;
      if (order.createdAt?.toDate) {
        orderDate = order.createdAt.toDate();
      } else if (order.createdAt instanceof Date) {
        orderDate = order.createdAt;
      } else if (typeof order.createdAt === 'number') {
        orderDate = new Date(order.createdAt);
      }
      
      if (orderDate && orderDate >= today) {
        todayRevenue += amount;
        todayOrders++;
      }
      
      (order.items || []).forEach(item => {
        const name = item.name || 'Unknown';
        itemSales[name] = (itemSales[name] || 0) + (item.quantity || 1);
      });
    });
    
    const topItems = Object.entries(itemSales)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([name, qty]) => `${name} (${qty})`)
      .join(', ') || '(No sales)';
    
    const lowStock = inventorySnapshot.docs
      .filter(d => {
        const data = d.data();
        return (data.currentStock || 0) <= (data.minStock || 0);
      })
      .map(d => d.data().name)
      .slice(0, 5)
      .join(', ') || '(None)';

    return `\n\n--- RESTAURANT CURRENT DATA (Last 7 Days) ---
Today's Orders: ${todayOrders}
Today's Revenue: ₱${todayRevenue.toFixed(2)}
Week's Orders: ${weekOrders}
Week's Revenue: ₱${weekRevenue.toFixed(2)}
Highest Sale: ₱${highestSale.toFixed(2)}
Top Items: ${topItems}
Low Stock Items: ${lowStock}
Sample Menu: ${menuItems}
---------------------------------------------
IMPORTANT: Use ONLY this data. Do NOT invent information.`;
  } catch (e) {
    console.error('Error fetching context:', e);
    return `\n\n--- RESTAURANT CURRENT DATA ---\nError loading data: ${e.message}`;
  }
};

// SYSTEM PROMPT - More specific and strict about data
const SYSTEM_PROMPT = `You are SmartBot, AI assistant for SmartEat Restaurant Management System.

CRITICAL RULES:
1. ANSWER HONESTLY: Only use data provided in the "RESTAURANT CURRENT DATA" section
2. IF DATA NOT PROVIDED: Say "I don't have that information available"
3. DO NOT GUESS OR INVENT: Never make up sales, inventory, or customer data
4. SYSTEM HELP: You can explain SmartEat features and navigation
5. BE BRIEF: Keep responses to 2-3 sentences max`;

/**
 * OPTIMIZED: Generate chat response using Ollama with caching and faster model
 */
exports.chat = async (req, res) => {
  try {
    const { message, history = [] } = req.body;
    const eateryId = await getEateryId(req);

    if (!message || typeof message !== 'string') {
      return res.status(400).json({ error: 'Valid message is required' });
    }

    // OPTIMIZATION: Check cache first
    if (eateryId) {
      const cacheKey = getCacheKey(eateryId, message);
      const cached = getFromCache(cacheKey);
      if (cached) {
        console.log('✓ Cache hit for message:', message.substring(0, 50));
        return res.json({
          success: true,
          response: cached,
          cached: true,
          model: MODEL_NAME,
          timestamp: new Date().toISOString()
        });
      }
    }

    // Fetch context data
    const contextData = await fetchRestaurantContext(eateryId);

    // Build messages
    const messages = [
      { role: 'system', content: SYSTEM_PROMPT + contextData }
    ];

    // Add limited history (last 5 turns for faster context)
    const recentHistory = history.slice(-5);
    messages.push(...recentHistory);
    messages.push({ role: 'user', content: message });

    // OPTIMIZATION: Reduced timeout, fewer tokens for faster generation
    console.log('Calling Ollama with', messages.length, 'messages');
    const response = await axios.post(`${OLLAMA_BASE_URL}/api/chat`, {
      model: MODEL_NAME,
      messages: messages,
      stream: false,
      options: {
        temperature: 0.3, // Lower temperature = more consistent
        num_predict: 150, // Reduced from 200 for faster response
        top_p: 0.9,
        top_k: 40,
      }
    }, {
      timeout: 60000 // OPTIMIZATION: Reduced from 300s to 60s
    });

    const assistantMessage = (response.data.message?.content || '').trim() ||
      'I could not generate a response. Please try again.';

    // Cache the response
    if (eateryId) {
      const cacheKey = getCacheKey(eateryId, message);
      setCache(cacheKey, assistantMessage);
    }

    res.json({
      success: true,
      response: assistantMessage,
      model: MODEL_NAME,
      cached: false,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Chatbot error:', error.message);
    
    if (error.code === 'ECONNREFUSED') {
      return res.status(503).json({
        error: 'AI service unavailable',
        message: 'Ollama is not running. Start it with: ollama serve'
      });
    }

    if (error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT') {
      return res.status(504).json({
        error: 'AI request timed out',
        message: 'The AI model is responding slowly. Please try again.'
      });
    }

    res.status(500).json({
      error: 'Failed to generate response',
      message: error.message
    });
  }
};

/**
 * Check Ollama status
 */
exports.getStatus = async (req, res) => {
  try {
    const response = await axios.get(`${OLLAMA_BASE_URL}/api/tags`, {
      timeout: 5000
    });
    
    const models = response.data.models || [];
    const hasModel = models.length > 0;

    res.json({
      status: 'online',
      ollamaRunning: true,
      hasModel: hasModel,
      availableModels: models.map(m => m.name),
      baseUrl: OLLAMA_BASE_URL
    });
  } catch (error) {
    console.error('Ollama status check failed:', error.message);
    res.status(503).json({
      status: 'offline',
      ollamaRunning: false,
      hasModel: false,
      message: 'Ollama is not running. Start it with: ollama serve',
      error: error.message
    });
  }
};

/**
 * OPTIMIZED: Get quick insights about eatery data - NOW WITH PROPER EATERY DATA
 */
exports.getInsights = async (req, res) => {
  try {
    const eateryId = await getEateryId(req);

    if (!eateryId) {
      return res.status(400).json({ error: 'Eatery ID required' });
    }

    console.log('Fetching insights for eatery:', eateryId);

    const last7Days = new Date();
    last7Days.setDate(last7Days.getDate() - 7);

    // OPTIMIZATION: Fetch only needed fields with limits
    const ordersSnapshot = await db
      .collection('eateries')
      .doc(eateryId)
      .collection('orders')
      .where('createdAt', '>=', last7Days)
      .where('status', '==', 'completed')
      .select('totalAmount', 'createdAt')
      .limit(100)
      .get();

    let totalOrders = 0;
    let totalRevenue = 0;
    const dailyOrders = {};

    ordersSnapshot.docs.forEach(doc => {
      const order = doc.data();
      totalOrders++;
      totalRevenue += order.totalAmount || 0;
      
      const date = order.createdAt?.toDate ? 
        order.createdAt.toDate().toISOString().split('T')[0] : 
        new Date().toISOString().split('T')[0];
      
      dailyOrders[date] = (dailyOrders[date] || 0) + 1;
    });

    const avgDailyOrders = Object.keys(dailyOrders).length > 0 ?
      totalOrders / Object.keys(dailyOrders).length : 0;

    // OPTIMIZATION: Use simpler, faster prompt for insights
    const insightsPrompt = `Give 2-3 brief insights on this restaurant's performance:
- Orders (7 days): ${totalOrders}
- Revenue: ₱${totalRevenue.toFixed(2)}
- Avg/day: ${avgDailyOrders.toFixed(1)} orders
- Active days: ${Object.keys(dailyOrders).length}

Be brief and actionable (1-2 sentences each).`;

    console.log('Calling Ollama for insights...');
    const aiResponse = await axios.post(`${OLLAMA_BASE_URL}/api/chat`, {
      model: MODEL_NAME,
      messages: [
        {
          role: 'user',
          content: insightsPrompt
        }
      ],
      stream: false,
      options: {
        temperature: 0.4,
        num_predict: 120,
        top_p: 0.9,
        top_k: 40
      }
    }, {
      timeout: 60000
    });

    const summary = (
      aiResponse.data?.message?.content ||
      aiResponse.data?.response ||
      aiResponse.data?.output ||
      aiResponse.data?.results?.[0]?.content ||
      ''
    ).toString().trim() ||
      'Unable to generate insights at this time.';

    res.json({
      success: true,
      data: {
        totalOrders,
        totalRevenue: Math.round(totalRevenue * 100) / 100,
        avgDailyOrders: Math.round(avgDailyOrders * 10) / 10,
        activeDays: Object.keys(dailyOrders).length,
        aiSummary: summary
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Insights error:', error.response?.data || error.message || error);
    
    if (error.code === 'ECONNREFUSED') {
      return res.status(503).json({
        error: 'AI service unavailable',
        message: 'Ollama is not running'
      });
    }

    if (error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT') {
      return res.status(504).json({
        error: 'AI request timed out',
        message: 'The AI model is responding slowly. Please try again.'
      });
    }

    return res.status(500).json({
      error: 'Failed to generate insights',
      message: process.env.NODE_ENV === 'development'
        ? (error.response?.data || error.message || 'Server error')
        : 'Server error'
    });
  }
};

module.exports = exports;
