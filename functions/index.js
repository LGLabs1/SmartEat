const crypto = require('crypto');

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const {
  onDocumentCreated,
  onDocumentWritten,
} = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { Resend } = require('resend');
admin.initializeApp();

const RESEND_API_KEY = defineSecret('RESEND_API_KEY');
const RESEND_FROM = defineSecret('RESEND_FROM');

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function sha256Hex(input) {
  return crypto.createHash('sha256').update(input).digest('hex');
}

function randomDigits(length) {
  let out = '';
  for (let i = 0; i < length; i++) {
    out += Math.floor(Math.random() * 10);
  }
  return out;
}

function requireString(value, fieldName) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new HttpsError('invalid-argument', `${fieldName} is required`);
  }
}

exports.requestEmailVerificationCode = onCall(
  { secrets: [RESEND_API_KEY, RESEND_FROM] },
  async (request) => {
  const email = normalizeEmail(request.data?.email);
  requireString(email, 'email');

  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new HttpsError('invalid-argument', 'Invalid email');
  }

  const resendApiKey = RESEND_API_KEY.value();
  const fromEmail = RESEND_FROM.value();

  if (!resendApiKey || !fromEmail) {
    throw new HttpsError(
      'failed-precondition',
      'Email service is not configured'
    );
  }

  const emailHash = sha256Hex(email);
  const docRef = admin.firestore().collection('email_verifications').doc(emailHash);
  const now = admin.firestore.Timestamp.now();

  const existing = await docRef.get();
  if (existing.exists) {
    const data = existing.data() || {};

    if (data.lockedUntil && data.lockedUntil.toMillis && data.lockedUntil.toMillis() > Date.now()) {
      throw new HttpsError('resource-exhausted', 'Too many attempts. Try again later.');
    }

    if (data.expiresAt && data.expiresAt.toMillis && data.expiresAt.toMillis() > Date.now()) {
      const lastSentAt = data.sentAt?.toMillis ? data.sentAt.toMillis() : 0;
      if (Date.now() - lastSentAt < 30 * 1000) {
        throw new HttpsError('resource-exhausted', 'Please wait before requesting another code.');
      }
    }
  }

  const code = randomDigits(6);
  const salt = crypto.randomBytes(16).toString('hex');
  const codeHash = sha256Hex(`${code}:${salt}`);
  const verificationId = crypto.randomBytes(16).toString('hex');

  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000);

  await docRef.set(
    {
      codeHash,
      salt,
      verificationId,
      attempts: 0,
      sentAt: now,
      expiresAt,
      verifiedAt: null,
      canCreateUntil: null,
      consumedAt: null,
    },
    { merge: true }
  );

  const resend = new Resend(resendApiKey);

  await resend.emails.send({
    from: fromEmail,
    to: email,
    subject: 'Your Smart Eat verification code',
    text: `Your verification code is: ${code}\n\nThis code expires in 10 minutes.`,
  });

  return { verificationId, expiresAt: expiresAt.toMillis() };
});

exports.verifyEmailVerificationCode = onCall(async (request) => {
  const email = normalizeEmail(request.data?.email);
  const code = String(request.data?.code || '').trim();
  const verificationId = String(request.data?.verificationId || '').trim();

  requireString(email, 'email');
  requireString(code, 'code');
  requireString(verificationId, 'verificationId');

  if (!/^\d{6}$/.test(code)) {
    throw new HttpsError('invalid-argument', 'Code must be 6 digits');
  }

  const emailHash = sha256Hex(email);
  const docRef = admin.firestore().collection('email_verifications').doc(emailHash);
  const snap = await docRef.get();

  if (!snap.exists) {
    throw new HttpsError('not-found', 'Verification request not found');
  }

  const data = snap.data() || {};

  if (data.consumedAt) {
    throw new HttpsError('failed-precondition', 'Verification already used');
  }

  if (data.verificationId !== verificationId) {
    throw new HttpsError('permission-denied', 'Invalid verificationId');
  }

  if (!data.expiresAt || data.expiresAt.toMillis() <= Date.now()) {
    throw new HttpsError('deadline-exceeded', 'Code expired');
  }

  const attempts = Number(data.attempts || 0);
  if (attempts >= 8) {
    await docRef.set(
      {
        lockedUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000),
      },
      { merge: true }
    );
    throw new HttpsError('resource-exhausted', 'Too many attempts. Try again later.');
  }

  const expectedHash = sha256Hex(`${code}:${data.salt}`);
  if (expectedHash !== data.codeHash) {
    await docRef.set({ attempts: attempts + 1 }, { merge: true });
    throw new HttpsError('permission-denied', 'Invalid code');
  }

  const verifiedAt = admin.firestore.Timestamp.now();
  const canCreateUntil = admin.firestore.Timestamp.fromMillis(Date.now() + 15 * 60 * 1000);

  await docRef.set(
    {
      verifiedAt,
      canCreateUntil,
      attempts: attempts,
    },
    { merge: true }
  );

  return { ok: true, canCreateUntil: canCreateUntil.toMillis() };
});

