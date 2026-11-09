const admin = require('firebase-admin');

/**
 * Initialize Firebase Admin once.
 * - Render/demo: set FIREBASE_SERVICE_ACCOUNT (or FIREBASE_SERVICE_ACCOUNT_KEY)
 *   to the full service-account JSON string (secret env var, never committed).
 * - Local/dev fallback: uses Application Default Credentials when no JSON env var.
 */
if (!admin.apps.length) {
  const rawJson =
    process.env.FIREBASE_SERVICE_ACCOUNT ||
    process.env.FIREBASE_SERVICE_ACCOUNT_KEY ||
    '';

  if (rawJson && rawJson.trim()) {
    try {
      const parsed = JSON.parse(rawJson);
      const opts = { credential: admin.credential.cert(parsed) };
      if (parsed.project_id) opts.projectId = parsed.project_id;
      admin.initializeApp(opts);
    } catch (e) {
      // Never log secret contents.
      throw new Error(
        'Invalid FIREBASE_SERVICE_ACCOUNT JSON. Provide a valid service-account JSON string in the environment variable.'
      );
    }
  } else {
    admin.initializeApp();
  }
}

const db = admin.firestore();

module.exports = { admin, db };
