const admin = require('firebase-admin');

function readServiceAccountFromPath(path) {
  if (!path) return null;
  try {
    const fs = require('fs');
    return fs.readFileSync(path, 'utf8');
  } catch (e) {
    throw new Error(`Failed to read service account file: ${path}`);
  }
}

function parseServiceAccount(raw) {
  if (!raw || String(raw).trim() === '') return null;
  const str = String(raw).trim();
  if (str.startsWith('{')) {
    try {
      return JSON.parse(str);
    } catch (e) {
      throw new Error('Invalid JSON in service account content');
    }
  }
  try {
    const decoded = Buffer.from(str, 'base64').toString('utf8');
    return JSON.parse(decoded);
  } catch (e) {
    throw new Error(
      'Invalid FIREBASE_SERVICE_ACCOUNT_JSON. Paste the full service-account JSON (starting with {) or a base64-encoded JSON string.'
    );
  }
}

async function deleteSubcollection(db, eateryId, subcollectionName) {
  const collectionRef = db.collection('eateries').doc(eateryId).collection(subcollectionName);
  let batch = db.batch();
  let count = 0;
  let deleted = 0;

  while (true) {
    const snapshot = await collectionRef.limit(500).get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
      count++;
      deleted++;

      if (count === 500) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }

    if (snapshot.size < 500) break;
  }

  if (count > 0) {
    await batch.commit();
  }

  return deleted;
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

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  const db = admin.firestore();

  // The specific eatery document to delete
  const eateryId = 'izaUOtLltteifoAZOicCCj8g9S32';

  console.log(`Force deleting eatery: ${eateryId}...`);

  // Step 1: Delete all subcollections
  const subcollections = ['admin_profiles'];
  let totalDeleted = 0;

  for (const subcol of subcollections) {
    console.log(`Deleting ${subcol}...`);
    const count = await deleteSubcollection(db, eateryId, subcol);
    totalDeleted += count;
    console.log(`Deleted ${count} documents from ${subcol}`);
  }

  // Step 2: Delete the eatery document itself
  console.log('Deleting eatery document...');
  await db.collection('eateries').doc(eateryId).delete();
  totalDeleted++;

  console.log(JSON.stringify({
    ok: true,
    totalDeleted,
    message: `Successfully force-deleted eatery ${eateryId} and all its subcollections`
  }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
