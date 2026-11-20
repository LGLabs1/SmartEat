const crypto = require('crypto');
const { admin, db } = require('../config/firebase');
const {
  OTP_TTL_MS,
  RESET_TOKEN_TTL_MS,
  RESEND_COOLDOWN_MS,
  MAX_OTP_ATTEMPTS,
  LOCKOUT_MS,
  RATE_WINDOW_MS,
  MAX_REQUESTS_PER_EMAIL,
  MAX_REQUESTS_PER_IP,
  normalizeEmail,
  isValidEmail,
  normalizePhMobile,
  isValidChannel,
  sha256Hex,
  randomOtp,
  randomToken,
  hashOtp,
  hashResetToken,
  safeEqualHex,
  validatePassword,
  getResetSecret,
  secondsUntil,
} = require('../utils/passwordReset');
const { sendPasswordResetEmail } = require('../services/emailService');
const { sendPasswordResetSms } = require('../services/smsService');

const REQUEST_COLLECTION = 'password_reset_requests';
const RATE_LIMIT_COLLECTION = 'password_reset_rate_limits';

class HttpError extends Error {
  constructor(status, code, message, retryAfterSeconds) {
    super(message);
    this.status = status;
    this.code = code;
    this.retryAfterSeconds = retryAfterSeconds;
    this.expose = true;
  }
}

function genericRequestMessage(email) {
  return `A verification code has been sent to ${email}`;
}

function requestDocId(email) {
  return sha256Hex(normalizeEmail(email));
}

function requestRef(email) {
  return db.collection(REQUEST_COLLECTION).doc(requestDocId(email));
}

function clientIp(req) {
  const raw = req.ip || req.headers['x-forwarded-for'] || '';
  return String(raw).split(',')[0].trim() || 'unknown';
}

async function consumeRateLimit(key, max, windowMs) {
  const ref = db.collection(RATE_LIMIT_COLLECTION).doc(sha256Hex(key));
  const now = Date.now();
  let retryAfterSeconds = 0;

  await db.runTransaction(async (transaction) => {
    retryAfterSeconds = 0;
    const snapshot = await transaction.get(ref);
    const data = snapshot.exists ? snapshot.data() || {} : {};
    const windowStart = data.windowStart && data.windowStart.toMillis
      ? data.windowStart.toMillis()
      : 0;
    const count = Number(data.count || 0);

    if (!windowStart || now - windowStart >= windowMs) {
      transaction.set(
        ref,
        {
          windowStart: admin.firestore.Timestamp.fromMillis(now),
          count: 1,
          updatedAt: admin.firestore.Timestamp.fromMillis(now),
        },
        { merge: true },
      );
      return;
    }

    if (count >= max) {
      retryAfterSeconds = Math.max(
        1,
        Math.ceil((windowStart + windowMs - now) / 1000),
      );
      return;
    }

    transaction.set(
      ref,
      {
        count: count + 1,
        updatedAt: admin.firestore.Timestamp.fromMillis(now),
      },
      { merge: true },
    );
  });

  if (retryAfterSeconds > 0) {
    throw new HttpError(
      429,
      'rate_limited',
      'Too many requests. Please try again later.',
      retryAfterSeconds,
    );
  }
}

function checkRequestCooldown(data) {
  if (!data) return;

  const now = Date.now();
  const lockedUntil = data.lockedUntil && data.lockedUntil.toMillis
    ? data.lockedUntil.toMillis()
    : 0;
  if (lockedUntil > now) {
    throw new HttpError(
      429,
      'locked',
      'Too many attempts. Please try again later.',
      secondsUntil(lockedUntil - now),
    );
  }

  const sentAt = data.sentAt && data.sentAt.toMillis ? data.sentAt.toMillis() : 0;
  if (sentAt && now - sentAt < RESEND_COOLDOWN_MS) {
    throw new HttpError(
      429,
      'cooldown',
      'Please wait before requesting another code.',
      secondsUntil(RESEND_COOLDOWN_MS - (now - sentAt)),
    );
  }
}

async function findAuthUser(email) {
  try {
    return await admin.auth().getUserByEmail(email);
  } catch (error) {
    if (error.code === 'auth/user-not-found') return null;
    throw error;
  }
}

async function registeredPhoneFor(uid) {
  try {
    const snapshot = await db.collection('users').doc(uid).get();
    if (!snapshot.exists) return null;
    const data = snapshot.data() || {};
    return normalizePhMobile(data.phone || data.phoneNumber);
  } catch (error) {
    return null;
  }
}

