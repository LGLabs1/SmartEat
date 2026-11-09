const axios = require('axios');
const { db } = require('../config/firebase');

const OLLAMA_BASE_URL = process.env.OLLAMA_URL || 'http://localhost:11434';
const MODEL_NAME = process.env.OLLAMA_MODEL || 'llama3.2';

// Live demo mode: disable Sage/Ollama-backed chatbot without changing other backend features.
const SAGE_DISABLED =
  String(process.env.SAGE_DISABLED || process.env.SAGE_DEMO_DISABLED || 'false').toLowerCase() === 'true';
const SAGE_DISABLED_MESSAGE =
  process.env.SAGE_DISABLED_MESSAGE ||
  'Sage is disabled in this demo. Analytics, inventory, finance, and other SmartEat features remain available.';

function sageDisabledResponse(streaming = false) {
  if (streaming) {
    return { type: 'demo_disabled', error: 'sage_disabled', message: SAGE_DISABLED_MESSAGE };
  }
  return { success: false, error: 'sage_disabled', message: SAGE_DISABLED_MESSAGE, demoDisabled: true };
}

// Tunable inference settings. Defaults preserve current behaviour, so tuning
// needs only an env change (e.g. OLLAMA_NUM_PREDICT=120) and no code edit.
const NUM_PREDICT = parseInt(process.env.OLLAMA_NUM_PREDICT, 10) || 250;
const NUM_CTX = parseInt(process.env.OLLAMA_NUM_CTX, 10) || 4096;
// Keep the model resident between questions so repeat asks skip cold-start.
const KEEP_ALIVE = process.env.OLLAMA_KEEP_ALIVE || '30m';
const OLLAMA_TIMEOUT = parseInt(process.env.OLLAMA_TIMEOUT_MS, 10) || 120000;

// Shared Ollama request options (used by both the blocking and streaming paths).
const ollamaOptions = () => ({
  temperature: 0.3,
  num_predict: NUM_PREDICT,
  // Ollama defaults to 2048 context tokens; the business snapshot plus history
  // can exceed that, which makes the model fail or stall.
  num_ctx: NUM_CTX,
  top_p: 0.9,
  top_k: 40,
});

// ---------------------------------------------------------------------------
// Cache  (5-minute TTL, keyed by eateryId + intent + contextSnippet + message)
// ---------------------------------------------------------------------------
const responseCache = new Map();
const CACHE_TTL = 5 * 60 * 1000;
// Bound the cache so a long-running server cannot grow it without limit.
const CACHE_MAX_ENTRIES = 500;

// Extract the intent label from the snapshot block so identical messages
// with different intents never collide in the cache.
const extractIntent = (context) => {
  if (!context) return 'general';
  const match = context.match(/^Intent\s*:\s*(.+)$/m);
  return match ? match[1].trim().toLowerCase() : 'general';
};

const getCacheKey = (eateryId, message, context) => {
  const intent = extractIntent(context);
  const ctxSnippet = context
    ? context.substring(0, 120).replace(/\s+/g, '')
    : 'nocontext';
  // Normalise the message so casing/whitespace variants share a cache entry.
  const normalizedMessage = (message || '').toLowerCase().replace(/\s+/g, ' ').trim();
  return `${eateryId}:${intent}:${ctxSnippet}:${normalizedMessage}`;
};

const getFromCache = (key) => {
  const cached = responseCache.get(key);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL) return cached.data;
  responseCache.delete(key);
  return null;
};

const setCache = (key, data) => {
  // Evict the oldest entry (Map preserves insertion order) when full.
  if (responseCache.size >= CACHE_MAX_ENTRIES) {
    const oldest = responseCache.keys().next().value;
    if (oldest !== undefined) responseCache.delete(oldest);
  }
  responseCache.set(key, { data, timestamp: Date.now() });
};

