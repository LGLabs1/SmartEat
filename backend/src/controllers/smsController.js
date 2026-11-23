const {
  consumeSmsRateLimit,
  describeProviderFailure,
  fingerprint,
  sendSmsMessage,
} = require('../services/smsService');
const { normalizePhMobile } = require('../utils/passwordReset');
const { sendDailySummaryForAllEateries } = require('../services/dailySummarySmsService');

const ALLOWED_PURPOSES = new Set([
  'test',
  'low_stock',
  'bill_reminder',
  'daily_summary',
  'order',
  'reminder',
  'attendance',
  'staff_approval',
]);
const PRIVILEGED_ROLES = new Set(['admin', 'manager']);
const MAX_MESSAGE_LENGTH = parseInt(process.env.SMS_MAX_MESSAGE_LENGTH, 10) || 459;

function normalizePurpose(value) {
  const normalized = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return ALLOWED_PURPOSES.has(normalized) ? normalized : null;
}

function getClientIp(req) {
  return String(req.ip || req.socket?.remoteAddress || 'unknown');
}

function audit(req, event, details = {}) {
  const entry = {
    at: new Date().toISOString(),
    event,
    uid: req.user?.uid ? fingerprint(req.user.uid) : null,
    eateryId: details.eateryId || req.user?.eateryId || null,
    role: req.user?.role || null,
    purpose: details.purpose || null,
    ip: getClientIp(req) === 'unknown' ? null : fingerprint(getClientIp(req)),
    phoneTail: details.phoneTail || null,
    status: details.status || null,
    retryAfterSeconds: details.retryAfterSeconds || null,
    messageId: details.messageId || null,
  };
  console.info(`[SMS audit] ${JSON.stringify(entry)}`);
}

function errorResponse(res, status, code, message, retryAfterSeconds) {
  const payload = { status, code, message };
  if (retryAfterSeconds) payload.retryAfterSeconds = retryAfterSeconds;
  return res.status(status).json(payload);
}

function deny(req, res, event, status, code, message, details = {}) {
  audit(req, event, details);
  return errorResponse(res, status, code, message, details.retryAfterSeconds);
}

/**
 * POST /api/sms/send
 * Restricted, audited proxy for allowlisted transactional SMS purposes.
 */
async function sendSms(req, res) {
  const body = req.body && typeof req.body === 'object' ? req.body : {};

  if (!PRIVILEGED_ROLES.has(String(req.user?.role || '').toLowerCase())) {
    return deny(req, res, 'sms_denied_role', 403, 'insufficient_permissions', 'Insufficient permissions');
  }

  const uid = String(req.user.uid || '');
  const eateryId = String(req.user.eateryId || '').trim();
  if (!uid || !eateryId) {
    return deny(req, res, 'sms_denied_tenant', 403, 'tenant_required', 'Tenant context required');
  }

  const purpose = normalizePurpose(body.purpose ?? body.type);
  if (!purpose) {
    return deny(req, res, 'sms_invalid_purpose', 400, 'invalid_purpose', 'Unsupported SMS purpose', { eateryId });
  }

  const phone = normalizePhMobile(body.phone_number ?? body.phoneNumber ?? body.phone);
  if (!phone) {
    return deny(req, res, 'sms_invalid_phone', 400, 'invalid_phone', 'A valid Philippine mobile number is required', { eateryId, purpose });
  }

  const message = typeof body.message === 'string' ? body.message.trim() : '';
  if (!message) {
    return deny(req, res, 'sms_invalid_message', 400, 'invalid_message', 'A non-empty message is required', {
      eateryId,
      purpose,
      phoneTail: phone.slice(-4),
    });
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    return deny(req, res, 'sms_message_too_long', 400, 'message_too_long', `Message exceeds ${MAX_MESSAGE_LENGTH} characters`, {
      eateryId,
      purpose,
      phoneTail: phone.slice(-4),
    });
  }

  const rate = consumeSmsRateLimit({ uid, ip: getClientIp(req), phone });
  if (!rate.allowed) {
    return deny(req, res, 'sms_rate_limited', 429, 'rate_limited', 'Too many SMS requests. Please try again later.', {
      eateryId,
      purpose,
      phoneTail: phone.slice(-4),
      retryAfterSeconds: rate.retryAfterSeconds,
    });
  }

  try {
    const response = await sendSmsMessage({ phoneNumber: phone, message });
    const status = Number(response.status) || 502;
    const ok = status >= 200 && status < 300;

    if (ok) {
      const rawId = response.data && typeof response.data === 'object'
        ? (response.data.message_id || response.data.id || response.data.messageId)
        : null;
      const messageId = rawId == null ? null : String(rawId).slice(0, 128);
      audit(req, 'sms_sent', {
        eateryId,
        purpose,
        phoneTail: phone.slice(-4),
        status,
        messageId,
      });
      return res.status(200).json({
        status: 200,
        message: 'SMS sent',
        message_id: messageId,
        purpose,
      });
    }

    const publicStatus = status === 429 ? 429 : 502;
    audit(req, 'sms_provider_failed', {
      eateryId,
      purpose,
      phoneTail: phone.slice(-4),
      status,
    });
    return errorResponse(
      res,
      publicStatus,
      status === 429 ? 'sms_provider_rate_limited' : 'sms_provider_error',
      describeProviderFailure(status),
    );
  } catch (error) {
    audit(req, 'sms_provider_error', { eateryId, purpose, phoneTail: phone.slice(-4) });
    return errorResponse(res, 502, 'sms_provider_error', 'SMS provider request failed');
  }
}

async function sendDailySummaryCron(req, res) {
  try {
    const result = await sendDailySummaryForAllEateries({ now: new Date() });
    console.info(`[SMS cron] ${JSON.stringify(result)}`);
    return res.status(200).json({ status: 200, data: result });
  } catch (error) {
    console.error('[SMS cron] failed:', error.message);
    return errorResponse(res, 500, 'daily_summary_cron_failed', 'Daily summary cron failed');
  }
}

module.exports = { sendDailySummaryCron, sendSms };
