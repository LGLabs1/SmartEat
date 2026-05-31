/* eslint-disable no-console */

const admin = require('firebase-admin');

function requireEnv(name) {
  const v = process.env[name];
  if (!v || String(v).trim() === '') {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

function parseServiceAccount(raw) {
  const trimmed = String(raw || '').trim();
  if (!trimmed) throw new Error('Empty service account secret');

  // 1) Try raw JSON first
  try {
    return JSON.parse(trimmed);
  } catch (_) {
    // continue
  }

  // 2) Try base64-encoded JSON (common workaround for multiline secrets)
  try {
    const decoded = Buffer.from(trimmed, 'base64').toString('utf8').trim();
    return JSON.parse(decoded);
  } catch (_) {
    throw new Error(
      'Invalid FIREBASE_SERVICE_ACCOUNT_JSON. Paste the full service-account JSON (starting with {) or a base64-encoded JSON string.'
    );
  }
}

function formatYMD(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function dateOnly(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

async function main() {
  const serviceAccountJson = requireEnv('FIREBASE_SERVICE_ACCOUNT_JSON');
  const serviceAccount = parseServiceAccount(serviceAccountJson);

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  const db = admin.firestore();

  const now = new Date();
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayKey = formatYMD(dateOnly(yesterday));

  console.log(`Processing attendance for ${yesterdayKey}`);

  // Get all eateries
  const eateriesSnap = await db.collection('eateries').get();

  const writes = [];

  for (const eateryDoc of eateriesSnap.docs) {
    const eateryId = eateryDoc.id;

    // Get all staff profiles for this eatery
    const staffSnap = await db
      .collection('eateries')
      .doc(eateryId)
      .collection('staff_profiles')
      .get();

    if (staffSnap.empty) continue;

    // Check existing attendance for yesterday
    const attendanceSnap = await db
      .collection('eateries')
      .doc(eateryId)
      .collection('staff_attendance')
      .where('date', '==', yesterdayKey)
      .get();

    const existingAttendance = new Map();
    for (const doc of attendanceSnap.docs) {
      const data = doc.data();
      const uid = String(data.uid || '').trim();
      if (uid) existingAttendance.set(uid, { id: doc.id, data });
    }

    // For each staff member, process their attendance
    for (const staffDoc of staffSnap.docs) {
      const uid = staffDoc.id;
      const docId = `${eateryId}_${uid}_${yesterdayKey}`;
      const ref = db
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_attendance')
        .doc(docId);

      const existing = existingAttendance.get(uid);

      if (existing) {
        // Staff has some attendance record - determine status based on check-ins
        const data = existing.data;
        const morningCheckIn = data.morningCheckIn;
        const afternoonCheckIn = data.afternoonCheckIn;

        let present, workUnit, status, notes;

        if (morningCheckIn && afternoonCheckIn) {
          // Both check-ins = Present (Full Day)
          present = true;
          workUnit = 1.0;
          status = 'present';
          notes = 'Full day - both check-ins recorded';
        } else if (morningCheckIn || afternoonCheckIn) {
          // Only one check-in = Half Day
          present = true;
          workUnit = 0.5;
          status = 'halfday';
          notes = morningCheckIn
            ? 'Half day - morning check-in only'
            : 'Half day - afternoon check-in only';
        } else {
          // No check-ins but record exists = Absent
          present = false;
          workUnit = 0.0;
          status = 'absent';
          notes = 'Absent - no check-ins recorded';
        }

        writes.push(
          ref.set({
            eateryId,
            uid,
            date: yesterdayKey,
            present,
            workUnit,
            status,
            notes,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            autoMarked: true,
          }, { merge: true })
        );

        console.log(
          `Updated ${uid} as ${status} (${workUnit} unit) for ${eateryId} on ${yesterdayKey}`
        );
      } else {
        // No attendance record at all = Absent
        writes.push(
          ref.set({
            eateryId,
            uid,
            date: yesterdayKey,
            present: false,
            workUnit: 0.0,
            status: 'absent',
            notes: 'Auto-marked absent - no check-ins',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            autoMarked: true,
          }, { merge: true })
        );

        console.log(`Marked ${uid} as absent for ${eateryId} on ${yesterdayKey}`);
      }
    }
  }

  await Promise.all(writes);

  console.log(`Done. Processed ${writes.length} attendance records.`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
