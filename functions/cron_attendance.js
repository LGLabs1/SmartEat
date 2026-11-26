/* eslint-disable no-console */

const admin = require('firebase-admin');

const PH_OFFSET_MS = 8 * 60 * 60 * 1000;
const DEFAULT_FULL_DAY_HOURS = 8;
const DEFAULT_HALF_DAY_HOURS = 4;
const DEFAULT_GRACE_MINUTES = 10;
const STALE_SHIFT_HOURS = 20;
const LOOKBACK_DAYS = 3;

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

function formatYMD(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** A UTC-midnight Date representing the Asia/Manila calendar day. */
function phDateOnly(date) {
  const shifted = new Date(date.getTime() + PH_OFFSET_MS);
  return new Date(
    Date.UTC(
      shifted.getUTCFullYear(),
      shifted.getUTCMonth(),
      shifted.getUTCDate()
    )
  );
}

function addDays(date, days) {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === 'function') {
    try {
      return value.toDate();
    } catch (_) {
      return null;
    }
  }
  if (value instanceof Date) return value;
  if (typeof value === 'string') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (typeof value === 'number') return new Date(value);
  return null;
}

function asNumber(value, fallback) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  const parsed = Number.parseFloat(String(value || '').trim());
  return Number.isFinite(parsed) ? parsed : fallback;
}

function computeWorkUnit(hours, settings) {
  const full =
    settings.fullDayHours > 0
      ? settings.fullDayHours
      : DEFAULT_FULL_DAY_HOURS;
  let half =
    settings.halfDayHours > 0
      ? settings.halfDayHours
      : DEFAULT_HALF_DAY_HOURS;
  if (half > full) half = full;

  if (hours >= full) return 1.0;
  if (hours >= half) return 0.5;
  return 0.0;
}

function statusForUnit(unit) {
  if (unit >= 1.0) return 'present';
  if (unit > 0) return 'halfday';
  return 'short';
}

async function loadSettings(db, eateryId) {
  try {
    const snap = await db
      .collection('eateries')
      .doc(eateryId)
      .collection('settings')
      .doc('attendance')
      .get();
    const data = snap.exists ? snap.data() || {} : {};
    const graceRaw = data.graceMinutes;
    const graceMinutes = graceRaw === undefined || graceRaw === null
      ? DEFAULT_GRACE_MINUTES
      : asNumber(graceRaw, DEFAULT_GRACE_MINUTES);
    return {
      fullDayHours: asNumber(data.fullDayHours, DEFAULT_FULL_DAY_HOURS),
      halfDayHours: asNumber(data.halfDayHours, DEFAULT_HALF_DAY_HOURS),
      graceMinutes: Math.max(0, graceMinutes),
    };
  } catch (err) {
    console.warn(`Using default attendance settings for ${eateryId}:`, err);
    return {
      fullDayHours: DEFAULT_FULL_DAY_HOURS,
      halfDayHours: DEFAULT_HALF_DAY_HOURS,
      graceMinutes: DEFAULT_GRACE_MINUTES,
    };
  }
}

