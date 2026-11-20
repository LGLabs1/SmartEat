const crypto = require('crypto');

const EMAIL_REGEX = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const OTP_TTL_MS = 10 * 60 * 1000;
const RESET_TOKEN_TTL_MS = 10 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_OTP_ATTEMPTS = 5;
const LOCKOUT_MS = 15 * 60 * 1000;
const RATE_WINDOW_MS = 60 * 60 * 1000;
const MAX_REQUESTS_PER_EMAIL = 5;
const MAX_REQUESTS_PER_IP = 20;
const PASSWORD_MIN_LENGTH = 6;
const PASSWORD_MAX_LENGTH = 128;

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

function isValidEmail(value) {
  return EMAIL_REGEX.test(normalizeEmail(value));
}

function normalizePhMobile(value) {
  let digits = String(value || '').trim().replace(/[^\d+]/g, '');
  if (digits.startsWith('+')) digits = digits.slice(1);
  digits = digits.replace(/\D/g, '');

  if (digits.startsWith('00')) digits = digits.slice(2);

  if (digits.startsWith('63')) {
    // Already country-coded.
  } else if (digits.startsWith('0')) {
    digits = `63${digits.slice(1)}`;
  } else if (digits.length === 10 && digits.startsWith('9')) {
    digits = `63${digits}`;
  } else {
    return null;
  }

  return /^639\d{9}$/.test(digits) ? digits : null;
}

function isValidChannel(value) {
  return value === 'email' || value === 'sms';
}

function sha256Hex(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function randomOtp() {
  return String(crypto.randomInt(0, 1000000)).padStart(6, '0');
}

function randomToken() {
  return crypto.randomBytes(32).toString('hex');
}

function getResetSecret() {
  const secret = String(process.env.PASSWORD_RESET_SECRET || '').trim();
  if (!secret) {
    const error = new Error('PASSWORD_RESET_SECRET is not configured');
    error.code = 'reset_secret_missing';
    throw error;
  }
  return secret;
}

function hashWithSecret(value, secret = getResetSecret()) {
  return crypto.createHmac('sha256', secret).update(String(value)).digest('hex');
}

function hashOtp(code, salt, secret = getResetSecret()) {
  return hashWithSecret(`${code}:${salt}`, secret);
}

function hashResetToken(token, secret = getResetSecret()) {
  return hashWithSecret(token, secret);
}

function safeEqualHex(left, right) {
  const a = Buffer.from(String(left || ''), 'hex');
  const b = Buffer.from(String(right || ''), 'hex');
  if (a.length === 0 || a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

function validatePassword(password) {
  const value = String(password || '');
  if (value.length < PASSWORD_MIN_LENGTH) {
    return `Password must be at least ${PASSWORD_MIN_LENGTH} characters`;
  }
  if (value.length > PASSWORD_MAX_LENGTH) {
    return `Password must be at most ${PASSWORD_MAX_LENGTH} characters`;
  }
  return null;
}

function secondsUntil(ms) {
  return Math.max(0, Math.ceil(ms / 1000));
}

module.exports = {
  EMAIL_REGEX,
  OTP_TTL_MS,
  RESET_TOKEN_TTL_MS,
  RESEND_COOLDOWN_MS,
  MAX_OTP_ATTEMPTS,
  LOCKOUT_MS,
  RATE_WINDOW_MS,
  MAX_REQUESTS_PER_EMAIL,
  MAX_REQUESTS_PER_IP,
  PASSWORD_MIN_LENGTH,
  PASSWORD_MAX_LENGTH,
  normalizeEmail,
  isValidEmail,
  normalizePhMobile,
  isValidChannel,
  sha256Hex,
  randomOtp,
  randomToken,
  getResetSecret,
  hashWithSecret,
  hashOtp,
  hashResetToken,
  safeEqualHex,
  validatePassword,
  secondsUntil,
};
