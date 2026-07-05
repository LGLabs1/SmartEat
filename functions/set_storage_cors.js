/**
 * One-off script to set CORS rules on Firebase Storage bucket.
 * Run with: node set_storage_cors.js
 *
 * This is required for Flutter Web to upload images to Firebase Storage.
 * Without CORS, the browser blocks the PUT request and the upload hangs.
 */
const admin = require('firebase-admin');

admin.initializeApp();

const corsConfig = [
  {
    origin: ['*'],
    method: ['GET', 'HEAD', 'PUT', 'POST', 'DELETE'],
    responseHeader: ['Content-Type', 'Access-Control-Allow-Origin'],
    maxAgeSeconds: 3600,
  },
];

// Try both bucket name formats since Firebase has migrated naming conventions
const bucketNames = [
  'smart-eat-2eaf7.firebasestorage.app',
  'smart-eat-2eaf7.appspot.com',
];

async function setCors() {
  for (const bucketName of bucketNames) {
    try {
      const bucket = admin.storage().bucket(bucketName);
      await bucket.setCorsConfiguration(corsConfig);
      console.log(`✅ CORS configuration applied to: gs://${bucketName}`);
      console.log('Firebase Storage will now accept uploads from Flutter Web.');
      process.exit(0);
    } catch (err) {
      console.log(`⚠️  Bucket "${bucketName}": ${err.message}`);
    }
  }
  console.error('');
  console.error('❌ Could not set CORS on any bucket. Make sure:');
  console.error('  1. GOOGLE_APPLICATION_CREDENTIALS points to a valid service account JSON');
  console.error('  2. The service account has Storage Admin permissions');
  console.error('  3. The bucket name in this script matches your Firebase project');
}

setCors();