async function requestPasswordReset(req, res, next) {
  try {
    const email = normalizeEmail(req.body && req.body.email);
    const channel = String((req.body && req.body.channel) || '').trim().toLowerCase();

    if (!isValidEmail(email)) {
      throw new HttpError(400, 'invalid_email', 'Please enter a valid email address.');
    }
    if (!isValidChannel(channel)) {
      throw new HttpError(400, 'invalid_channel', 'Choose email or SMS.');
    }

    await consumeRateLimit(`request-email:${email}`, MAX_REQUESTS_PER_EMAIL, RATE_WINDOW_MS);
    await consumeRateLimit(`request-ip:${clientIp(req)}`, MAX_REQUESTS_PER_IP, RATE_WINDOW_MS);

    const ref = requestRef(email);
    const existing = await ref.get();
    const existingData = existing.exists ? existing.data() || {} : null;
    checkRequestCooldown(existingData);

    const user = await findAuthUser(email);
    if (!user || user.disabled) {
      return res.json({
        ok: true,
        message: genericRequestMessage(email),
        retryAfterSeconds: secondsUntil(RESEND_COOLDOWN_MS),
      });
    }

    let phone = null;
    if (channel === 'sms') {
      phone = await registeredPhoneFor(user.uid);
      if (!phone) {
        return res.json({
          ok: true,
          message: genericRequestMessage(email),
          retryAfterSeconds: secondsUntil(RESEND_COOLDOWN_MS),
        });
      }
    }

    const secret = getResetSecret();
    const code = randomOtp();
    const salt = crypto.randomBytes(16).toString('hex');
    const now = Date.now();

    await ref.set(
      {
        uid: user.uid,
        emailHash: requestDocId(email),
        channel,
        codeHash: hashOtp(code, salt, secret),
        salt,
        attempts: 0,
        sentAt: null,
        expiresAt: admin.firestore.Timestamp.fromMillis(now + OTP_TTL_MS),
        lockedUntil: null,
        resetTokenHash: null,
        resetTokenExpiresAt: null,
        codeUsedAt: null,
        usedAt: null,
        createdAt: admin.firestore.Timestamp.fromMillis(now),
        updatedAt: admin.firestore.Timestamp.fromMillis(now),
      },
      { merge: true },
    );

    try {
      if (channel === 'email') {
        await sendPasswordResetEmail({
          to: email,
          code,
          expiresMinutes: OTP_TTL_MS / 60000,
        });
      } else {
        await sendPasswordResetSms({
          phoneNumber: phone,
          code,
          expiresMinutes: OTP_TTL_MS / 60000,
        });
      }
    } catch (error) {
      await ref.delete().catch(() => {});
      console.error('[PasswordReset] Failed to send code:', error.message);
      throw new HttpError(
        502,
        'send_failed',
        'Unable to send the verification code right now. Please try again.',
      );
    }

    await ref.set(
      { sentAt: admin.firestore.Timestamp.now() },
      { merge: true },
    );

    return res.json({
      ok: true,
      message: genericRequestMessage(email),
      retryAfterSeconds: secondsUntil(RESEND_COOLDOWN_MS),
    });
  } catch (error) {
    return next(error);
  }
}

