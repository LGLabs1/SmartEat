const axios = require('axios');
const { db } = require('../config/firebase');

const OLLAMA_BASE_URL = process.env.OLLAMA_URL || 'http://localhost:11434';
const MODEL_NAME = process.env.OLLAMA_MODEL || 'llama3.2';

const responseCache = new Map();
const CACHE_TTL = 5 * 60 * 1000;

const getCacheKey = (eateryId, message, context) => {
  const ctxSnippet = context
    ? context.substring(0, 120).replace(/\s+/g, '')
    : 'nocontext';
  return `${eateryId}:${ctxSnippet}:${message.toLowerCase().trim()}`;
};

const getFromCache = (key) => {
  const cached = responseCache.get(key);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) return cached.data;
  responseCache.delete(key);
  return null;
};

const setCache = (key, data) =>
  responseCache.set(key, { data, timestamp: Date.now() });

const getEateryId = async (req) => {
  if (req.body?.eateryId)       return req.body.eateryId;
  if (req.query?.eateryId)      return req.query.eateryId;
  if (req.headers?.['x-eatery-id']) return req.headers['x-eatery-id'];
  if (req.user?.eateryId)       return req.user.eateryId;
  if (req.user?.uid) {
    try {
      const doc = await db.collection('users').doc(req.user.uid).get();
      if (doc.exists) return doc.data().eateryId;
    } catch (e) {
      console.error('Error fetching user eateryId:', e);
    }
  }
  return null;
};

async function getDocsForEatery(eateryId, collectionName) {
  if (!eateryId) return [];
  try {
    const subSnap = await db
      .collection('eateries')
      .doc(eateryId)
      .collection(collectionName)
      .get();
    if (!subSnap.empty) return subSnap.docs;
  } catch (e) {
    console.warn(`[Sage] Subcollection fetch for ${collectionName} failed:`, e.message);
  }

  try {
    const topSnap = await db
      .collection(collectionName)
      .where('eateryId', '==', eateryId)
      .get();
    return topSnap.docs;
  } catch (e) {
    console.error(`[Sage] Top-level fetch for ${collectionName} failed:`, e.message);
    return [];
  }
}

function parseDate(val) {
  if (!val) return null;
  if (typeof val.toDate === 'function') return val.toDate();
  if (val instanceof Date) return val;
  if (typeof val === 'number') return new Date(val);
  if (typeof val === 'string') {
    const d = new Date(val);
    return isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function isCompletedOrder(order) {
  const status = String(order.status || '').toLowerCase().trim();
  return status === 'completed' || status === 'paid' || status === 'delivered' || status === 'done';
}

const SYSTEM_PROMPT = `You are Sage, the intelligent restaurant business assistant for SmartEat.

STRICT DIRECTIVES AGAINST HALLUCINATION:
1. ONLY use exact numbers, item names, and facts from the SMARTEAT BUSINESS SNAPSHOT section.
2. NEVER invent menu items, dishes, sales numbers, percentages, or order counts that do not appear in the snapshot.
3. If a metric or specific item is not available in the snapshot, say: "Based on the current business snapshot available, I don't see those specific figures recorded yet..."
4. NEVER say "check your records" or "consult your data" — interpret the provided snapshot directly.
5. Use ₱ for peso amounts.`;

exports.fetchRestaurantContext = async (eateryId) => {
  if (!eateryId) {
    return `\n\n--- RESTAURANT CURRENT DATA ---\nNo data available. Cannot authenticate restaurant.`;
  }

  try {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const last7DaysDate = new Date(); last7DaysDate.setDate(last7DaysDate.getDate() - 7);

    const [menuDocs, orderDocs, inventoryDocs] = await Promise.all([
      getDocsForEatery(eateryId, 'menu'),
      getDocsForEatery(eateryId, 'orders'),
      getDocsForEatery(eateryId, 'inventory'),
    ]);

    const menuItems = menuDocs.map(d => (d.data() || {}).name).filter(Boolean).slice(0, 20).join(', ') || '(No menu items)';

    let todayRevenue = 0, todayOrders = 0, weekRevenue = 0, weekOrders = 0, highestSale = 0;
    const itemSales = {};

    orderDocs.forEach(d => {
      const order = d.data() || {};
      if (!isCompletedOrder(order)) return;
      const amount = Number(order.totalAmount || order.total || 0);
      const orderDate = parseDate(order.createdAt);

      if (orderDate && orderDate >= last7DaysDate) {
        weekRevenue += amount;
        weekOrders++;
        if (amount > highestSale) highestSale = amount;

        if (orderDate >= today) {
          todayRevenue += amount;
          todayOrders++;
        }

        (order.items || []).forEach(item => {
          const name = item.name || item.menuItemName || 'Unknown';
          const qty = Number(item.quantity || item.qty || 1);
          itemSales[name] = (itemSales[name] || 0) + qty;
        });
      }
    });

    const topItems = Object.entries(itemSales)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([name, qty]) => `${name} (${qty})`)
      .join(', ') || '(No sales)';

    const lowStock = inventoryDocs
      .map(d => d.data() || {})
      .filter(d => Number(d.currentStock || 0) <= Number(d.minStock || 0))
      .map(d => d.name)
      .filter(Boolean)
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

exports.chat = async (req, res) => {
  try {
    const { message, history = [], context } = req.body;
    const eateryId = await getEateryId(req);

    if (!message || typeof message !== 'string') {
      return res.status(400).json({ error: 'Valid message is required' });
    }

    if (eateryId) {
      const cached = getFromCache(getCacheKey(eateryId, message, context));
      if (cached) {
        return res.json({ success: true, response: cached, cached: true, model: MODEL_NAME, timestamp: new Date().toISOString() });
      }
    }

    let snapshotBlock;
    if (context && typeof context === 'string' && context.length > 20) {
      snapshotBlock = context;
    } else {
      snapshotBlock = await exports.fetchRestaurantContext(eateryId);
    }

    const systemContent = `${SYSTEM_PROMPT}\n\n${snapshotBlock}`;
    const recentHistory = history.slice(-6);
    const messages = [
      { role: 'system', content: systemContent },
      ...recentHistory,
      { role: 'user', content: message },
    ];

    const ollamaRes = await axios.post(`${OLLAMA_BASE_URL}/api/chat`, {
      model: MODEL_NAME,
      messages,
      stream: false,
      options: {
        temperature: 0.3,
        num_predict: 250,
        top_p: 0.9,
        top_k: 40,
      },
    }, { timeout: 90000 });

    const reply = (ollamaRes.data.message?.content || '').trim() ||
      'I could not generate a response. Please try again.';

    if (eateryId) setCache(getCacheKey(eateryId, message, context), reply);

    res.json({ success: true, response: reply, model: MODEL_NAME, cached: false, timestamp: new Date().toISOString() });
  } catch (error) {
    console.error('[Sage] Chat error:', error.message);
    res.status(500).json({ error: 'Failed to generate response', message: error.message });
  }
};
