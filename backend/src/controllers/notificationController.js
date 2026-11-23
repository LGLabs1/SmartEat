const { requireTenant } = require('../middleware/auth');
const {
  deactivateSystemNotification,
  listSystemNotifications,
  markAllSystemNotificationsRead,
  markSystemNotificationRead,
  setNotificationPreference,
  syncSystemNotifications,
  writeSystemNotification,
} = require('../services/notificationService');

const PRIVILEGED_ROLES = new Set(['admin', 'manager']);

function fail(res, status, code, message) {
  return res.status(status).json({ error: message, code });
}

function bodyOf(req) {
  return req.body && typeof req.body === 'object' ? req.body : {};
}

function stringList(value) {
  if (Array.isArray(value)) return value.map((item) => String(item || '').trim()).filter(Boolean);
  const single = String(value || '').trim();
  return single ? [single] : [];
}

function roleOf(req) {
  return String(req.user?.role || 'staff').trim().toLowerCase();
}

function canRecordFor(req, body) {
  if (PRIVILEGED_ROLES.has(roleOf(req))) return true;

  const targets = stringList(body.targetUids);
  if (targets.some((uid) => uid !== req.user.uid)) return false;

  const audience = String(body.audience || '').toLowerCase();
  if (!targets.length && (audience === 'admin' || audience === 'manager')) {
    return false;
  }
  return true;
}

async function listNotifications(req, res) {
  const eateryId = requireTenant(req, res);
  if (!eateryId) return;
  try {
    const result = await listSystemNotifications({
      eateryId,
      uid: req.user.uid,
      role: roleOf(req),
      limit: req.query.limit,
    });
    return res.status(200).json({ data: result });
  } catch (error) {
    console.error('Notification list error:', error.message);
    return fail(res, 500, 'notification_list_failed', 'Notification list failed');
  }
}

async function recordNotification(req, res) {
  const eateryId = requireTenant(req, res);
  if (!eateryId) return;

  const body = bodyOf(req);
  if (!canRecordFor(req, body)) {
    return fail(res, 403, 'insufficient_permissions', 'Insufficient permissions');
  }

  try {
    const result = await writeSystemNotification({
      eateryId,
      title: body.title,
      body: body.body,
      type: body.type,
      source: body.source || 'client_mirror',
      audience: body.audience,
      allowedRoles: body.allowedRoles,
      targetUids: body.targetUids,
      dedupeKey: body.dedupeKey,
      createdAt: body.createdAt,
      data: body.data,
      preserveReadState: Boolean(body.preserveReadState),
    });
    return res.status(201).json({ data: result });
  } catch (error) {
    const status = Number(error && error.status) || 500;
    const code = String(error && error.code) || 'notification_write_failed';
    if (status >= 500) console.error('Notification write error:', error.message);
    return fail(
      res,
      status,
      code,
      status < 500 ? (error && error.message) || 'Invalid notification payload' : 'Notification write failed',
    );
  }
}

async function syncNotifications(req, res) {
  const eateryId = requireTenant(req, res);
  if (!eateryId) return;

  try {
    const result = await syncSystemNotifications({ eateryId });
    return res.status(200).json({ data: result });
  } catch (error) {
    console.error('Notification sync error:', error.message);
    return fail(res, 500, 'notification_sync_failed', 'Notification sync failed');
  }
}

async function markRead(req, res) {
  const eateryId = requireTenant(req, res);
  if (!eateryId) return;
  try {
    const marked = await markSystemNotificationRead({
      eateryId,
      uid: req.user.uid,
      role: roleOf(req),
      docId: req.params.id,
    });
    if (!marked) return fail(res, 404, 'notification_not_found', 'Notification not found');
    return res.status(200).json({ data: { id: req.params.id, marked } });
  } catch (error) {
    console.error('Notification read error:', error.message);
    return fail(res, 500, 'notification_read_failed', 'Notification read failed');
  }
}

async function markAllRead(req, res) {
  const eateryId = requireTenant(req, res);
  if (!eateryId) return;
  try {
    const result = await markAllSystemNotificationsRead({
      eateryId,
      uid: req.user.uid,
      role: roleOf(req),
    });
    return res.status(200).json({ data: { marked: result } });
  } catch (error) {
    console.error('Notification read-all error:', error.message);
    return fail(res, 500, 'notification_read_failed', 'Notification read failed');
  }
}

async function updateNotificationPreference(req, res) {
  const eateryId = requireTenant(req, res);
  if (!eateryId) return;
  const body = bodyOf(req);
  const booleanOrUndefined = (value) => typeof value === 'boolean' ? value : undefined;
  try {
    const result = await setNotificationPreference({
      eateryId,
      uid: req.user.uid,
      role: roleOf(req),
      docId: req.params.id,
      removed: booleanOrUndefined(body.removed),
      pinned: booleanOrUndefined(body.pinned),
      ignored: booleanOrUndefined(body.ignored),
    });
    if (!result) return fail(res, 404, 'notification_not_found', 'Notification not found');
    return res.status(200).json({ data: result });
  } catch (error) {
    console.error('Notification preference error:', error.message);
    return fail(res, 500, 'notification_preference_failed', 'Notification update failed');
  }
}

async function deleteNotification(req, res) {
  const eateryId = requireTenant(req, res);
  if (!eateryId) return;
  if (!PRIVILEGED_ROLES.has(roleOf(req))) {
    return fail(res, 403, 'insufficient_permissions', 'Insufficient permissions');
  }
  try {
    const removed = await deactivateSystemNotification({
      eateryId,
      docId: req.params.id,
    });
    if (!removed) return fail(res, 404, 'notification_not_found', 'Notification not found');
    return res.status(200).json({ data: { id: req.params.id, removed } });
  } catch (error) {
    console.error('Notification delete error:', error.message);
    return fail(res, 500, 'notification_delete_failed', 'Notification delete failed');
  }
}

module.exports = {
  deleteNotification,
  listNotifications,
  markAllRead,
  markRead,
  recordNotification,
  syncNotifications,
  updateNotificationPreference,
};