async function verifyPasswordResetCode(req, res, next) {
  try {
    const email = normalizeEmail(req.body && req.body.email);
    const code = String((req.body && req.body.code) || '').trim();

    if (!isValidEmail(email)) {
      throw new HttpError(400, 'invalid_email', 'Please enter a valid email address.');
    }
    if (!/^\d{6}$/.test(code)) {
      throw new HttpError(400, 'invalid_code', 'Enter the 6-digit verification code.');
    }

    await consumeRateLimit(`verify-ip:${clientIp(req)}`, 60, RATE_WINDOW_MS);

    const ref = requestRef(email);
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      throw new HttpError(400, 'invalid_code', 'Invalid or expired verification code.');
    }

    const data = snapshot.data() || {};
    if (data.usedAt || !data.codeHash || !data.salt) {
      throw new HttpError(400, 'invalid_code', 'Invalid or expired verification code.');
    }

    const now = Date.now();
    const lockedUntil = data.lockedUntil && data.lockedUntil.toMillis
      ? data.lockedUntil.toMillis()
      : 0;
    if (lockedUntil > now) {
      throw new HttpError(
        429,
        'locked',
        'Too many attempts. Please try again later.',
        secondsUntil(lockedUntil - now),
      );
    }

    const expiresAt = data.expiresAt && data.expiresAt.toMillis
      ? data.expiresAt.toMillis()
      : 0;
    if (!expiresAt || expiresAt <= now) {
      throw new HttpError(400, 'invalid_code', 'Invalid or expired verification code.');
    }

    const attempts = Number(data.attempts || 0);
    if (attempts >= MAX_OTP_ATTEMPTS) {
      const lockUntil = admin.firestore.Timestamp.fromMillis(now + LOCKOUT_MS);
      await ref.set({ lockedUntil: lockUntil, updatedAt: admin.firestore.Timestamp.now() }, { merge: true });
      throw new HttpError(
        429,
        'locked',
        'Too many attempts. Please try again later.',
        secondsUntil(LOCKOUT_MS),
      );
    }

    const secret = getResetSecret();
    const expectedHash = hashOtp(code, data.salt, secret);

    if (!safeEqualHex(expectedHash, data.codeHash)) {
      const nextAttempts = attempts + 1;
      const patch = {
        attempts: nextAttempts,
        updatedAt: admin.firestore.Timestamp.now(),
      };
      if (nextAttempts >= MAX_OTP_ATTEMPTS) {
        patch.lockedUntil = admin.firestore.Timestamp.fromMillis(now + LOCKOUT_MS);
      }
      await ref.set(patch, { merge: true });
      throw new HttpError(400, 'invalid_code', 'Invalid or expired verification code.');
    }

    const resetToken = randomToken();
    const resetTokenHash = hashResetToken(resetToken, secret);
    const resetTokenExpiresAt = admin.firestore.Timestamp.fromMillis(now + RESET_TOKEN_TTL_MS);

    await ref.set(
      {
        codeHash: null,
        salt: null,
        codeUsedAt: admin.firestore.Timestamp.now(),
        resetTokenHash,
        resetTokenExpiresAt,
        updatedAt: admin.firestore.Timestamp.now(),
      },
      { merge: true },
    );

    return res.json({
      ok: true,
      resetToken,
      expiresAt: resetTokenExpiresAt.toMillis(),
    });
  } catch (error) {
    return next(error);
  }
}

async function confirmPasswordReset(req, res, next) {
  try {
    const email = normalizeEmail(req.body && req.body.email);
    const resetToken = String((req.body && req.body.resetToken) || '').trim();
    const newPassword = String((req.body && req.body.newPassword) || '');

    if (!isValidEmail(email)) {
      throw new HttpError(400, 'invalid_email', 'Please enter a valid email address.');
    }
    if (!resetToken) {
      throw new HttpError(400, 'invalid_token', 'Invalid or expired reset token.');
    }

    const passwordError = validatePassword(newPassword);
    if (passwordError) {
      throw new HttpError(400, 'invalid_password', passwordError);
    }

    await consumeRateLimit(`confirm-ip:${clientIp(req)}`, 30, RATE_WINDOW_MS);

    const ref = requestRef(email);
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      throw new HttpError(400, 'invalid_token', 'Invalid or expired reset token.');
    }

    const data = snapshot.data() || {};
    if (data.usedAt || !data.resetTokenHash) {
      throw new HttpError(400, 'invalid_token', 'Invalid or expired reset token.');
    }

    const now = Date.now();
    const tokenExpiresAt = data.resetTokenExpiresAt && data.resetTokenExpiresAt.toMillis
      ? data.resetTokenExpiresAt.toMillis()
      : 0;
    if (!tokenExpiresAt || tokenExpiresAt <= now) {
      throw new HttpError(400, 'invalid_token', 'Invalid or expired reset token.');
    }

    const secret = getResetSecret();
    if (!safeEqualHex(hashResetToken(resetToken, secret), data.resetTokenHash)) {
      throw new HttpError(400, 'invalid_token', 'Invalid or expired reset token.');
    }

    const uid = String(data.uid || '');
    if (!uid) {
      throw new HttpError(400, 'invalid_token', 'Invalid or expired reset token.');
    }

    const user = await admin.auth().getUser(uid).catch(() => null);
    if (!user || user.disabled) {
      throw new HttpError(400, 'invalid_token', 'Invalid or expired reset token.');
    }

    await ref.set(
      {
        usedAt: admin.firestore.Timestamp.now(),
        resetTokenHash: null,
        resetTokenExpiresAt: null,
        updatedAt: admin.firestore.Timestamp.now(),
      },
      { merge: true },
    );

    await admin.auth().updateUser(uid, { password: newPassword });

    try {
      await admin.auth().revokeRefreshTokens(uid);
    } catch (error) {
      console.error('[PasswordReset] Failed to revoke refresh tokens:', error.message);
    }

    return res.json({ ok: true, message: 'Password reset successfully.' });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  HttpError,
  requestPasswordReset,
  verifyPasswordResetCode,
  confirmPasswordReset,
};
