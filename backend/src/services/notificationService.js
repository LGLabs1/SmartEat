const { admin, db } = require('../config/firebase');

const VALID_ROLES = new Set(['admin', 'manager', 'staff', 'all']);
const SENSITIVE_TYPES = new Set([
  'low_stock',
  'out_of_stock',
  'bill_overdue',
  'bill_due_soon',
  'staff_approval',
  'order',
  'sms_low_stock',
  'sms_bill_reminder',
  'sms_daily_summary',
  'sms_test',
]);

function cleanText(value, maxLength = 180) {
  return String(value ?? '')
    .trim()
    .slice(0, maxLength);
}

function sanitizeSegment(value) {
  return String(value ?? '')
    .trim()
    .replace(/[^a-zA-Z0-9_-]/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 120);
}

function buildNotificationDocId(eateryId, dedupeKey) {
  const prefix = sanitizeSegment(eateryId) || 'eatery';
  const key = sanitizeSegment(dedupeKey) || 'notification';
  const room = 180 - prefix.length - 1;
  const trimmed = room > 0 && key.length > room ? key.slice(0, room) : key;
  return `${prefix}_${trimmed}`;
}

function normalizeStringList(value, maxLength = 100) {
  if (!Array.isArray(value)) {
    const single = cleanText(value, 120);
    return single ? [single] : [];
  }
  const seen = new Set();
  const result = [];
  for (const item of value) {
    const text = cleanText(item, 120);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    result.push(text);
    if (result.length >= maxLength) break;
  }
  return result;
}

function deriveIgnoreKey(dedupeKey, type) {
  const key = sanitizeSegment(dedupeKey || type || 'notification');
  return key
    .replace(/_(\d{4}-\d{2}-\d{2})(_\d{1,4})*$/, '')
    .replace(/_(\d{13}|\d{8})$/, '')
    .replace(/_(\d{1,2})$/, '') || key;
}

function ignoreKeyFor(data = {}) {
  const explicit = cleanText(data.ignoreKey || data.data?.ignoreKey, 160);
  if (explicit) return sanitizeSegment(explicit);
  return deriveIgnoreKey(
    cleanText(data.dedupeKey || data.data?.dedupeKey, 160),
    cleanText(data.type, 80),
  );
}

function defaultAudienceFor(type) {
  const normalized = cleanText(type, 80).toLowerCase();
  if (SENSITIVE_TYPES.has(normalized) || normalized.startsWith('sms_')) {
    return 'admin';
  }
  if (normalized === 'attendance') return 'staff';
  return 'all';
}

function rolesFor(audience, type, targetUids = []) {
  const normalized = cleanText(audience, 40).toLowerCase();
  if (normalized === 'admin' || normalized === 'manager') {
    return ['admin', 'manager'];
  }
  if (normalized === 'staff') {
    return ['staff', 'admin', 'manager'];
  }
  if (normalized === 'all' || normalized === 'everyone') {
    return ['all', 'staff', 'admin', 'manager'];
  }
  return rolesFor(defaultAudienceFor(type), type, targetUids);
}

function normalizeRoles({ allowedRoles, audience, type, targetUids }) {
  const supplied = normalizeStringList(allowedRoles, 10)
    .map((role) => role.toLowerCase())
    .filter((role) => VALID_ROLES.has(role));
  if (supplied.length) return supplied;
  return rolesFor(audience, type, targetUids);
}

function timestampValue(value) {
  if (!value) return admin.firestore.FieldValue.serverTimestamp();
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return admin.firestore.FieldValue.serverTimestamp();
  }
  return admin.firestore.Timestamp.fromDate(date);
}

function isAlreadyExists(error) {
  const code = String(error && error.code ? error.code : '');
  return code === '6' || code === 'ALREADY_EXISTS' || code.includes('ALREADY_EXISTS');
}

function notificationStateRef(uid, docId) {
  return db.collection('users').doc(uid).collection('notificationStates').doc(docId);
}

function notificationIgnoreRuleRef(uid, ignoreKey) {
  return db.collection('users').doc(uid).collection('notificationIgnoreRules').doc(ignoreKey);
}

