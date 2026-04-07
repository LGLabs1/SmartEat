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

async function deleteCollection(db, collectionPath, batchSize = 100) {
  const collectionRef = db.collection(collectionPath);
  const query = collectionRef.limit(batchSize);

  let deleted = 0;

  while (true) {
    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
      deleted++;
    }
    await batch.commit();

    if (snapshot.size < batchSize) break;
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

  console.log('Deleting root-level staff_attendance collection...');
  const deleted = await deleteCollection(db, 'staff_attendance');

  console.log(JSON.stringify({
    ok: true,
    deleted,
    message: deleted > 0
      ? `Successfully deleted ${deleted} documents from root staff_attendance collection`
      : 'No documents found in root staff_attendance collection'
  }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
