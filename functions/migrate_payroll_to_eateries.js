/* eslint-disable no-console */

// One-off migration: move top-level payroll_payouts into
// eateries/{eateryId}/payroll_payouts.
//
// Usage (from repo root):
//   $env:FIREBASE_SERVICE_ACCOUNT_PATH="C:\path\service-account.json"
//   node functions/migrate_payroll_to_eateries.js
//
// Env:
//   MIGRATE_DRY_RUN=true   Only report what would change.
//   DELETE_SOURCE=true     Delete the top-level docs after copying.

const admin = require('firebase-admin');
const fs = require('fs');

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
  const deleteSource = toBoolEnv('DELETE_SOURCE', false);

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  const db = admin.firestore();
  const bulk = db.bulkWriter();
  bulk.onWriteError((err) => {
    console.error('Bulk write failed:', err);
    return false;
  });

  const snap = await db.collection('payroll_payouts').get();
  let copied = 0;
  let skipped = 0;
  const byEatery = {};

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    const eateryId = String(data.eateryId || '').trim();
    if (!eateryId) {
      skipped += 1;
      console.warn(`Skipping ${doc.id}: missing eateryId`);
      continue;
    }

    const destRef = db
      .collection('eateries')
      .doc(eateryId)
      .collection('payroll_payouts')
      .doc(doc.id);

    if (!dryRun) {
      bulk.set(destRef, data, { merge: true });
      if (deleteSource) {
        bulk.delete(doc.ref);
      }
    }

    byEatery[eateryId] = (byEatery[eateryId] || 0) + 1;
    copied += 1;
  }

  if (!dryRun) {
    await bulk.close();
  } else {
    bulk.close().catch(() => null);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        dryRun,
        deleteSource,
        total: snap.size,
        copied,
        skipped,
        byEatery,
      },
      null,
      2
    )
  );
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