function legacyStatus(data) {
  const morning = data.morningCheckIn;
  const afternoon = data.afternoonCheckIn;
  if (morning && afternoon) {
    return {
      present: true,
      workUnit: 1.0,
      status: 'present',
      notes: 'Full day - both check-ins recorded',
    };
  }
  if (morning || afternoon) {
    return {
      present: true,
      workUnit: 0.5,
      status: 'halfday',
      notes: morning
        ? 'Half day - morning check-in only'
        : 'Half day - afternoon check-in only',
    };
  }
  return {
    present: false,
    workUnit: 0.0,
    status: 'absent',
    notes: 'Absent - no check-ins recorded',
  };
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
  const today = phDateOnly(now);
  const todayKey = formatYMD(today);

  const dates = [];
  for (let i = 0; i < LOOKBACK_DAYS; i++) {
    dates.push(formatYMD(addDays(today, -i)));
  }

  console.log(
    `Processing shift attendance for ${dates.join(', ')} (Asia/Manila)`
  );

  const eateriesSnap = await db.collection('eateries').get();
  const writes = [];

  for (const eateryDoc of eateriesSnap.docs) {
    const eateryId = eateryDoc.id;
    const settings = await loadSettings(db, eateryId);

    const staffSnap = await db
      .collection('eateries')
      .doc(eateryId)
      .collection('staff_profiles')
      .get();
    if (staffSnap.empty) continue;

    const staffUids = staffSnap.docs
      .map((doc) => String(doc.id || '').trim())
      .filter(Boolean);

    for (const dateKey of dates) {
      const isToday = dateKey === todayKey;

      const attendanceSnap = await db
        .collection('eateries')
        .doc(eateryId)
        .collection('staff_attendance')
        .where('date', '==', dateKey)
        .get();

      const existingByUid = new Map();
      for (const doc of attendanceSnap.docs) {
        const data = doc.data() || {};
        const uid = String(data.uid || '').trim();
        if (uid) existingByUid.set(uid, { id: doc.id, data });
      }

      for (const uid of staffUids) {
        const existing = existingByUid.get(uid);
        const docId = `${eateryId}_${uid}_${dateKey}`;
        const ref = db
          .collection('eateries')
          .doc(eateryId)
          .collection('staff_attendance')
          .doc(docId);

        if (existing) {
          const data = existing.data;

          // Admin-encoded records are manual overrides and must not be
          // recalculated by the scheduled job.
          if (String(data.source || '') === 'admin') continue;

          if (data.timeIn) {
            const timeIn = toDate(data.timeIn);
            const timeOut = toDate(data.timeOut);

            if (timeIn && timeOut) {
              const hours = Math.max(
                0,
                (timeOut.getTime() - timeIn.getTime()) / 3600000
              );
              const workUnit = computeWorkUnit(hours, settings);
              const status = statusForUnit(workUnit);

              const payload = {
                present: true,
                workUnit,
                status,
                hoursWorked: Number(hours.toFixed(2)),
                needsReview: false,
                lateTimeout: false,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                autoMarked: true,
              };
              if (!data.notes) payload.notes = 'Auto-finalized from shift times';

              if (data.workUnit !== workUnit || data.status !== status) {
                writes.push(ref.set(payload, { merge: true }));
                console.log(
                  `Finalized ${uid} as ${status} (${workUnit} unit) for ${eateryId} on ${dateKey}`
                );
              }
            } else if (timeIn && !timeOut) {
              const openHours = (now.getTime() - timeIn.getTime()) / 3600000;
              const expectedOut = new Date(
                timeIn.getTime() +
                  settings.fullDayHours * 3600000 +
                  settings.graceMinutes * 60000
              );
              if (now >= expectedOut && data.lateTimeout !== true) {
                const workUnit = computeWorkUnit(settings.fullDayHours, settings);
                writes.push(
                  ref.set(
                    {
                      present: true,
                      workUnit,
                      status: statusForUnit(workUnit),
                      hoursWorked: settings.fullDayHours,
                      needsReview: !timeOut,
                      lateTimeout: !timeOut,
                      notes: data.notes || 'Missing Time Out - past expected end time',
                      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                      autoMarked: true,
                    },
                    { merge: true }
                  )
                );
                console.log(
                  `Flagged ${uid} as late time out for ${eateryId} on ${dateKey}`
                );
              } else if (openHours > STALE_SHIFT_HOURS && data.needsReview !== true) {
                writes.push(
                  ref.set(
                    {
                      present: true,
                      workUnit: 0.0,
                      status: 'incomplete',
                      needsReview: true,
                      notes: 'Missing Time Out - needs review',
                      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                    },
                    { merge: true }
                  )
                );
                console.log(
                  `Flagged ${uid} as incomplete for ${eateryId} on ${dateKey}`
                );
              }
            }
          } else if (data.morningCheckIn || data.afternoonCheckIn) {
            const legacy = legacyStatus(data);
            writes.push(
              ref.set(
                {
                  ...legacy,
                  present: legacy.present,
                  workUnit: legacy.workUnit,
                  status: legacy.status,
                  notes: legacy.notes,
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                  autoMarked: true,
                },
                { merge: true }
              )
            );
          } else if (!isToday && data.status !== 'absent') {
            writes.push(
              ref.set(
                {
                  present: false,
                  workUnit: 0.0,
                  status: 'absent',
                  needsReview: false,
                  notes: 'Auto-marked absent - no shift recorded',
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                  autoMarked: true,
                },
                { merge: true }
              )
            );
          }
        } else if (!isToday) {
          // The business is open 24/7, so a past day without a shift is absent.
          writes.push(
            ref.set(
              {
                eateryId,
                uid,
                date: dateKey,
                present: false,
                workUnit: 0.0,
                status: 'absent',
                source: 'cron',
                needsReview: false,
                notes: 'Auto-marked absent - no shift recorded',
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                autoMarked: true,
              },
              { merge: true }
            )
          );
          console.log(`Marked ${uid} absent for ${eateryId} on ${dateKey}`);
        }
      }
    }
  }

  await Promise.all(writes);

  console.log(`Done. Wrote ${writes.length} attendance records.`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
