const admin = require('firebase-admin');

// Initialize firebase-admin once.
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

module.exports = { admin, db };