// ---------------------------------------------------------------------------
// eateryId resolution
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Helper: Firestore collection query (supports both subcollection & top-level)
// ---------------------------------------------------------------------------
async function getDocsForEatery(eateryId, collectionName) {
  if (!eateryId) return [];

  // 1. Try subcollection first: eateries/{eateryId}/{collectionName}
  try {
    const subSnap = await db
      .collection('eateries')
      .doc(eateryId)
      .collection(collectionName)
      .get();
    if (!subSnap.empty) {
      return subSnap.docs;
    }
  } catch (e) {
    console.warn(`[Sage] Subcollection fetch for ${collectionName} failed:`, e.message);
  }

  // 2. Fallback to top-level collection: {collectionName} where eateryId == eateryId
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

// ---------------------------------------------------------------------------
// System prompt — restaurant business consultant persona
// ---------------------------------------------------------------------------
const SYSTEM_PROMPT = `You are Sage, a warm and insightful restaurant business advisor for SmartEat — the kind of trusted consultant an owner loves talking to.

HOW YOU SOUND:
1. Warm, human, and genuinely encouraging. Use contractions (you're, we're, let's) and talk to the owner directly as "you".
2. Speak like a person, not a report. Short paragraphs, natural flow. Open each reply differently — never start with "Certainly!" or "Here is...".
3. Celebrate wins with real enthusiasm; deliver bad news with empathy and immediately follow with a clear, simple next step.
4. Use at most one emoji per reply, only when it fits the moment.
5. Lead with the single most useful insight, then support it with 2-3 brief points. A few short sentences — not an essay.
6. When it helps, end with a natural follow-up offer like "Want me to dig into Friday?" or "I can break this down by dish if you'd like".
7. Vary your phrasing and sentence rhythm so no two answers feel the same.

HOW YOU FORMAT (the chat styles this markup automatically — it never shows raw symbols):
1. Wrap the key figure or takeaway in **double asterisks** — e.g. **₱12,480** or **Sales are up 8%**. Use it about 1-3 times per reply; never bold a whole paragraph.
2. Start a line with ## for a short section heading (only in replies with more than a few lines).
3. Start lines with - for a bullet list (3-5 items) when comparing options or listing steps.
4. Start a line with > for a callout box — use it for the single most important takeaway or next action.
5. *Single asterisks* give light emphasis to a contrast word; backticks wrap commands like \`ollama serve\`.
6. Leave most of a reply as plain flowing prose — markup only where it genuinely helps the eye scan faster.
7. Never show markdown tables or raw HTML.

HOW YOU RECEIVE DATA:
Before each question, live business data is injected into your context. It is your ONLY source of facts — but never talk about the data feed itself.

STRICT RULES AGAINST HALLUCINATION:
1. ONLY use exact numbers, item names, and facts from the data you were given.
2. NEVER invent menu items, dishes, sales numbers, percentages, or order counts that do not appear in the data.
3. If a metric or specific item is not available, say warmly: "I don't have that tracked yet — here's what I can see instead..."
4. ALWAYS be specific: use exact peso amounts (₱), percentages, item names, and day names.
5. When recommendations are included, weave them into your answer naturally, like advice from a consultant.
6. If a term could have multiple meanings, briefly say how you're interpreting it instead of guessing.
7. For a short or vague question, answer from the most relevant available metrics and mention the period you used.

NEVER reveal internal workings: do not mention "snapshot", "intent", "concepts", "confidence", "prompt", or "data provided". Instead say "I can see..." or "looking at your numbers...".

COMMON RESTAURANT LANGUAGE (your interpretation):
- revenue, sales, takings, turnover, money made = completed-order income (use net sales or gross sales exactly as labeled in the snapshot).
- orders, transactions, tickets = order counts.
- best seller, popular item, what is moving = highest item sales in the stated period.
- slow mover, underperforming item, what is not selling = low or zero item sales.
- low stock, running short, about to run out = stock at or below its minimum.
- COGS may be Actual (from sale-consumption stock movements) or Estimated (fallback from recipe/menu costing). Use the label shown; never guess Actual COGS.
- Gross Margin (by Menu Costing) is separate from Actual COGS. Do not conflate them.
- Discounts, gross sales, and net sales should be discussed only from snapshot values; if missing/unavailable, say so clearly.
- Net profit/profit margin/operating expenses are valid only when shown in the snapshot and must be explained with their COGS source.
- Forecast ingredient cost/profit are estimates unless explicitly marked actual.`;

// ---------------------------------------------------------------------------
// Shared request helpers (used by both /chat and /chat/stream)
// ---------------------------------------------------------------------------

// Validate the incoming message; returns an {error, message} object when
// invalid, or null when the message is acceptable.
const validateMessage = (message) => {
  if (!message || typeof message !== 'string' || !message.trim()) {
    return { error: 'invalid_message', message: 'A non-empty question is required.' };
  }
  if (message.length > 4000) {
    return { error: 'message_too_long', message: 'The question exceeds the 4000-character limit.' };
  }
  return null;
};

// The client sends an intent-specific Smart Snapshot as `context`. Detect which
// type arrived and inject accordingly, falling back to a server-side fetch.
const resolveSnapshotBlock = async (context, eateryId) => {
  const isSmartSnapshot = context && typeof context === 'string'
    && context.includes('SMARTEAT BUSINESS SNAPSHOT');
  const isLegacySnapshot = context && typeof context === 'string'
    && context.includes('SMARTEAT BUSINESS INTELLIGENCE SNAPSHOT');

  if (isSmartSnapshot || isLegacySnapshot) {
    const intentLine = (context.match(/^Intent\s*:\s*(.+)$/m) || [])[1] || 'Unknown';
    console.log(`[Sage] Smart snapshot received — Intent: ${intentLine} (${context.length} chars)`);
    return context;
  }
  if (context && typeof context === 'string' && context.trim().length > 20) {
    return `SMARTEAT BUSINESS SNAPSHOT\nIntent: General\n\n${context}`;
  }
  console.log('[Sage] No client context — fetching fallback snapshot from Firestore');
  return fetchFallbackContext(eateryId);
};

// Message array with the system prompt, last 6 turns, and the new question.
const buildMessages = (snapshotBlock, history, message) => [
  { role: 'system', content: `${SYSTEM_PROMPT}\n\n${snapshotBlock}` },
  ...history.slice(-6),
  { role: 'user', content: message },
];

// Map a low-level Ollama/axios failure to a {status, error, message} triple so
// both handlers report the actual cause instead of one generic apology.
const mapOllamaError = (error) => {
  if (error.code === 'ECONNREFUSED')
    return { status: 503, error: 'ollama_unavailable', message: 'Ollama is not running. Start it with: ollama serve' };
  if (error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT')
    return { status: 504, error: 'ai_timeout', message: 'The AI model is responding slowly. Please try again.' };
  if (error.code === 'ECONNRESET' || error.code === 'EPIPE')
    return { status: 502, error: 'ollama_connection_lost', message: 'The connection to Ollama dropped mid-request.' };
  if (error.code === 'ENOTFOUND' || error.code === 'EAI_AGAIN' || error.code === 'EHOSTUNREACH' || error.code === 'ENETUNREACH')
    return { status: 503, error: 'ollama_host_unreachable', message: `Cannot resolve Ollama host at ${OLLAMA_BASE_URL}. Check OLLAMA_URL.` };
  if (error.response && error.response.status)
    return { status: 502, error: 'ollama_error', message: `Ollama returned HTTP ${error.response.status}.` };
  if (error.request && !error.response)
    return { status: 504, error: 'ai_timeout', message: 'No response received from the AI model in time.' };
  return { status: 500, error: 'server_error', message: error.message || 'Sage could not complete the request.' };
};

// ---------------------------------------------------------------------------
// POST /api/chatbot/chat  (blocking; kept for compatibility)
// ---------------------------------------------------------------------------
exports.chat = async (req, res) => {
  if (SAGE_DISABLED) return res.status(200).json(sageDisabledResponse(false));
  try {
    const { message, history = [], context } = req.body;
    const eateryId = await getEateryId(req);

    const invalid = validateMessage(message);
    if (invalid) return res.status(400).json(invalid);

    // Cache check — keyed by eateryId + intent + contextSnippet + message
    if (eateryId) {
      const cached = getFromCache(getCacheKey(eateryId, message, context));
      if (cached) {
        console.log(`[Sage] ✓ Cache hit for: "${message.substring(0, 50)}"`);
        return res.json({ success: true, response: cached, cached: true, model: MODEL_NAME, timestamp: new Date().toISOString() });
      }
    }

    const snapshotBlock = await resolveSnapshotBlock(context, eateryId);
    const messages = buildMessages(snapshotBlock, history, message);

    console.log(`[Sage] Sending ${messages.length} messages to Ollama (model: ${MODEL_NAME})`);

    const ollamaRes = await axios.post(`${OLLAMA_BASE_URL}/api/chat`, {
      model: MODEL_NAME,
      messages,
      stream: false,
      keep_alive: KEEP_ALIVE,
      options: ollamaOptions(),
      // Slow CPU inference needs headroom — a tighter limit was turning
      // slow-but-working replies into 504 errors. Client waits 125s.
    }, { timeout: OLLAMA_TIMEOUT });

    const reply = (ollamaRes.data.message?.content || '').trim();
    if (!reply) {
      return res.status(502).json({
        error: 'empty_response',
        message: 'Sage could not form a reliable response from the AI service.',
      });
    }

    if (eateryId) setCache(getCacheKey(eateryId, message, context), reply);

    res.json({ success: true, response: reply, model: MODEL_NAME, cached: false, timestamp: new Date().toISOString() });

  } catch (error) {
    console.error('[Sage] Chat error:', error.code || error.message);
    const mapped = mapOllamaError(error);
    res.status(mapped.status).json({ error: mapped.error, message: mapped.message });
  }
};

// ---------------------------------------------------------------------------
// POST /api/chatbot/chat/stream  (Server-Sent Events)
//
// Streams tokens from Ollama's NDJSON output as SSE `data:` events so the UI
// can render progressively. Event shapes:
//   { type: 'token', text }                       — a content delta
//   { type: 'done', cached, model, timestamp }    — success terminator
//   { type: 'error', error, message }             — failure (stream then ends)
// ---------------------------------------------------------------------------
exports.chatStream = async (req, res) => {
  const { message, history = [], context } = req.body;
  const eateryId = await getEateryId(req);

  // Enable SSE and disable proxy buffering so tokens flush immediately.
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  res.flushHeaders?.();

  const send = (obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`);

  if (SAGE_DISABLED) {
    send({ type: 'token', text: SAGE_DISABLED_MESSAGE });
    send({ type: 'done', cached: false, model: null, demoDisabled: true, timestamp: new Date().toISOString() });
    return res.end();
  }

  try {
    const invalid = validateMessage(message);
    if (invalid) {
      send({ type: 'error', error: invalid.error, message: invalid.message });
      return res.end();
    }

    // Serve a cached reply as a single token so the client path is identical.
    if (eateryId) {
      const cached = getFromCache(getCacheKey(eateryId, message, context));
      if (cached) {
        console.log(`[Sage] ✓ Cache hit (stream) for: "${message.substring(0, 50)}"`);
        send({ type: 'token', text: cached });
        send({ type: 'done', cached: true, model: MODEL_NAME, timestamp: new Date().toISOString() });
        return res.end();
      }
    }

    const snapshotBlock = await resolveSnapshotBlock(context, eateryId);
    const messages = buildMessages(snapshotBlock, history, message);

    console.log(`[Sage] Streaming ${messages.length} messages from Ollama (model: ${MODEL_NAME})`);

    const ollamaRes = await axios.post(`${OLLAMA_BASE_URL}/api/chat`, {
      model: MODEL_NAME,
      messages,
      stream: true,
      keep_alive: KEEP_ALIVE,
      options: ollamaOptions(),
    }, { timeout: OLLAMA_TIMEOUT, responseType: 'stream' });

    let full = '';
    // Ollama emits newline-delimited JSON, not standard SSE. Buffer partial
    // lines across chunk boundaries before parsing.
    let buffer = '';
    ollamaRes.data.on('data', (chunk) => {
      buffer += chunk.toString('utf8');
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        let parsed;
        try {
          parsed = JSON.parse(trimmed);
        } catch (_) {
          continue; // ignore malformed partials
        }
        const token = parsed.message?.content || '';
        if (token) {
          full += token;
          send({ type: 'token', text: token });
        }
        if (parsed.done) {
          // handled after stream end for cache correctness
        }
      }
    });

    ollamaRes.data.on('error', (err) => {
      console.error('[Sage] Stream error:', err.message);
      const mapped = mapOllamaError(err);
      send({ type: 'error', error: mapped.error, message: mapped.message });
      res.end();
    });

    ollamaRes.data.on('end', () => {
      const reply = full.trim();
      if (!reply) {
        send({ type: 'error', error: 'empty_response', message: 'Sage could not form a reliable response from the AI service.' });
        return res.end();
      }
      if (eateryId) setCache(getCacheKey(eateryId, message, context), reply);
      send({ type: 'done', cached: false, model: MODEL_NAME, timestamp: new Date().toISOString() });
      res.end();
    });

  } catch (error) {
    console.error('[Sage] Chat stream error:', error.code || error.message);
    const mapped = mapOllamaError(error);
    // Headers are already sent, so report the failure as an SSE error event.
    send({ type: 'error', error: mapped.error, message: mapped.message });
    res.end();
  }
};

// ---------------------------------------------------------------------------
// GET /api/chatbot/status
// ---------------------------------------------------------------------------
exports.getStatus = async (req, res) => {
  if (SAGE_DISABLED) {
    return res.json({
      status: 'disabled',
      ollamaRunning: false,
      hasModel: false,
      demoDisabled: true,
      message: SAGE_DISABLED_MESSAGE,
    });
  }
  try {
    const response = await axios.get(`${OLLAMA_BASE_URL}/api/tags`, { timeout: 5000 });
    const models = response.data.models || [];
    res.json({
      status: 'online',
      ollamaRunning: true,
      hasModel: models.length > 0,
      availableModels: models.map(m => m.name),
      baseUrl: OLLAMA_BASE_URL,
    });
  } catch (error) {
    // Distinguish "not running" from "not answering" so the client can show
    // the right fix instead of one blanket "start ollama serve" message.
    const refused = error.code === 'ECONNREFUSED';
    const timedOut = error.code === 'ECONNABORTED' || error.code === 'ETIMEDOUT';
    res.status(503).json({
      status: 'offline',
      ollamaRunning: false,
      hasModel: false,
      error: refused ? 'ollama_unavailable'
           : timedOut ? 'ollama_timeout'
           : 'ollama_unreachable',
      message: refused
        ? 'Ollama is not running. Start it with: ollama serve'
        : timedOut
          ? 'Ollama is running but did not respond in time.'
          : `Cannot reach Ollama at ${OLLAMA_BASE_URL}.`,
      detail: error.message,
    });
  }
};

// ---------------------------------------------------------------------------
// GET /api/chatbot/insights  (legacy endpoint — still used by ChatProvider)
// ---------------------------------------------------------------------------
exports.getInsights = async (req, res) => {
  if (SAGE_DISABLED) {
    return res.json({ success: false, demoDisabled: true, message: SAGE_DISABLED_MESSAGE, data: null });
  }
  try {
    const eateryId = await getEateryId(req);
    if (!eateryId) return res.status(400).json({ error: 'eateryId required' });

    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const last7 = new Date(); last7.setDate(last7.getDate() - 7);

    const orderDocs = await getDocsForEatery(eateryId, 'orders');

    let totalRevenue = 0, todayRevenue = 0, totalOrders = 0;
    const activeDays = new Set();
    const itemSales = {};

    orderDocs.forEach(d => {
      const o = d.data() || {};
      if (!isCompletedOrder(o)) return;

      const dt = parseDate(o.createdAt);
      if (!dt || dt < last7) return;

      const amount = Number(o.totalAmount || o.total || 0);
      totalRevenue += amount;
      totalOrders++;

      activeDays.add(dt.toISOString().split('T')[0]);
      if (dt >= today) todayRevenue += amount;

      (o.items || []).forEach(item => {
        const name = item.name || item.menuItemName || 'Unknown';
        const qty = Number(item.quantity || item.qty || 1);
        itemSales[name] = (itemSales[name] || 0) + qty;
      });
    });

    const topSeller = Object.entries(itemSales)
      .sort((a, b) => b[1] - a[1])[0]?.[0] || 'N/A';

    const avgDailyOrders = activeDays.size > 0
      ? (totalOrders / activeDays.size).toFixed(1)
      : 0;

    // Ask AI for a short narrative summary
    let aiSummary = '';
    try {
      const prompt = `You are Sage, a warm restaurant business consultant. Write a short, human summary of this week's performance for the restaurant owner in 2-3 sentences: open with the most important insight, sound genuinely encouraging when things went well, empathetic when they didn't, and finish with one simple suggested action. Use contractions and natural language — not a robotic data readout.

Data:
- Total revenue: ₱${totalRevenue.toFixed(2)}
- Today's revenue: ₱${todayRevenue.toFixed(2)}
- Total orders: ${totalOrders}
- Active days: ${activeDays.size}
- Average daily orders: ${avgDailyOrders}
- Top selling item: ${topSeller}

STRICT RULE: Use ONLY the exact numbers provided above. Never invent sales numbers or dish names.`;

      const aiRes = await axios.post(`${OLLAMA_BASE_URL}/api/generate`, {
        model: MODEL_NAME,
        prompt,
        stream: false,
        options: { temperature: 0.5, num_predict: 120, num_ctx: 4096 },
      }, { timeout: 60000 });

      aiSummary = (aiRes.data.response || '').trim();
    } catch (_) {
      aiSummary = `Revenue this week: ₱${totalRevenue.toFixed(2)} across ${totalOrders} orders. Top item: ${topSeller}.`;
    }

    res.json({
      success: true,
      data: {
        totalRevenue,
        todayRevenue,
        totalOrders,
        avgDailyOrders: parseFloat(avgDailyOrders),
        activeDays: activeDays.size,
        topSeller,
        aiSummary,
      },
    });
  } catch (error) {
    console.error('[Sage] getInsights error:', error.message);
    res.status(500).json({ error: 'Failed to fetch insights', message: error.message });
  }
};

// ---------------------------------------------------------------------------
// Fallback: server-side Firestore fetch (used when client sends no context)
// ---------------------------------------------------------------------------
async function fetchFallbackContext(eateryId) {
  if (!eateryId) return '=== RESTAURANT DATA ===\nNo restaurant data available.\n======================';
  try {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const last7 = new Date(); last7.setDate(last7.getDate() - 7);

    const [menuDocs, orderDocs, inventoryDocs] = await Promise.all([
      getDocsForEatery(eateryId, 'menu'),
      getDocsForEatery(eateryId, 'orders'),
      getDocsForEatery(eateryId, 'inventory'),
    ]);

    let todayRev = 0, weekRev = 0;
    const itemSales = {};
    let completedOrdersCount = 0;

    orderDocs.forEach(d => {
      const o = d.data() || {};
      if (!isCompletedOrder(o)) return;

      const amt = Number(o.totalAmount || o.total || 0);
      const dt = parseDate(o.createdAt);

      if (dt && dt >= last7) {
        weekRev += amt;
        completedOrdersCount++;
        if (dt >= today) todayRev += amt;

        (o.items || []).forEach(i => {
          const n = i.name || i.menuItemName || 'Unknown';
          const q = Number(i.quantity || i.qty || 1);
          itemSales[n] = (itemSales[n] || 0) + q;
        });
      }
    });

    const topItems = Object.entries(itemSales)
      .sort((a,b) => b[1] - a[1])
      .slice(0, 5)
      .map(([n,q]) => `${n} (${q} sold)`)
      .join(', ') || 'None';

    const lowStock = inventoryDocs
      .map(d => d.data() || {})
      .filter(i => Number(i.currentStock || 0) <= Number(i.minStock || 0))
      .map(i => i.name)
      .filter(Boolean)
      .slice(0, 5)
      .join(', ') || 'None';

    const menuSample = menuDocs
      .map(d => (d.data() || {}).name)
      .filter(Boolean)
      .slice(0, 10)
      .join(', ') || 'None';

    return `=== SMARTEAT BUSINESS INTELLIGENCE SNAPSHOT ===
Restaurant ID: ${eateryId}
Today Revenue: ₱${todayRev.toFixed(2)}
7-Day Revenue: ₱${weekRev.toFixed(2)}
Completed Orders (7d): ${completedOrdersCount}
Top Selling Items: ${topItems}
Low Stock Items: ${lowStock}
Menu Items: ${menuSample}
=================================================`;
  } catch (e) {
    console.error('[Sage] fetchFallbackContext error:', e);
    return `=== RESTAURANT DATA ===\nError loading data: ${e.message}\n======================`;
  }
}

// ---------------------------------------------------------------------------
// Warm-up  (called on server start; non-blocking, best-effort)
//
// Loads the model into memory so the first real question skips cold-start,
// then keeps it resident via `keep_alive`.
// ---------------------------------------------------------------------------
exports.warmUpModel = async () => {
  if (SAGE_DISABLED) {
    console.log('[Sage] Demo mode: warm-up skipped (SAGE_DISABLED=true).');
    return;
  }
  const started = Date.now();
  try {
    await axios.post(`${OLLAMA_BASE_URL}/api/chat`, {
      model: MODEL_NAME,
      messages: [{ role: 'user', content: 'ping' }],
      stream: false,
      keep_alive: KEEP_ALIVE,
      options: { num_predict: 1, num_ctx: 512 },
    }, { timeout: OLLAMA_TIMEOUT });
    console.log(`[Sage] Model "${MODEL_NAME}" warmed in ${Date.now() - started}ms (keep_alive: ${KEEP_ALIVE}).`);
  } catch (error) {
    // Never fatal: Sage will warm lazily on the first real request instead.
    console.warn(`[Sage] Warm-up skipped (${error.code || error.message}). Sage will load on first use.`);
  }
};
