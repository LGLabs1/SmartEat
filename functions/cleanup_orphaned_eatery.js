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

async function deleteCollectionRecursive(db, collectionPath, batchSize = 100) {
  const collectionRef = db.collection(collectionPath);
  const snapshot = await collectionRef.get();

  let deletedDocs = 0;

  for (const doc of snapshot.docs) {
    // Delete all subcollections first
    const subcollections = await doc.ref.listCollections();
    for (const subcol of subcollections) {
      const subcolPath = `${collectionPath}/${doc.id}/${subcol.id}`;
      const subDeleted = await deleteCollectionRecursive(db, subcolPath, batchSize);
      deletedDocs += subDeleted;
    }
    // Delete the document
    await doc.ref.delete();
    deletedDocs++;
  }

  return deletedDocs;
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

  // The orphaned eatery document ID
  const orphanedEateryId = 'izaUOtLltteifoAZOicCCj8g9S32';

  console.log(`Checking eatery document: ${orphanedEateryId}...`);

  // Check if this is a real eatery with data
  const eateryDoc = await db.collection('eateries').doc(orphanedEateryId).get();

  if (!eateryDoc.exists) {
    console.log(JSON.stringify({
      ok: true,
      message: 'Document does not exist, nothing to delete'
    }, null, 2));
    return;
  }

  // Check for subcollections that indicate real eatery data
  const subcollections = await eateryDoc.ref.listCollections();
  const subcollectionIds = subcollections.map(c => c.id);

  console.log('Found subcollections:', subcollectionIds);

  // Only delete if it only has admin_profiles (orphaned admin data)
  const hasRealEateryData = subcollectionIds.some(id =>
    ['menu', 'inventory', 'orders', 'staff_profiles', 'staff_attendance'].includes(id)
  );

  if (hasRealEateryData) {
    console.log(JSON.stringify({
      ok: false,
      message: 'This eatery has real data (menu, inventory, orders, etc.). NOT deleting.',
      subcollections: subcollectionIds
    }, null, 2));
    return;
  }

  // Safe to delete - only has admin_profiles or is empty
  console.log('No real eatery data found. Proceeding with deletion...');

  // Delete all subcollections recursively
  let deletedCount = 0;
  for (const subcol of subcollections) {
    const subcolPath = `eateries/${orphanedEateryId}/${subcol.id}`;
    console.log(`Deleting subcollection: ${subcolPath}...`);
    const count = await deleteCollectionRecursive(db, subcolPath);
    deletedCount += count;
    console.log(`Deleted ${count} documents from ${subcol.id}`);
  }

  // Delete the main eatery document
  await eateryDoc.ref.delete();
  deletedCount++;

  console.log(JSON.stringify({
    ok: true,
    deletedCount,
    message: `Successfully deleted orphaned eatery ${orphanedEateryId} and all its subcollections`
  }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
