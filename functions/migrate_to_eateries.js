/* eslint-disable no-console */

const admin = require('firebase-admin');
const fs = require('fs');

function requireEnv(name) {
  const v = process.env[name];
  if (!v || String(v).trim() === '') {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

function readServiceAccountFromPath(p) {
  const filePath = String(p || '').trim();
  if (!filePath) return null;
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch (e) {
    throw new Error(`Failed to read service account file: ${filePath}`);
  }
}

function parseServiceAccount(raw) {
  const trimmed = String(raw || '').trim();
  if (!trimmed) throw new Error('Empty service account secret');

  try {
    return JSON.parse(trimmed);
  } catch (_) {
    // continue
  }

  try {
    const decoded = Buffer.from(trimmed, 'base64').toString('utf8').trim();
    return JSON.parse(decoded);
  } catch (_) {
    throw new Error(
      'Invalid FIREBASE_SERVICE_ACCOUNT_JSON. Paste the full service-account JSON (starting with {) or a base64-encoded JSON string.'
    );
  }
}

function toBoolEnv(name, defaultValue = false) {
  const v = process.env[name];
  if (v == null) return defaultValue;
  const s = String(v).trim().toLowerCase();
  if (s === '1' || s === 'true' || s === 'yes' || s === 'y') return true;
  if (s === '0' || s === 'false' || s === 'no' || s === 'n') return false;
  return defaultValue;
}

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

async function copyTopLevelCollectionByEatery(db, bulk, srcCollection, destSubcollection, opts) {
  const dryRun = Boolean(opts?.dryRun);
  const idStrategy = opts?.idStrategy;

  const snap = await db.collection(srcCollection).get();
  let copied = 0;
  let skipped = 0;

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const eateryId = String(data.eateryId || '').trim();
    if (!eateryId) {
      skipped += 1;
      continue;
    }

    const destId = (() => {
      if (typeof idStrategy === 'function') {
        const v = idStrategy({ docId: doc.id, data, eateryId });
        const s = String(v || '').trim();
        return s || doc.id;
      }
      return doc.id;
    })();

    const destRef = db
      .collection('eateries')
      .doc(eateryId)
      .collection(destSubcollection)
      .doc(destId);

    if (!dryRun) {
      bulk.set(destRef, data, { merge: true });
    }
    copied += 1;
  }

  return { srcCollection, destSubcollection, copied, skipped, total: snap.size };
}

async function copyAnalyticsDaily(db, bulk, opts) {
  const dryRun = Boolean(opts?.dryRun);

  const rootSnap = await db.collection('analytics_daily').get();
  let copied = 0;
  let skipped = 0;

  for (const eateryDoc of rootSnap.docs) {
    const eateryId = String(eateryDoc.id || '').trim();
    if (!eateryId) continue;

    const daysSnap = await db
      .collection('analytics_daily')
      .doc(eateryId)
      .collection('days')
      .get();

    for (const dayDoc of daysSnap.docs) {
      const data = dayDoc.data() || {};
      const dayKey = String(data.date || dayDoc.id || '').trim();
      if (!dayKey) {
        skipped += 1;
        continue;
      }

      const destRef = db
        .collection('eateries')
        .doc(eateryId)
        .collection('analytics_daily')
        .doc(dayKey);

      if (!dryRun) {
        bulk.set(destRef, { ...data, date: dayKey }, { merge: true });
      }
      copied += 1;
    }
  }

  return { name: 'analytics_daily', copied, skipped, totalEateries: rootSnap.size };
}

async function copyPredictions(db, bulk, opts) {
  const dryRun = Boolean(opts?.dryRun);

  const snap = await db.collection('predictions').get();
  let copied = 0;

  for (const doc of snap.docs) {
    const eateryId = String(doc.id || '').trim();
    if (!eateryId) continue;
    const data = doc.data() || {};

    const destRef = db
      .collection('eateries')
      .doc(eateryId)
      .collection('predictions')
      .doc('latest');

    if (!dryRun) {
      bulk.set(destRef, data, { merge: true });
    }
    copied += 1;
  }

  return { name: 'predictions', copied, total: snap.size };
}

async function ensureEateryDocs(db, bulk, eateryIds, opts) {
  const dryRun = Boolean(opts?.dryRun);

  const ids = Array.from(new Set(eateryIds)).filter(Boolean);
  const parts = chunk(ids, 500);

  let createdOrMerged = 0;

  for (const group of parts) {
    const reads = await Promise.all(group.map((id) => db.collection('eateries').doc(id).get()));
    for (let i = 0; i < group.length; i++) {
      const id = group[i];
      const exists = reads[i]?.exists === true;
      if (exists) continue;
      const ref = db.collection('eateries').doc(id);
      if (!dryRun) {
        bulk.set(
          ref,
          {
            eateryId: id,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
      createdOrMerged += 1;
    }
  }

  return { ensured: ids.length, createdOrMerged };
}

async function createAdminProfilesFromUsers(db, bulk, opts) {
  const dryRun = Boolean(opts?.dryRun);

  const snap = await db.collection('users').get();
  let created = 0;
  let skipped = 0;

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const eateryId = String(data.eateryId || '').trim();
    const uid = String(doc.id || '').trim();
    
    // Check if user is admin
    const isAdmin = data.isAdmin === true || 
                    String(data.role || '').trim().toLowerCase() === 'admin';
    
    if (!eateryId || !uid || !isAdmin) {
      skipped += 1;
      continue;
    }

    const destRef = db
      .collection('eateries')
      .doc(eateryId)
      .collection('admin_profiles')
      .doc(uid);

    const profileData = {
      eateryId: eateryId,
      uid: uid,
      email: data.email || '',
      firstName: data.firstName || '',
      lastName: data.lastName || '',
      position: data.position || 'Administrator',
      status: 'active',
      createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (!dryRun) {
      bulk.set(destRef, profileData, { merge: true });
    }
    created += 1;
  }

  return { name: 'admin_profiles', created, skipped, total: snap.size };
}

async function collectEateryIdsFromCollection(db, srcCollection) {
  const snap = await db.collection(srcCollection).get();
  const out = new Set();
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const eateryId = String(data.eateryId || '').trim();
    if (eateryId) out.add(eateryId);
  }
  return Array.from(out);
}

async function main() {
  const serviceAccountJson =
    process.env.FIREBASE_SERVICE_ACCOUNT_JSON ||
    readServiceAccountFromPath(process.env.FIREBASE_SERVICE_ACCOUNT_PATH) ||
    readServiceAccountFromPath(process.env.GOOGLE_APPLICATION_CREDENTIALS);

  if (!serviceAccountJson || String(serviceAccountJson).trim() === '') {
    throw new Error(
      'Missing credentials. Set FIREBASE_SERVICE_ACCOUNT_JSON (raw/base64) OR set FIREBASE_SERVICE_ACCOUNT_PATH to a downloaded service-account JSON file path.'
    );
  }
  const serviceAccount = parseServiceAccount(serviceAccountJson);
  const dryRun = toBoolEnv('MIGRATE_DRY_RUN', false);

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  const db = admin.firestore();
  const bulk = db.bulkWriter();
  const eateryIds = new Set();

  for (const id of await collectEateryIdsFromCollection(db, 'menu')) eateryIds.add(id);
  for (const id of await collectEateryIdsFromCollection(db, 'inventory')) eateryIds.add(id);
  for (const id of await collectEateryIdsFromCollection(db, 'orders')) eateryIds.add(id);
  for (const id of await collectEateryIdsFromCollection(db, 'staff_profiles')) eateryIds.add(id);
  for (const id of await collectEateryIdsFromCollection(db, 'staff_attendance')) eateryIds.add(id);

  const ensureRes = await ensureEateryDocs(db, bulk, Array.from(eateryIds), { dryRun });

  const results = [];

  results.push(
    await copyTopLevelCollectionByEatery(db, bulk, 'menu', 'menu', {
      dryRun,
    })
  );

  results.push(
    await copyTopLevelCollectionByEatery(db, bulk, 'inventory', 'inventory', {
      dryRun,
    })
  );

  results.push(
    await copyTopLevelCollectionByEatery(db, bulk, 'orders', 'orders', {
      dryRun,
    })
  );

  results.push(
    await copyTopLevelCollectionByEatery(db, bulk, 'staff_profiles', 'staff_profiles', {
      dryRun,
      idStrategy: ({ data, docId }) => String(data.uid || '').trim() || docId,
    })
  );

  results.push(
    await copyTopLevelCollectionByEatery(db, bulk, 'staff_attendance', 'staff_attendance', {
      dryRun,
    })
  );

  // Create admin_profiles from users with isAdmin=true
  results.push(await createAdminProfilesFromUsers(db, bulk, { dryRun }));

  results.push(await copyAnalyticsDaily(db, bulk, { dryRun }));
  results.push(await copyPredictions(db, bulk, { dryRun }));

  if (!dryRun) {
    await bulk.close();
  } else {
    bulk.close().catch(() => null);
  }

  console.log(JSON.stringify({ ok: true, dryRun, ensureRes, results }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