async function loadUserNotificationState(uid) {
  const states = new Map();
  const rules = new Map();
  const user = cleanText(uid, 120);
  if (!user) return { states, rules };

  const [stateSnap, rulesSnap] = await Promise.all([
    db.collection('users').doc(user).collection('notificationStates').get(),
    db.collection('users').doc(user).collection('notificationIgnoreRules').get(),
  ]);
  for (const doc of snapshotDocs(stateSnap)) {
    states.set(doc.id, doc.data() || {});
  }
  for (const doc of snapshotDocs(rulesSnap)) {
    const data = doc.data() || {};
    rules.set(String(data.ignoreKey || doc.id), {
      ...data,
      ignoredAtMillis: toMillis(data.ignoredAt),
    });
  }
  return { states, rules };
}

async function writeSystemNotification(input = {}) {
  const eateryId = cleanText(input.eateryId, 120);
  const dedupeKey = cleanText(input.dedupeKey, 160);
  const type = cleanText(input.type, 80);
  const title = cleanText(input.title, 180);
  const body = cleanText(input.body, 1000);

  if (!eateryId || !dedupeKey || !type || !title || !body) {
    const error = new Error('Invalid notification payload');
    error.code = 'invalid_notification';
    error.status = 400;
    throw error;
  }

  const audience = cleanText(input.audience, 40) || defaultAudienceFor(type);
  const targetUids = normalizeStringList(input.targetUids);
  const allowedRoles = normalizeRoles({
    allowedRoles: input.allowedRoles,
    audience,
    type,
    targetUids,
  });
  const source = cleanText(input.source, 60) || 'system';
  const docId = buildNotificationDocId(eateryId, dedupeKey);
  const ref = db.collection('notifications').doc(docId);

  if (input.preserveReadState) {
    const existing = await ref.get();
    if (existing && existing.exists) {
      return { id: docId, created: false };
    }
  }

  let serializedData = {};
  try {
    serializedData = JSON.parse(JSON.stringify(input.data || {}));
  } catch (_) {
    serializedData = {};
  }
  const dataText = JSON.stringify(serializedData);
  if (dataText.length > 12000) {
    serializedData = { truncated: true };
  }

  const payload = {
    eateryId,
    title,
    body,
    type,
    source,
    audience,
    allowedRoles,
    targetUids,
    dedupeKey,
    ignoreKey: ignoreKeyFor(input),
    data: serializedData,
    active: true,
    isRead: false,
    readBy: {},
    createdAt: timestampValue(input.createdAt),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  try {
    await ref.create(payload);
    return { id: docId, created: true };
  } catch (error) {
    if (isAlreadyExists(error)) {
      return { id: docId, created: false };
    }
    throw error;
  }
}

function toMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const parsed = Date.parse(String(value));
  return Number.isNaN(parsed) ? 0 : parsed;
}

