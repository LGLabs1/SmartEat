const crypto = require('crypto');
const axios = require('axios');

const IPROG_ENDPOINT = 'https://www.iprogsms.com/api/v1/sms_messages';
const RATE_WINDOW_MS = parseInt(process.env.SMS_RATE_WINDOW_MS, 10) || 60 * 60 * 1000;
const MAX_PER_UID = parseInt(process.env.SMS_MAX_PER_UID, 10) || 10;
const MAX_PER_IP = parseInt(process.env.SMS_MAX_PER_IP, 10) || 20;
const MAX_PER_PHONE = parseInt(process.env.SMS_MAX_PER_PHONE, 10) || 5;

const rateBuckets = new Map();

function fingerprint(value) {
  return crypto
    .createHash('sha256')
    .update(String(value || ''))
    .digest('hex')
    .slice(0, 16);
}

function bucketKey(scope, value) {
  return `${scope}:${fingerprint(value)}`;
}

function pruneBuckets(now) {
  if (rateBuckets.size < 1000) return;
  for (const [key, bucket] of rateBuckets) {
    if (bucket.resetAt <= now) rateBuckets.delete(key);
  }
}

function consumeSmsRateLimit({ uid, ip, phone }) {
  const now = Date.now();
  pruneBuckets(now);

  const dimensions = [
    ['uid', uid || 'anonymous', MAX_PER_UID],
    ['ip', ip || 'unknown', MAX_PER_IP],
    ['phone', phone || 'unknown', MAX_PER_PHONE],
  ];

  let retryAfterSeconds = 0;
  for (const [scope, value, max] of dimensions) {
    const bucket = rateBuckets.get(bucketKey(scope, value));
    if (bucket && bucket.resetAt > now && bucket.count >= max) {
      retryAfterSeconds = Math.max(
        retryAfterSeconds,
        Math.ceil((bucket.resetAt - now) / 1000),
      );
    }
  }

  if (retryAfterSeconds > 0) {
    return { allowed: false, retryAfterSeconds: Math.max(1, retryAfterSeconds) };
  }

  for (const [scope, value] of dimensions) {
    const key = bucketKey(scope, value);
    const bucket = rateBuckets.get(key);
    if (!bucket || bucket.resetAt <= now) {
      rateBuckets.set(key, { count: 1, resetAt: now + RATE_WINDOW_MS });
    } else {
      bucket.count += 1;
    }
  }

  return { allowed: true };
}

function resetSmsRateLimits() {
  rateBuckets.clear();
}

function describeProviderFailure(status) {
  if (status === 400) return 'SMS provider rejected the request.';
  if (status === 401 || status === 403) return 'SMS provider authentication failed.';
  if (status === 429) return 'SMS provider is rate limiting requests.';
  if (status >= 500) return 'SMS provider is temporarily unavailable.';
  return 'SMS provider request failed.';
}

function extractProviderMessage(data) {
  let raw = '';
  if (typeof data === 'string' && data.trim()) {
    raw = data.trim();
  } else if (data && typeof data === 'object') {
    if (typeof data.message === 'string' && data.message.trim()) raw = data.message.trim();
    else if (typeof data.error === 'string' && data.error.trim()) raw = data.error.trim();
    else if (typeof data.detail === 'string' && data.detail.trim()) raw = data.detail.trim();
  }
  if (!raw) return '';
  if (/(api[_-]?token|authorization|bearer|secret|password|private[_-]?key)\s*[:=]/i.test(raw)) {
    return '';
  }
  return raw.slice(0, 200);
}

async function sendSmsMessage({ phoneNumber, message }) {
  const apiToken = String(
    process.env.IPROG_SMS_API_TOKEN || process.env.SMS_API_TOKEN || '',
  ).trim();
  if (!apiToken) {
    const error = new Error('SMS provider token is not configured on the server');
    error.status = 500;
    error.code = 'sms_not_configured';
    throw error;
  }

  const response = await axios.post(
    IPROG_ENDPOINT,
    {
      api_token: apiToken,
      phone_number: String(phoneNumber),
      message: String(message),
    },
    {
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      timeout: 60000,
      validateStatus: () => true,
    },
  );

  return { status: response.status, data: response.data };
}

async function sendPasswordResetSms({ phoneNumber, code, expiresMinutes }) {
  const message =
    `SmartEat: Your password reset code is ${code}. ` +
    `It expires in ${expiresMinutes} minutes. ` +
    'If you did not request this, ignore this message.';

  const result = await sendSmsMessage({ phoneNumber, message });
  if (result.status < 200 || result.status >= 300) {
    const error = new Error(describeProviderFailure(result.status));
    error.status = 502;
    error.code = 'sms_send_failed';
    throw error;
  }

  return { status: result.status, message: 'SMS sent' };
}

module.exports = {
  extractProviderMessage,
  describeProviderFailure,
  fingerprint,
  consumeSmsRateLimit,
  resetSmsRateLimits,
  sendSmsMessage,
  sendPasswordResetSms,
};
