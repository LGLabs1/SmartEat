/* eslint-disable no-console */

const admin = require('firebase-admin');

function requireEnv(name) {
  const v = process.env[name];
  if (!v || String(v).trim() === '') {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

function parseServiceAccount(raw) {
  const trimmed = String(raw || '').trim();
  if (!trimmed) throw new Error('Empty service account secret');

  // 1) Try raw JSON first
  try {
    return JSON.parse(trimmed);
  } catch (_) {
    // continue
  }

  // 2) Try base64-encoded JSON (common workaround for multiline secrets)
  try {
    const decoded = Buffer.from(trimmed, 'base64').toString('utf8').trim();
    return JSON.parse(decoded);
  } catch (_) {
    throw new Error(
      'Invalid FIREBASE_SERVICE_ACCOUNT_JSON. Paste the full service-account JSON (starting with {) or a base64-encoded JSON string.'
    );
  }
}

function formatYMD(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function addDays(d, days) {
  const n = new Date(d);
  n.setDate(n.getDate() + days);
  return n;
}

async function main() {
  const serviceAccountJson = requireEnv('FIREBASE_SERVICE_ACCOUNT_JSON');
  const serviceAccount = parseServiceAccount(serviceAccountJson);

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  const db = admin.firestore();

  const now = new Date();
  const windowDays = Number(process.env.ANALYTICS_WINDOW_DAYS || 90);
  const since = addDays(now, -windowDays);

  // Completed orders only
  const ordersSnap = await db
    .collection('orders')
    .where('status', '==', 'completed')
    .where('completedAt', '>=', admin.firestore.Timestamp.fromDate(since))
    .get();

  /**
   * Structure:
   * daily[eateryId][yyyy-mm-dd] = { revenue, orders, itemsSold }
   * itemDaily[eateryId][menuItemId][yyyy-mm-dd] = qty
   */
  const daily = Object.create(null);
  const itemDaily = Object.create(null);

  for (const doc of ordersSnap.docs) {
    const o = doc.data() || {};
    const eateryId = String(o.eateryId || '').trim();
    if (!eateryId) continue;

    const completedAt = o.completedAt?.toDate ? o.completedAt.toDate() : null;
    if (!completedAt) continue;

    const dayKey = formatYMD(startOfDay(completedAt));

    if (!daily[eateryId]) daily[eateryId] = Object.create(null);
    if (!daily[eateryId][dayKey]) {
      daily[eateryId][dayKey] = { revenue: 0, orders: 0, itemsSold: 0 };
    }

    const total = Number(o.totalAmount || 0);
    daily[eateryId][dayKey].revenue += Number.isFinite(total) ? total : 0;
    daily[eateryId][dayKey].orders += 1;

    const items = Array.isArray(o.items) ? o.items : [];
    for (const it of items) {
      const menuItemId = String(it.menuItemId || it.id || '').trim();
      const qty = Number(it.quantity || it.qty || 0);
      if (!Number.isFinite(qty) || qty <= 0) continue;

      daily[eateryId][dayKey].itemsSold += qty;

      if (!itemDaily[eateryId]) itemDaily[eateryId] = Object.create(null);
      if (!itemDaily[eateryId][menuItemId]) {
        itemDaily[eateryId][menuItemId] = Object.create(null);
      }
      itemDaily[eateryId][menuItemId][dayKey] =
        (itemDaily[eateryId][menuItemId][dayKey] || 0) + qty;
    }
  }

  // Write daily aggregates + basic 7-day item forecasts back to Firestore.
  // Collections written:
  // analytics_daily/{eateryId}/days/{yyyy-mm-dd}
  // predictions/{eateryId}/demandForecast (doc)
  const writes = [];
  const today = startOfDay(now);

  for (const eateryId of Object.keys(daily)) {
    const perDay = daily[eateryId];

    for (const dayKey of Object.keys(perDay)) {
      const ref = db
        .collection('analytics_daily')
        .doc(eateryId)
        .collection('days')
        .doc(dayKey);

      const payload = {
        date: dayKey,
        revenue: perDay[dayKey].revenue,
        orders: perDay[dayKey].orders,
        itemsSold: perDay[dayKey].itemsSold,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      writes.push(ref.set(payload, { merge: true }));
    }

    // Very simple forecast: for each menuItemId, forecast next 7 days
    // using average of the same weekday in history window.
    const perItem = itemDaily[eateryId] || Object.create(null);
    const nextDays = Number(process.env.FORECAST_DAYS || 7);

    const forecastByItem = [];

    for (const menuItemId of Object.keys(perItem)) {
      const series = perItem[menuItemId];
      const entries = Object.keys(series)
        .map((k) => ({
          date: k,
          dt: new Date(`${k}T00:00:00`),
          qty: Number(series[k] || 0),
        }))
        .filter((x) => Number.isFinite(x.qty));

      if (entries.length === 0) continue;

      // Map weekday -> list of qty
      const byWeekday = new Map();
      for (const e of entries) {
        const wd = e.dt.getDay();
        if (!byWeekday.has(wd)) byWeekday.set(wd, []);
        byWeekday.get(wd).push(e.qty);
      }

      const predicted = [];
      for (let i = 1; i <= nextDays; i++) {
        const d = addDays(today, i);
        const wd = d.getDay();
        const arr = byWeekday.get(wd) || [];
        const avg =
          arr.length === 0
            ? 0
            : arr.reduce((a, b) => a + b, 0) / arr.length;
        predicted.push({
          date: formatYMD(d),
          predictedQty: Math.round(avg * 100) / 100,
        });
      }

      forecastByItem.push({
        menuItemId,
        horizonDays: nextDays,
        predicted,
      });
    }

    const predRef = db.collection('predictions').doc(eateryId);
    writes.push(
      predRef.set(
        {
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
          windowDays,
          nextDays,
          demandByItem: forecastByItem,
        },
        { merge: true }
      )
    );
  }

  await Promise.all(writes);

  console.log(
    `Done. Processed ${ordersSnap.size} completed orders. Updated ${Object.keys(daily).length} eateries.`
  );
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