function numberValue(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function itemQuantity(data) {
  for (const key of ['quantity', 'currentQuantity', 'currentStock', 'stock', 'inStock']) {
    if (data[key] !== undefined && data[key] !== null) {
      return numberValue(data[key]);
    }
  }
  return 0;
}

function itemThreshold(data) {
  for (const key of ['reorderPoint', 'minStock', 'minimumStock', 'lowStockThreshold']) {
    if (data[key] !== undefined && data[key] !== null) {
      return numberValue(data[key]);
    }
  }
  return 0;
}

function snapshotDocs(snapshot) {
  if (!snapshot || !Array.isArray(snapshot.docs)) return [];
  return snapshot.docs;
}

function specFor(partial) {
  return {
    source: 'server_sync',
    audience: rolesFor('', partial.type, []).includes('all') ? 'all' : 'admin',
    ...partial,
  };
}

function manilaDateKey(now = Date.now()) {
  return new Date(now + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function attendanceDisplayTime(value) {
  const millis = toMillis(value);
  if (!millis) return '';
  return new Date(millis + 8 * 60 * 60 * 1000).toISOString().slice(11, 16);
}

function attendanceDurationText(minutes) {
  const total = Math.max(0, Math.round(minutes));
  const hours = Math.floor(total / 60);
  const mins = total % 60;
  if (!hours) return `${mins} min`;
  if (!mins) return `${hours} hr`;
  return `${hours} hr ${mins} min`;
}

async function loadAttendanceRules(tenant) {
  const snapshot = await db
    .collection('eateries')
    .doc(tenant)
    .collection('settings')
    .doc('attendance')
    .get();
  const data = snapshot && snapshot.exists ? snapshot.data() || {} : {};
  const full = numberValue(data.fullDayHours);
  const grace = data.graceMinutes === undefined
    ? 10
    : numberValue(data.graceMinutes);
  return {
    fullDayHours: full > 0 ? full : 8,
    graceMinutes: Math.max(0, grace),
  };
}

async function buildAttendanceNotificationSpecs({ tenant, usersSnap, today }) {
  const specs = [];
  const settings = await loadAttendanceRules(tenant);
  const attendanceSnap = await db
    .collection('eateries')
    .doc(tenant)
    .collection('staff_attendance')
    .where('date', '==', today)
    .get();

  const names = new Map();
  for (const doc of snapshotDocs(usersSnap)) {
    const data = doc.data() || {};
    const first = cleanText(data.firstName, 60);
    const last = cleanText(data.lastName, 60);
    const full = `${first} ${last}`.trim();
    names.set(
      doc.id,
      full || cleanText(data.name || data.displayName || data.email, 120) || 'Staff member',
    );
  }

  const now = Date.now();
  for (const doc of snapshotDocs(attendanceSnap)) {
    const data = doc.data() || {};
    const uid = cleanText(data.uid, 120);
    if (!uid) continue;
    const staffName = names.get(uid) ||
      cleanText(data.staffName || data.name, 120) ||
      'Staff member';
    const timeInText = attendanceDisplayTime(data.timeIn);
    const timeOutText = attendanceDisplayTime(data.timeOut);
    const shared = {
      date: today,
      staffUid: uid,
      staffName,
      timeIn: timeInText,
      timeOut: timeOutText,
    };

    if (timeInText) {
      specs.push(specFor({
        type: 'attendance_time_in',
        title: 'Staff time in',
        body: `${staffName} timed in at ${timeInText}.`,
        dedupeKey: `attendance_time_in_admin_${uid}_${today}`,
        source: 'attendance',
        audience: 'admin',
        data: {
          ...shared,
          target: 'staff_attendance',
          route: 'staff_attendance',
          ignoreKey: `attendance_time_in_${uid}`,
        },
      }));
      specs.push(specFor({
        type: 'attendance_time_in',
        title: 'You timed in',
        body: `You timed in at ${timeInText}.`,
        dedupeKey: `attendance_time_in_self_${uid}_${today}`,
        source: 'attendance',
        audience: 'staff',
        targetUids: [uid],
        data: {
          ...shared,
          target: 'profile',
          route: 'profile',
          ignoreKey: `attendance_time_in_self_${uid}`,
        },
      }));
    }

    if (timeOutText) {
      specs.push(specFor({
        type: 'attendance_time_out',
        title: 'Staff time out',
        body: `${staffName} timed out at ${timeOutText}.`,
        dedupeKey: `attendance_time_out_admin_${uid}_${today}`,
        source: 'attendance',
        audience: 'admin',
        data: {
          ...shared,
          target: 'staff_attendance',
          route: 'staff_attendance',
          ignoreKey: `attendance_time_out_${uid}`,
        },
      }));
      specs.push(specFor({
        type: 'attendance_time_out',
        title: 'You timed out',
        body: `You timed out at ${timeOutText}.`,
        dedupeKey: `attendance_time_out_self_${uid}_${today}`,
        source: 'attendance',
        audience: 'staff',
        targetUids: [uid],
        data: {
          ...shared,
          target: 'profile',
          route: 'profile',
          ignoreKey: `attendance_time_out_self_${uid}`,
        },
      }));
    }

    const timeInMillis = toMillis(data.timeIn);
    const expectedMillis = timeInMillis
      ? timeInMillis +
        settings.fullDayHours * 60 * 60 * 1000 +
        settings.graceMinutes * 60 * 1000
      : 0;
    const hasCompleteTimes = Boolean(timeInText) && Boolean(timeOutText);
    const isLate = !hasCompleteTimes && Boolean(timeInText) && !timeOutText && Boolean(expectedMillis) && now >= expectedMillis;
    const isFlagged = !hasCompleteTimes && (data.lateTimeout === true ||
      (data.needsReview === true && String(data.notes || '').toLowerCase().includes('time out')));

    if (!hasCompleteTimes && (isLate || isFlagged)) {
      const overdueText = expectedMillis
        ? attendanceDurationText((now - expectedMillis) / 60000)
        : '';
      const adminBody = isLate
        ? `${staffName} has not timed out ${overdueText} after the expected time.`
        : `${staffName} missed time out and needs review.`;
      const selfBody = isLate
        ? `You have not timed out ${overdueText} after the expected time.`
        : 'Your time out needs review.';
      specs.push(specFor({
        type: 'attendance_late_timeout',
        title: 'Staff time out overdue',
        body: adminBody,
        dedupeKey: `attendance_late_timeout_admin_${uid}_${today}`,
        source: 'attendance',
        audience: 'admin',
        data: {
          ...shared,
          target: 'staff_attendance',
          route: 'staff_attendance',
          ignoreKey: `attendance_late_timeout_${uid}`,
          lateTimeout: true,
        },
      }));
      specs.push(specFor({
        type: 'attendance_late_timeout',
        title: 'Time out overdue',
        body: selfBody,
        dedupeKey: `attendance_late_timeout_self_${uid}_${today}`,
        source: 'attendance',
        audience: 'staff',
        targetUids: [uid],
        data: {
          ...shared,
          target: 'profile',
          route: 'profile',
          ignoreKey: `attendance_late_timeout_self_${uid}`,
          lateTimeout: true,
        },
      }));

      if (isLate && data.lateTimeout !== true && String(data.source || '') !== 'admin') {
        await doc.ref.update({
          lateTimeout: true,
          needsReview: true,
          notes: data.notes || 'Missing Time Out - past expected end time',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }
  }
  return specs;
}

async function syncSystemNotifications({ eateryId }) {
  const tenant = cleanText(eateryId, 120);
  if (!tenant) {
    const error = new Error('Tenant context required');
    error.code = 'tenant_required';
    error.status = 403;
    throw error;
  }

  const query = (collectionName, clauses) => {
    let ref = db.collection(collectionName);
    for (const [field, op, value] of clauses) {
      ref = ref.where(field, op, value);
    }
    return ref.get();
  };

  const [usersSnap, inventorySnap, ordersSnap, payablesSnap] = await Promise.all([
    query('users', [['eateryId', '==', tenant]]),
    query('inventory', [['eateryId', '==', tenant]]),
    query('orders', [['eateryId', '==', tenant]]),
    query('payables', [['eateryId', '==', tenant]]),
  ]);

  const specs = [];
  const today = manilaDateKey();

  specs.push(specFor({
    type: 'system',
    title: 'Notification history is active',
    body: 'System notifications are stored permanently in this workspace.',
    dedupeKey: `notification_history_active_${today}`,
    audience: 'all',
  }));

  const pendingStaff = snapshotDocs(usersSnap).filter((doc) => {
    const data = doc.data() || {};
    const status = cleanText(data.approvalStatus || data.status, 40).toLowerCase();
    return status === 'pending' || data.approved === false;
  });
  if (pendingStaff.length) {
    specs.push(specFor({
      type: 'staff_approval',
      title: 'Staff approvals pending',
      body: `${pendingStaff.length} staff account${pendingStaff.length === 1 ? '' : 's'} waiting for approval.`,
      dedupeKey: `staff_approvals_pending_${today}`,
      audience: 'admin',
      data: { target: 'staff', route: 'staff' },
    }));
  }

  for (const doc of snapshotDocs(inventorySnap)) {
    const data = doc.data() || {};
    const quantity = itemQuantity(data);
    const threshold = itemThreshold(data);
    const name = cleanText(data.name || doc.id, 120);
    if (quantity <= 0) {
      specs.push(specFor({
        type: 'out_of_stock',
        title: 'Item out of stock',
        body: `${name} is out of stock.`,
        dedupeKey: `out_of_stock_${doc.id}`,
        audience: 'admin',
        data: {
          inventoryId: doc.id,
          quantity,
          target: 'inventory',
          route: 'inventory',
        },
      }));
    } else if (threshold > 0 && quantity <= threshold) {
      specs.push(specFor({
        type: 'low_stock',
        title: 'Low stock alert',
        body: `${name} has ${quantity} left (threshold ${threshold}).`,
        dedupeKey: `low_stock_${doc.id}`,
        audience: 'admin',
        data: {
          inventoryId: doc.id,
          quantity,
          threshold,
          target: 'inventory',
          route: 'inventory',
        },
      }));
    }
  }

  const pendingOrders = snapshotDocs(ordersSnap).filter((doc) => {
    const data = doc.data() || {};
    return cleanText(data.status, 40).toLowerCase() === 'pending';
  });
  if (pendingOrders.length) {
    specs.push(specFor({
      type: 'order',
      title: 'Pending orders',
      body: `${pendingOrders.length} order${pendingOrders.length === 1 ? '' : 's'} still waiting to be completed.`,
      dedupeKey: `pending_orders_${today}`,
      audience: 'admin',
      data: {
        count: pendingOrders.length,
        target: 'orders',
        route: 'orders',
      },
    }));
  }

  const now = Date.now();
  const sevenDays = 7 * 24 * 60 * 60 * 1000;
  for (const doc of snapshotDocs(payablesSnap)) {
    const data = doc.data() || {};
    const status = cleanText(data.status, 40).toLowerCase();
    if (status === 'paid' || status === 'settled') continue;
    const dueAt = toMillis(data.dueDate || data.dueAt);
    const vendor = cleanText(data.vendor || data.name || doc.id, 120);
    if (dueAt && dueAt < now) {
      specs.push(specFor({
        type: 'bill_overdue',
        title: 'Overdue bill',
        body: `${vendor} has an overdue payable.`,
        dedupeKey: `bill_overdue_${doc.id}`,
        audience: 'admin',
        data: {
          payableId: doc.id,
          dueAt,
          target: 'finance',
          route: 'finance',
        },
      }));
    } else if (dueAt && dueAt - now <= sevenDays) {
      specs.push(specFor({
        type: 'bill_due_soon',
        title: 'Bill due soon',
        body: `${vendor} has a payable due soon.`,
        dedupeKey: `bill_due_soon_${doc.id}`,
        audience: 'admin',
        data: {
          payableId: doc.id,
          dueAt,
          target: 'finance',
          route: 'finance',
        },
      }));
    }
  }

  const attendanceSpecs = await buildAttendanceNotificationSpecs({
    tenant,
    usersSnap,
    today,
  });
  specs.push(...attendanceSpecs);

  const results = await Promise.all(
    specs.map((spec) => writeSystemNotification({ ...spec, eateryId: tenant })),
  );
  return {
    total: results.length,
    created: results.filter((result) => result.created).length,
  };
}

function userRolesFor(role) {
  const normalized = String(role || '').trim().toLowerCase();
  if (normalized === 'admin') return ['admin', 'manager', 'staff', 'all'];
  if (normalized === 'manager' || normalized === 'owner') {
    return ['manager', 'staff', 'all'];
  }
  return ['staff', 'all'];
}

function notificationVisibleTo(data, uid, role) {
  const targets = normalizeStringList(data.targetUids);
  if (targets.length) return Boolean(uid) && targets.includes(uid);
  const roles = normalizeRoles({
    allowedRoles: data.allowedRoles,
    audience: data.audience,
    type: data.type,
    targetUids: [],
  });
  const userRoles = userRolesFor(role);
  return roles.some((item) => userRoles.includes(item));
}

function timestampIso(value) {
  if (!value) return new Date().toISOString();
  if (typeof value.toMillis === 'function') {
    return new Date(value.toMillis()).toISOString();
  }
  if (typeof value.toDate === 'function') {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) return value.toISOString();
  const parsed = Date.parse(String(value));
  return Number.isNaN(parsed) ? new Date().toISOString() : new Date(parsed).toISOString();
}

function serializeNotification(doc, uid, state = {}) {
  const data = doc.data() || {};
  const readBy = data.readBy && typeof data.readBy === 'object' ? data.readBy : {};
  const readByIso = {};
  for (const [key, value] of Object.entries(readBy)) {
    readByIso[String(key)] = timestampIso(value);
  }
  const legacyRead = data.isRead === true && Object.keys(readByIso).length === 0;
  const payload = data.data && typeof data.data === 'object' ? data.data : {};
  return {
    id: doc.id,
    eateryId: String(data.eateryId || ''),
    title: String(data.title || 'Notification'),
    body: String(data.body || ''),
    type: String(data.type || 'general'),
    source: String(data.source || payload.source || 'system'),
    audience: String(data.audience || defaultAudienceFor(data.type)),
    allowedRoles: normalizeRoles({
      allowedRoles: data.allowedRoles,
      audience: data.audience,
      type: data.type,
      targetUids: data.targetUids,
    }),
    targetUids: normalizeStringList(data.targetUids),
    dedupeKey: String(data.dedupeKey || ''),
    ignoreKey: ignoreKeyFor(data),
    route: cleanText(payload.route || payload.target, 80),
    pinned: state.pinned === true,
    ignored: state.ignored === true,
    data: payload,
    active: data.active !== false,
    isRead: Boolean(readByIso[uid] || legacyRead),
    readBy: readByIso,
    createdAt: timestampIso(data.createdAt || data.updatedAt || data.resolvedAt),
    updatedAt: timestampIso(data.updatedAt || data.createdAt),
  };
}

async function fetchEateryNotificationDocs(eateryId) {
  const snapshot = await db
    .collection('notifications')
    .where('eateryId', '==', eateryId)
    .get();
  return snapshotDocs(snapshot).filter((doc) => {
    const data = doc.data() || {};
    return data.active !== false;
  });
}

async function listSystemNotifications({ eateryId, uid, role, limit = 400 }) {
  const tenant = cleanText(eateryId, 120);
  if (!tenant) {
    const error = new Error('Tenant context required');
    error.code = 'tenant_required';
    error.status = 403;
    throw error;
  }
  const docs = await fetchEateryNotificationDocs(tenant);
  const { states, rules } = await loadUserNotificationState(uid);
  const items = [];
  for (const doc of docs) {
    const data = doc.data() || {};
    if (!notificationVisibleTo(data, uid, role)) continue;
    const state = states.get(doc.id) || {};
    if (state.removed === true) continue;

    const ignoreKey = ignoreKeyFor(data);
    const rule = rules.get(ignoreKey);
    const explicitlyIgnored = state.ignored === true;
    const createdMillis = toMillis(data.createdAt || data.updatedAt);
    const suppressed = Boolean(
      rule &&
      rule.notificationId !== doc.id &&
      (!createdMillis || !rule.ignoredAtMillis || createdMillis > rule.ignoredAtMillis),
    );
    if (!explicitlyIgnored && suppressed) continue;

    items.push(serializeNotification(doc, uid, state));
  }
  items.sort((a, b) => {
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
    return Date.parse(b.createdAt) - Date.parse(a.createdAt);
  });
  return {
    total: items.length,
    items: items.slice(0, Math.max(1, Math.min(Number(limit) || 400, 1000))),
  };
}

async function markSystemNotificationRead({ eateryId, uid, role, docId }) {
  const tenant = cleanText(eateryId, 120);
  const id = cleanText(docId, 200);
  const user = cleanText(uid, 120);
  if (!tenant || !id || !user) return false;

  const ref = db.collection('notifications').doc(id);
  const snapshot = await ref.get();
  if (!snapshot || !snapshot.exists) return false;
  const data = snapshot.data() || {};
  if (String(data.eateryId || '') !== tenant) return false;
  if (!notificationVisibleTo(data, user, role)) return false;

  const readBy = data.readBy && typeof data.readBy === 'object' ? { ...data.readBy } : {};
  const timestamp = admin.firestore.FieldValue.serverTimestamp();
  readBy[user] = timestamp;
  await ref.update({
    readBy,
    readAt: timestamp,
    updatedAt: timestamp,
  });
  return true;
}

async function markAllSystemNotificationsRead({ eateryId, uid, role }) {
  const tenant = cleanText(eateryId, 120);
  const user = cleanText(uid, 120);
  if (!tenant || !user) return 0;
  const docs = await fetchEateryNotificationDocs(tenant);
  const targets = docs.filter((doc) => {
    const data = doc.data() || {};
    if (!notificationVisibleTo(data, user, role)) return false;
    const readBy = data.readBy && typeof data.readBy === 'object' ? data.readBy : {};
    return !readBy[user];
  });
  await Promise.all(targets.map((doc) => markSystemNotificationRead({
    eateryId: tenant,
    uid: user,
    role,
    docId: doc.id,
  })));
  return targets.length;
}

async function setNotificationPreference({
  eateryId,
  uid,
  role,
  docId,
  removed,
  pinned,
  ignored,
}) {
  const tenant = cleanText(eateryId, 120);
  const id = cleanText(docId, 200);
  const user = cleanText(uid, 120);
  if (!tenant || !id || !user) return null;

  const ref = db.collection('notifications').doc(id);
  const snapshot = await ref.get();
  if (!snapshot || !snapshot.exists) return null;
  const data = snapshot.data() || {};
  if (String(data.eateryId || '') !== tenant) return null;
  if (!notificationVisibleTo(data, user, role)) return null;

  const timestamp = admin.firestore.FieldValue.serverTimestamp();
  const state = {
    eateryId: tenant,
    notificationId: id,
    uid: user,
    updatedAt: timestamp,
  };
  if (typeof removed === 'boolean') state.removed = removed;
  if (typeof pinned === 'boolean') state.pinned = pinned;
  if (typeof ignored === 'boolean') state.ignored = ignored;
  await notificationStateRef(user, id).set(state, { merge: true });

  const ignoreKey = ignoreKeyFor(data);
  if (ignored === true) {
    await notificationIgnoreRuleRef(user, ignoreKey).set({
      eateryId: tenant,
      uid: user,
      ignoreKey,
      notificationId: id,
      title: cleanText(data.title, 180),
      type: cleanText(data.type, 80),
      ignoredAt: timestamp,
      updatedAt: timestamp,
    }, { merge: true });
  } else if (ignored === false) {
    const ruleRef = notificationIgnoreRuleRef(user, ignoreKey);
    const ruleSnap = await ruleRef.get();
    if (ruleSnap && ruleSnap.exists && String(ruleSnap.data()?.notificationId || '') === id) {
      await ruleRef.delete();
    }
  }

  return {
    id,
    removed: typeof removed === 'boolean' ? removed : false,
    pinned: typeof pinned === 'boolean' ? pinned : false,
    ignored: typeof ignored === 'boolean' ? ignored : false,
  };
}

async function deactivateSystemNotification({ eateryId, docId }) {
  const tenant = cleanText(eateryId, 120);
  const id = cleanText(docId, 200);
  if (!tenant || !id) return false;
  const ref = db.collection('notifications').doc(id);
  const snapshot = await ref.get();
  if (!snapshot || !snapshot.exists) return false;
  const data = snapshot.data() || {};
  if (String(data.eateryId || '') !== tenant) return false;
  await ref.update({
    active: false,
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return true;
}

module.exports = {
  buildNotificationDocId,
  defaultAudienceFor,
  deactivateSystemNotification,
  listSystemNotifications,
  markAllSystemNotificationsRead,
  markSystemNotificationRead,
  normalizeRoles,
  notificationVisibleTo,
  rolesFor,
  setNotificationPreference,
  userRolesFor,
  writeSystemNotification,
  syncSystemNotifications,
};