exports.createAccountAfterEmailOtp = onCall(async (request) => {
  const email = normalizeEmail(request.data?.email);
  const password = String(request.data?.password || '');
  const verificationId = String(request.data?.verificationId || '').trim();

  const firstName = String(request.data?.firstName || '').trim();
  const lastName = String(request.data?.lastName || '').trim();
  const eateryName = String(request.data?.eateryName || '').trim();
  const phoneNumber = String(request.data?.phoneNumber || '').trim();

  requireString(email, 'email');
  requireString(password, 'password');
  requireString(verificationId, 'verificationId');
  requireString(firstName, 'firstName');
  requireString(lastName, 'lastName');
  requireString(eateryName, 'eateryName');
  requireString(phoneNumber, 'phoneNumber');

  if (password.length < 6) {
    throw new HttpsError('invalid-argument', 'Password must be at least 6 characters');
  }

  const emailHash = sha256Hex(email);
  const docRef = admin.firestore().collection('email_verifications').doc(emailHash);
  const snap = await docRef.get();

  if (!snap.exists) {
    throw new HttpsError('not-found', 'Verification request not found');
  }

  const data = snap.data() || {};

  if (data.consumedAt) {
    throw new HttpsError('failed-precondition', 'Verification already used');
  }

  if (data.verificationId !== verificationId) {
    throw new HttpsError('permission-denied', 'Invalid verificationId');
  }

  if (!data.verifiedAt) {
    throw new HttpsError('failed-precondition', 'Email not verified');
  }

  if (!data.canCreateUntil || data.canCreateUntil.toMillis() <= Date.now()) {
    throw new HttpsError('deadline-exceeded', 'Verification expired. Please request a new code.');
  }

  let userRecord;
  try {
    userRecord = await admin.auth().createUser({
      email,
      password,
    });
  } catch (e) {
    throw new HttpsError('already-exists', 'Email already in use');
  }

  const displayName = [firstName, lastName].filter(Boolean).join(' ');
  const normalizedPhone = normalizePhMobile(phoneNumber) || phoneNumber;

  await admin
    .firestore()
    .collection('users')
    .doc(userRecord.uid)
    .set(
      {
        firstName,
        lastName,
        displayName,
        eateryName,
        phone: normalizedPhone,
        phoneNumber: normalizedPhone,
        email,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  await docRef.set({ consumedAt: admin.firestore.Timestamp.now() }, { merge: true });

  const customToken = await admin.auth().createCustomToken(userRecord.uid);
  return { uid: userRecord.uid, customToken };
});

exports.onOrderCreatedAdjustMenuServings = onDocumentCreated(
  'eateries/{eateryId}/orders/{orderId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const orderRef = snap.ref;
    const order = snap.data() || {};
    const eateryId = String(event.params?.eateryId || order.eateryId || '').trim();
    const items = Array.isArray(order.items) ? order.items : [];

    if (!eateryId || items.length === 0) {
      await orderRef.set(
        {
          status: 'rejected',
          rejectReason: 'Invalid order payload',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      return;
    }

    try {
      if (String(order.eateryId || '').trim() !== eateryId) {
        await orderRef.set(
          {
            eateryId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      await admin.firestore().runTransaction(async (tx) => {
        const norm = (s) =>
          String(s || '')
            .toLowerCase()
            .replace(/\s+/g, ' ')
            .replace(/[^a-z0-9\s]/g, '')
            .trim();

        const menuReads = [];
        for (const it of items) {
          const menuItemId = String(it.menuItemId || '').trim();
          const quantity = Number(it.quantity || 0);
          if (!menuItemId || !Number.isFinite(quantity) || quantity <= 0) {
            throw new Error('Invalid order item');
          }
          const menuRef = admin
            .firestore()
            .collection('eateries')
            .doc(eateryId)
            .collection('menu')
            .doc(menuItemId);
          menuReads.push({ menuRef, quantity });
        }

        const menuSnaps = await Promise.all(
          menuReads.map(({ menuRef }) => tx.get(menuRef))
        );

        const invLinkReads = [];
        const recipeReads = [];
        const drinkFallbackReads = [];
        for (let i = 0; i < menuReads.length; i++) {
          const { menuRef, quantity } = menuReads[i];
          const menuSnap = menuSnaps[i];
          if (!menuSnap.exists) {
            throw new Error('Menu item not found');
          }
          const menu = menuSnap.data() || {};
          const menuEateryId = String(menu.eateryId || '').trim();
          if (menuEateryId && menuEateryId !== eateryId) {
            throw new Error('Access denied');
          }

          const isDrinkCategory = (() => {
            const normKey = (v) =>
              String(v || '')
                .toLowerCase()
                .replace(/\s+/g, ' ')
                .trim();

            const cat = normKey(menu.category);
            if (cat === 'drinks' || cat === 'drink') return true;

            const cats = Array.isArray(menu.categories) ? menu.categories : [];
            return cats.some((c) => {
              const k = normKey(c);
              return k === 'drinks' || k === 'drink';
            });
          })();

          const inventoryItemId = String(menu.inventoryItemId || '').trim();
          if (inventoryItemId) {
            const invRef = admin
              .firestore()
              .collection('eateries')
              .doc(eateryId)
              .collection('inventory')
              .doc(inventoryItemId);
            invLinkReads.push({ invRef, quantity, menuRef, menu });
          } else if (isDrinkCategory) {
            drinkFallbackReads.push({ quantity, menuRef, menu });
          } else {
            const currentServings = Number(menu.availableServings || 0);
            if (!Number.isFinite(currentServings) || currentServings < quantity) {
              throw new Error('Insufficient available servings');
            }

            const nextServings = currentServings - quantity;
            tx.update(menuRef, {
              availableServings: nextServings,
              isAvailable: nextServings > 0,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }

          const recipeId = String(menu.recipeId || '').trim();
          if (recipeId) {
            const recipeRef = admin
              .firestore()
              .collection('eateries')
              .doc(eateryId)
              .collection('recipes')
              .doc(recipeId);
            recipeReads.push({ recipeRef, quantity, menuItemId });
          }
        }

        const needsInventoryByName = drinkFallbackReads.length > 0 || recipeReads.length > 0;
        let inventoryByName = null;
        if (needsInventoryByName) {
          const inventoryQuery = admin
            .firestore()
            .collection('eateries')
            .doc(eateryId)
            .collection('inventory');
          const inventorySnap = await tx.get(inventoryQuery);

          inventoryByName = new Map();
          inventorySnap.forEach((doc) => {
            const data = doc.data() || {};
            const nameKey = norm(data.name);
            if (!nameKey) return;
            if (!inventoryByName.has(nameKey)) {
              inventoryByName.set(nameKey, { ref: doc.ref, data });
            }
          });
        }

        if (invLinkReads.length > 0) {
          const invSnaps = await Promise.all(
            invLinkReads.map(({ invRef }) => tx.get(invRef))
          );

          for (let i = 0; i < invLinkReads.length; i++) {
            const { quantity, menuRef, menu } = invLinkReads[i];
            const invSnap = invSnaps[i];
            if (!invSnap.exists) {
              throw new Error('Linked inventory item not found');
            }
            const inv = invSnap.data() || {};
            const invEateryId = String(inv.eateryId || '').trim();
            if (!invEateryId || invEateryId !== eateryId) {
              throw new Error('Access denied');
            }

            const currentStock = Number(inv.currentStock || 0);
            if (!Number.isFinite(currentStock) || currentStock < quantity) {
              throw new Error('Insufficient inventory stock');
            }

            const nextStock = currentStock - quantity;
            tx.update(invSnap.ref, {
              currentStock: nextStock,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            tx.update(menuRef, {
              availableServings: nextStock,
              isAvailable: nextStock > 0,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        }

        if (drinkFallbackReads.length > 0) {
          if (!inventoryByName) {
            throw new Error('Inventory not available');
          }

          for (const { quantity, menuRef, menu } of drinkFallbackReads) {
            const menuName = String(menu.name || '').trim();
            const key = norm(menuName);
            if (!key) {
              throw new Error('Invalid drink menu name');
            }

            const inv = inventoryByName.get(key);
            if (!inv) {
              throw new Error(`Missing inventory item for drink: ${menuName}`);
            }

            const currentStock = Number(inv.data?.currentStock || 0);
            if (!Number.isFinite(currentStock) || currentStock < quantity) {
              throw new Error('Insufficient inventory stock');
            }

            const nextStock = currentStock - quantity;
            tx.update(inv.ref, {
              currentStock: nextStock,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            tx.update(menuRef, {
              inventoryItemId: inv.ref.id,
              availableServings: nextStock,
              isAvailable: nextStock > 0,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            inventoryByName.set(key, {
              ref: inv.ref,
              data: { ...inv.data, currentStock: nextStock },
            });
          }
        }

        if (recipeReads.length > 0) {
          const recipeSnaps = await Promise.all(
            recipeReads.map(({ recipeRef }) => tx.get(recipeRef))
          );

          if (!inventoryByName) {
            throw new Error('Inventory not available');
          }

          const requiredByInventoryRefPath = new Map();

          for (let i = 0; i < recipeReads.length; i++) {
            const { quantity } = recipeReads[i];
            const recipeSnap = recipeSnaps[i];
            if (!recipeSnap.exists) {
              throw new Error('Recipe not found');
            }
            const recipe = recipeSnap.data() || {};
            const baseServings = Number(recipe.baseServings || 1);
            const factor =
              Number.isFinite(baseServings) && baseServings > 0
                ? quantity / baseServings
                : quantity;

            const ingredients = Array.isArray(recipe.ingredients)
              ? recipe.ingredients
              : [];
            for (const ing of ingredients) {
              const ingName = String(ing?.name || '').trim();
              if (!ingName) continue;

              const key = norm(ingName);
              const inv = inventoryByName.get(key);
              if (!inv) {
                throw new Error(`Missing inventory item: ${ingName}`);
              }

              const invUnit = String(inv.data?.unit || '').trim();
              const ingUnit = String(ing?.unit || '').trim();
              if (invUnit && ingUnit && norm(invUnit) !== norm(ingUnit)) {
                throw new Error(`Unit mismatch for: ${ingName}`);
              }

              const baseQty = Number(ing?.quantity || 0);
              if (!Number.isFinite(baseQty) || baseQty <= 0) continue;
              const requiredQty = baseQty * factor;

              const refPath = inv.ref.path;
              requiredByInventoryRefPath.set(
                refPath,
                (requiredByInventoryRefPath.get(refPath) || 0) + requiredQty
              );
            }
          }

          for (const [refPath, requiredQtyRaw] of requiredByInventoryRefPath) {
            const requiredQty = Number(requiredQtyRaw || 0);
            if (!Number.isFinite(requiredQty) || requiredQty <= 0) continue;

            const inv = Array.from(inventoryByName.values()).find(
              (v) => v.ref.path === refPath
            );
            if (!inv) {
              throw new Error('Inventory item not found');
            }

            const currentStock = Number(inv.data?.currentStock || 0);
            if (!Number.isFinite(currentStock) || currentStock < requiredQty) {
              throw new Error('Insufficient inventory stock');
            }

            const nextStock = currentStock - requiredQty;
            tx.update(inv.ref, {
              currentStock: nextStock,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          }
        }

        tx.set(
          orderRef,
          {
            status: 'completed',
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      });
    } catch (e) {
      await orderRef.set(
        {
          status: 'rejected',
          rejectReason: String(e?.message || e || 'Order rejected'),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
  }
);

Object.assign(
  exports,
  createSmsFunctions({
    admin,
    onCall,
    HttpsError,
    onDocumentWritten,
    onSchedule,
    PHILSMS_API_TOKEN,
  })
);
