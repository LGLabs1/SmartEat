const { admin, db } = require('../config/firebase');
const { sendSmsMessage } = require('./smsService');
const { writeSystemNotification } = require('./notificationService');
const { normalizePhMobile } = require('../utils/passwordReset');

const PH_OFFSET_MS = 8 * 60 * 60 * 1000;

function formatYMD(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function previousManilaDateKey(now) {
  const shifted = new Date(now.getTime() + PH_OFFSET_MS);
  const yesterday = new Date(
    Date.UTC(
      shifted.getUTCFullYear(),
      shifted.getUTCMonth(),
      shifted.getUTCDate() - 1,
    ),
  );
  return formatYMD(yesterday);
}

function manilaDayRangeUtc(dateKey) {
  const [year, month, day] = String(dateKey).split('-').map(Number);
  const start = new Date(Date.UTC(year, month - 1, day) - PH_OFFSET_MS);
  return { start, end: new Date(start.getTime() + 24 * 60 * 60 * 1000) };
}

function toMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const parsed = Date.parse(String(value));
  return Number.isNaN(parsed) ? 0 : parsed;
}

function isTruthy(value, fallback) {
  if (value === undefined || value === null) return fallback;
  if (typeof value === 'string') return value.trim().toLowerCase() === 'true' || value.trim() === '1';
  return value === true || value === 1;
}

function isAlreadyExists(error) {
  const code = String(error && error.code ? error.code : '');
  return code === '6' || code === 'ALREADY_EXISTS' || code.includes('ALREADY_EXISTS');
}

function maskPhone(phone) {
  const value = String(phone || '');
  return value.length >= 7 ? `${value.slice(0, 3)}****${value.slice(-4)}` : 'Not set';
}

async function loadSmsSettings(eateryId) {
  const snapshot = await db
    .collection('eateries')
    .doc(eateryId)
    .collection('settings')
    .doc('sms')
    .get();
  const data = snapshot && snapshot.exists ? snapshot.data() || {} : {};
  return {
    enabled: isTruthy(data.enabled, false),
    dailySummaryEnabled: isTruthy(data.dailySummaryEnabled, true),
  };
}

async function loadAdminContact(eateryId) {
  const eaterySnap = await db.collection('eateries').doc(eateryId).get();
  const eatery = eaterySnap && eaterySnap.exists ? eaterySnap.data() || {} : {};
  const ownerUid = String(eatery.ownerUid || '').trim();
  let phone = null;

  if (ownerUid) {
    const userSnap = await db.collection('users').doc(ownerUid).get();
    const user = userSnap && userSnap.exists ? userSnap.data() || {} : {};
    phone = normalizePhMobile(String(user.phone || user.phoneNumber || ''));

    if (!phone) {
      const adminSnap = await db
        .collection('eateries')
        .doc(eateryId)
        .collection('admin_profiles')
        .doc(ownerUid)
        .get();
      const profile = adminSnap && adminSnap.exists ? adminSnap.data() || {} : {};
      phone = normalizePhMobile(String(profile.phone || profile.phoneNumber || ''));
    }
  }

  return {
    phone,
    eateryName: String(eatery.name || 'SmartEat').trim() || 'SmartEat',
  };
}

async function buildSummary(eateryId, start, end) {
  const snapshot = await db
    .collection('eateries')
    .doc(eateryId)
    .collection('orders')
    .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(start))
    .where('createdAt', '<', admin.firestore.Timestamp.fromDate(end))
    .get();

  let orderCount = 0;
  let revenue = 0;
  const itemQty = new Map();
  for (const doc of snapshot.docs || []) {
    const order = doc.data() || {};
    if (String(order.status || '').trim().toLowerCase() !== 'completed') continue;
    orderCount += 1;
    revenue += Number(order.totalAmount) || 0;
    const items = Array.isArray(order.items) ? order.items : [];
    for (const item of items) {
      if (!item || typeof item !== 'object') continue;
      const name = String(item.name || '').trim();
      const qty = Number(item.quantity) || 0;
      if (name && qty > 0) itemQty.set(name, (itemQty.get(name) || 0) + qty);
    }
  }

  if (!orderCount) return null;
  let topText = '';
  if (itemQty.size) {
    const top = [...itemQty.entries()].sort((a, b) => b[1] - a[1])[0];
    topText = ` Top: ${top[0]} (${top[1]} sold).`;
  }
  const revenueText = revenue === Math.round(revenue)
    ? String(Math.round(revenue))
    : revenue.toFixed(0);
  return {
    orderCount,
    revenue,
    message: `SmartEat: Yesterday ${orderCount} order${orderCount === 1 ? '' : 's'}, PHP${revenueText}.${topText}`,
  };
}

