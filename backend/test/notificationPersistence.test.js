const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');

const firestoreStub = {
  FieldValue: { serverTimestamp: () => 'SERVER_TIMESTAMP' },
  Timestamp: { fromDate: (date) => ({ timestamp: date.toISOString() }) },
};

function loadService(dbStub) {
  const originalLoad = Module._load;
  Module._load = function patchedLoad(request) {
    if (request === '../config/firebase') {
      return { admin: { firestore: firestoreStub }, db: dbStub };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('../src/services/notificationService');
  } finally {
    Module._load = originalLoad;
    delete require.cache[require.resolve('../src/services/notificationService')];
  }
}

function makeWriteDb({ existingKeys = [], createdIds = [] } = {}) {
  const existing = new Set(existingKeys);
  const refFor = (id) => ({
    get: async () => ({ exists: existing.has(id) }),
    create: async (payload) => {
      if (existing.has(id)) {
        const error = new Error('already exists');
        error.code = '6';
        throw error;
      }
      createdIds.push({ id, payload });
      existing.add(id);
    },
  });
  return {
    collection(name) {
      assert.equal(name, 'notifications');
      return { doc: (id) => refFor(id) };
    },
  };
}

function makeRes() {
  return {
    statusCode: 200,
    payload: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.payload = payload;
      return this;
    },
  };
}

function loadController(serviceStub) {
  const originalLoad = Module._load;
  Module._load = function patchedLoad(request) {
    if (request === '../middleware/auth') {
      return { requireTenant: (req) => req.user?.eateryId || null };
    }
    if (request === '../services/notificationService') return serviceStub;
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('../src/controllers/notificationController');
  } finally {
    Module._load = originalLoad;
    delete require.cache[require.resolve('../src/controllers/notificationController')];
  }
}

test('notification doc ids are deterministic and sanitized', () => {
  const service = loadService(makeWriteDb());
  assert.equal(
    service.buildNotificationDocId('eatery-a', 'low stock / today'),
    'eatery-a_low_stock_today',
  );
});

test('notification writer stores role metadata and is idempotent', async () => {
  const created = [];
  const service = loadService(makeWriteDb({ createdIds: created }));
  const first = await service.writeSystemNotification({
    eateryId: 'eatery-a',
    dedupeKey: 'low_stock_1',
    type: 'low_stock',
    title: 'Low stock',
    body: 'Rice is low',
    createdAt: '2026-11-23T00:00:00.000Z',
  });

  assert.equal(first.created, true);
  assert.equal(created.length, 1);
  assert.deepEqual(created[0].payload.allowedRoles, ['admin', 'manager']);
  assert.equal(created[0].payload.source, 'system');
  assert.equal(created[0].payload.active, true);
  assert.equal(created[0].payload.audience, 'admin');

  const second = await service.writeSystemNotification({
    eateryId: 'eatery-a',
    dedupeKey: 'low_stock_1',
    type: 'low_stock',
    title: 'Low stock',
    body: 'Rice is low',
  });
  assert.equal(second.created, false);
  assert.equal(created.length, 1);
});

test('notification sync always creates a permanent history record', async () => {
  const created = [];
  let maxWhereClauses = 0;
  const dbStub = {
    collection(name) {
      if (name === 'notifications') {
        return {
          doc: (id) => ({
            get: async () => ({ exists: false }),
            create: async (payload) => {
              created.push({ id, payload });
            },
          }),
        };
      }
      if (name === 'users') {
        const usersStub = {
          where: () => usersStub,
          get: async () => ({ docs: [] }),
          doc: () => ({
            collection: (collectionName) => {
              assert.ok(
                collectionName === 'notificationStates' ||
                  collectionName === 'notificationIgnoreRules',
              );
              return { get: async () => ({ docs: [] }) };
            },
          }),
        };
        return usersStub;
      }
      if (name === 'eateries') {
        return {
          doc: () => ({
            collection: () => ({
              doc: () => ({ get: async () => ({ exists: false, data: () => ({}) }) }),
              where: () => ({ get: async () => ({ docs: [] }) }),
              get: async () => ({ docs: [] }),
            }),
          }),
        };
      }
      let whereClauses = 0;
      const queryStub = {
        where: () => {
          whereClauses += 1;
          maxWhereClauses = Math.max(maxWhereClauses, whereClauses);
          return queryStub;
        },
        get: async () => ({ docs: [] }),
      };
      return queryStub;
    },
  };
  const service = loadService(dbStub);
  const result = await service.syncSystemNotifications({ eateryId: 'eatery-a' });

  assert.equal(result.total, 1);
  assert.equal(result.created, 1);
  assert.equal(maxWhereClauses, 1);
  assert.equal(created[0].payload.type, 'system');
  assert.equal(created[0].payload.title, 'Notification history is active');
  assert.deepEqual(created[0].payload.allowedRoles, ['all', 'staff', 'admin', 'manager']);
});