async function markLog(logRef, payload) {
  await logRef.set(
    {
      ...payload,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function sendDailySummaryForEatery({ eateryId, targetDateKey, start, end }) {
  const settings = await loadSmsSettings(eateryId);
  if (!settings.enabled || !settings.dailySummaryEnabled) return 'skipped';

  const summary = await buildSummary(eateryId, start, end);
  if (!summary) return 'skipped';

  const contact = await loadAdminContact(eateryId);
  if (!contact.phone) return 'skipped';

  const logRef = db
    .collection('eateries')
    .doc(eateryId)
    .collection('sms_logs')
    .doc(`daily_summary_${targetDateKey}`);
  const existing = await logRef.get();
  if (existing && existing.exists) return 'skipped';

  try {
    await logRef.create({
      type: 'daily_summary',
      status: 'sending',
      targetDateKey,
      recipient: maskPhone(contact.phone),
      messagePreview: summary.message.slice(0, 160),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    if (isAlreadyExists(error)) return 'skipped';
    throw error;
  }

  try {
    const response = await sendSmsMessage({
      phoneNumber: contact.phone,
      message: summary.message,
    });
    const status = Number(response.status) || 502;
    if (status < 200 || status >= 300) {
      await markLog(logRef, {
        status: 'failed',
        error: `SMS provider returned ${status}`,
      });
      return 'failed';
    }

    const rawId = response.data && typeof response.data === 'object'
      ? response.data.message_id || response.data.id || response.data.messageId
      : null;
    const messageId = rawId == null ? null : String(rawId).slice(0, 128);
    await markLog(logRef, {
      status: 'sent',
      providerMessageId: messageId,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await writeSystemNotification({
      eateryId,
      type: 'sms_daily_summary',
      title: 'Daily Summary SMS Sent',
      body: summary.message,
      source: 'sms',
      audience: 'admin',
      dedupeKey: `sms_daily_summary_${targetDateKey}`,
      preserveReadState: true,
      data: {
        smsType: 'daily_summary',
        targetDateKey,
        orderCount: summary.orderCount,
        revenue: summary.revenue,
        providerMessageId: messageId,
        target: 'dashboard',
        route: 'dashboard',
      },
    });
    return 'sent';
  } catch (error) {
    await markLog(logRef, {
      status: 'failed',
      error: String(error && error.message ? error.message : error).slice(0, 500),
    });
    return 'failed';
  }
}

async function sendDailySummaryForAllEateries({ now = new Date() } = {}) {
  const targetDateKey = previousManilaDateKey(now);
  const { start, end } = manilaDayRangeUtc(targetDateKey);
  const eateries = await db.collection('eateries').get();
  const result = {
    targetDateKey,
    total: 0,
    sent: 0,
    skipped: 0,
    failed: 0,
  };

  for (const eateryDoc of eateries.docs || []) {
    result.total += 1;
    try {
      const status = await sendDailySummaryForEatery({
        eateryId: eateryDoc.id,
        targetDateKey,
        start,
        end,
      });
      result[status] = (result[status] || 0) + 1;
    } catch (error) {
      result.failed += 1;
      console.error(`Daily summary SMS failed for ${eateryDoc.id}:`, error.message);
    }
  }

  return result;
}

module.exports = {
  manilaDayRangeUtc,
  previousManilaDateKey,
  sendDailySummaryForAllEateries,
};