test('notification list hides admin-only records from staff and serializes timestamps', async () => {
  const docs = [
    {
      id: 'admin-doc',
      data: () => ({
        eateryId: 'eatery-a',
        title: 'Admin alert',
        body: 'Sensitive',
        type: 'order',
        audience: 'admin',
        allowedRoles: ['admin', 'manager'],
        createdAt: { toMillis: () => Date.parse('2026-11-23T00:00:00.000Z') },
      }),
    },
    {
      id: 'staff-doc',
      data: () => ({
        eateryId: 'eatery-a',
        title: 'Shift reminder',
        body: 'Staff only',
        type: 'attendance',
        audience: 'staff',
        allowedRoles: ['staff', 'admin', 'manager'],
        createdAt: { toMillis: () => Date.parse('2026-11-22T00:00:00.000Z') },
      }),
    },
  ];
  const dbStub = {
    collection(name) {
      if (name === 'users') {
        return {
          doc: () => ({
            collection: (collectionName) => {
              assert.ok(
                collectionName === 'notificationStates' ||
                  collectionName === 'notificationIgnoreRules',
              );
              return { get: async () => ({ docs: [] }) };
            },
          }),
        };
      }
      assert.equal(name, 'notifications');
      const queryStub = {
        where: () => queryStub,
        get: async () => ({ docs }),
      };
      return queryStub;
    },
  };
  const service = loadService(dbStub);
  const staff = await service.listSystemNotifications({
    eateryId: 'eatery-a',
    uid: 'u1',
    role: 'staff',
  });
  assert.equal(staff.items.length, 1);
  assert.equal(staff.items[0].id, 'staff-doc');
  assert.equal(staff.items[0].createdAt, '2026-11-22T00:00:00.000Z');

  const admin = await service.listSystemNotifications({
    eateryId: 'eatery-a',
    uid: 'u1',
    role: 'admin',
  });
  assert.equal(admin.items.length, 2);
});

test('mark read stores a per-user read marker', async () => {
  const updates = [];
  const existing = {
    exists: true,
    data: () => ({
      eateryId: 'eatery-a',
      title: 'Reminder',
      body: 'Read me',
      type: 'general',
      audience: 'all',
      allowedRoles: ['all', 'staff', 'admin', 'manager'],
    }),
  };
  const dbStub = {
    collection() {
      return {
        doc: () => ({
          get: async () => existing,
          update: async (payload) => updates.push(payload),
        }),
      };
    },
  };
  const service = loadService(dbStub);
  const marked = await service.markSystemNotificationRead({
    eateryId: 'eatery-a',
    uid: 'u1',
    role: 'staff',
    docId: 'eatery-a_doc',
  });
  assert.equal(marked, true);
  assert.equal(updates.length, 1);
  assert.ok(updates[0].readBy.u1);
});

test('notification controller rejects privilege escalation and allows self-targeted records', async () => {
  const calls = [];
  const serviceStub = {
    writeSystemNotification: async (payload) => {
      calls.push(payload);
      return { id: 'doc', created: true };
    },
    listSystemNotifications: async () => ({ total: 0, items: [] }),
    syncSystemNotifications: async () => ({ total: 0, created: 0 }),
    markSystemNotificationRead: async () => true,
    markAllSystemNotificationsRead: async () => 0,
    deactivateSystemNotification: async () => true,
    setNotificationPreference: async () => null,
  };
  const controller = loadController(serviceStub);

  const deniedRes = makeRes();
  await controller.recordNotification({
    user: { uid: 'u1', eateryId: 'eatery-a', role: 'staff' },
    body: { type: 'order', title: 'Order', body: 'New order', audience: 'admin' },
  }, deniedRes);
  assert.equal(deniedRes.statusCode, 403);
  assert.equal(calls.length, 0);

  const allowedRes = makeRes();
  await controller.recordNotification({
    user: { uid: 'u1', eateryId: 'eatery-a', role: 'staff' },
    body: {
      type: 'general',
      title: 'Reminder',
      body: 'Your shift starts soon',
      audience: 'staff',
      targetUids: ['u1'],
    },
  }, allowedRes);
  assert.equal(allowedRes.statusCode, 201);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].eateryId, 'eatery-a');
});
