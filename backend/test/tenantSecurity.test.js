const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');

function clearCache(relativePath) {
  delete require.cache[require.resolve(relativePath)];
}

function loadWithStubs(relativePath, stubs) {
  clearCache(relativePath);
  clearCache('../src/middleware/auth');
  clearCache('../src/config/firebase');

  const originalLoad = Module._load;
  Module._load = function patchedLoad(request, parent, isMain) {
    if (Object.prototype.hasOwnProperty.call(stubs, request)) return stubs[request];
    return originalLoad.apply(this, arguments);
  };
  try {
    return require(relativePath);
  } finally {
    Module._load = originalLoad;
  }
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

test('verifyToken resolves tenant from claim, then Firestore, never from client headers', async () => {
  const decoded = {
    u1: { uid: 'u1', email: 'u1@example.com', eateryId: 'claim-tenant', role: 'admin' },
    u2: { uid: 'u2', email: 'u2@example.com', role: 'staff' },
    u3: { uid: 'u3', email: 'u3@example.com', role: 'staff' },
  };
  const users = { u2: { eateryId: 'firestore-tenant' } };
  const dbStub = {
    collection(name) {
      assert.equal(name, 'users');
      return {
        doc(id) {
          return {
            get: async () => (users[id]
              ? { exists: true, data: () => users[id] }
              : { exists: false, data: () => ({}) }),
          };
        },
      };
    },
  };
  const firebaseStub = {
    admin: { auth: () => ({ verifyIdToken: async (token) => decoded[token] || null }) },
    db: dbStub,
  };
  const auth = loadWithStubs('../src/middleware/auth', {
    '../config/firebase': firebaseStub,
  });

  const reqClaim = {
    headers: { authorization: 'Bearer u1', 'x-eatery-id': 'attacker-tenant' },
  };
  const resClaim = makeRes();
  let nextCalled = false;
  await auth.verifyToken(reqClaim, resClaim, () => { nextCalled = true; });
  assert.equal(nextCalled, true);
  assert.equal(reqClaim.user.eateryId, 'claim-tenant');
  assert.equal(reqClaim.tenantId, 'claim-tenant');

  const reqFirestore = {
    headers: { authorization: 'Bearer u2', 'x-eatery-id': 'attacker-tenant' },
  };
  const resFirestore = makeRes();
  await auth.verifyToken(reqFirestore, resFirestore, () => {});
  assert.equal(resFirestore.statusCode, 200);
  assert.equal(reqFirestore.user.eateryId, 'firestore-tenant');
  assert.equal(reqFirestore.tenantId, 'firestore-tenant');

  const reqNoTenant = { headers: { authorization: 'Bearer u3', 'x-eatery-id': 'attacker-tenant' } };
  const resNoTenant = makeRes();
  let rejectedNext = false;
  await auth.verifyToken(reqNoTenant, resNoTenant, () => { rejectedNext = true; });
  assert.equal(rejectedNext, false);
  assert.equal(resNoTenant.statusCode, 403);
  assert.equal(resNoTenant.payload.code, 'tenant_required');
  assert.equal(reqNoTenant.user, undefined);
});

test('optionalAuth never assigns a client-supplied tenant', async () => {
  const decoded = { ok: { uid: 'u9', role: 'admin' } };
  const firebaseStub = {
    admin: {
      auth: () => ({
        verifyIdToken: async (token) => {
          if (token === 'bad') throw new Error('invalid token');
          return decoded[token];
        },
      }),
    },
    db: {
      collection: () => ({
        doc: () => ({ get: async () => ({ exists: false }) }),
      }),
    },
  };
  const auth = loadWithStubs('../src/middleware/auth', {
    '../config/firebase': firebaseStub,
  });

  const req = {
    headers: { authorization: 'Bearer ok', 'x-eatery-id': 'attacker-tenant' },
    body: { eateryId: 'attacker-tenant' },
  };
  const res = makeRes();
  let nextCalled = false;
  await auth.optionalAuth(req, res, () => { nextCalled = true; });
  assert.equal(nextCalled, true);
  assert.equal(req.user, undefined);
  assert.equal(req.tenantId, undefined);

  const badReq = { headers: { authorization: 'Bearer bad' } };
  await auth.optionalAuth(badReq, makeRes(), () => {});
  assert.equal(badReq.user, undefined);
});

test('analytics queries use only the trusted tenant even with hostile client tenant fields', async () => {
  const whereCalls = [];
  const query = {
    where(field, op, value) {
      whereCalls.push({ field, op, value });
      return this;
    },
    orderBy() {
      return this;
    },
    async get() {
      return { docs: [], size: 0, empty: true };
    },
  };
  const dbStub = {
    collection: () => query,
    FieldValue: { increment: (value) => value },
  };
  const controller = loadWithStubs('../src/controllers/analyticsController', {
    '../config/firebase': { admin: {}, db: dbStub },
  });

  const req = {
    user: { uid: 'u1', eateryId: 'tenant-a', role: 'admin' },
    tenantId: 'tenant-a',
    headers: { 'x-eatery-id': 'tenant-b' },
    query: { eateryId: 'tenant-b', days: '7' },
    body: { eateryId: 'tenant-b' },
  };
  const res = makeRes();
  await controller.getDailySalesAnalytics(req, res);

  assert.equal(res.statusCode, 200);
  const tenantFilters = whereCalls.filter((call) => call.field === 'eateryId');
  assert.ok(tenantFilters.length > 0);
  assert.ok(tenantFilters.every((call) => call.value === 'tenant-a'));
  assert.equal(tenantFilters.some((call) => call.value === 'tenant-b'), false);
});

test('inventory controller ignores client tenant fields and denies cross-tenant items', async () => {
  const calls = [];
  const inventoryStub = {
    create: async (data) => {
      calls.push(['create', data]);
      return { id: 'new', ...data };
    },
    getAll: async (eateryId) => {
      calls.push(['getAll', eateryId]);
      return [];
    },
    getByCategory: async (eateryId, category) => {
      calls.push(['getByCategory', eateryId, category]);
      return [];
    },
    getById: async (id) => ({
      id,
      eateryId: 'tenant-b',
      name: 'Foreign item',
      currentStock: 1,
      unitCost: 1,
    }),
    update: async () => ({}),
    updateStock: async () => ({}),
    getLowStock: async () => [],
    recordUsage: async () => ({}),
    getUsageHistory: async () => [],
    getAnalytics: async () => ({}),
    delete: async () => {},
  };
  const controller = loadWithStubs('../src/controllers/inventoryController', {
    '../models/Inventory': inventoryStub,
    '../models/InventoryLog': { create: async () => ({}) },
    '../models/DamagedItem': { create: async () => ({}), getByEatery: async () => [] },
    '../config/firebase': { admin: {}, db: {} },
  });

  const baseReq = {
    user: { uid: 'u1', eateryId: 'tenant-a', role: 'admin' },
    tenantId: 'tenant-a',
    headers: { 'x-eatery-id': 'tenant-b' },
    query: { eateryId: 'tenant-b' },
    body: { eateryId: 'tenant-b' },
    params: { id: 'foreign-item' },
  };

  const itemRes = makeRes();
  await controller.getInventoryItem(baseReq, itemRes);
  assert.equal(itemRes.statusCode, 403);
  assert.equal(itemRes.payload.error, 'Access denied');

  const listRes = makeRes();
  await controller.getInventoryItems(baseReq, listRes);
  assert.equal(listRes.statusCode, 200);
  assert.deepEqual(calls.find((call) => call[0] === 'getAll'), ['getAll', 'tenant-a']);

  const createReq = {
    ...baseReq,
    body: {
      name: 'Rice',
      category: 'Grains',
      currentStock: 10,
      unit: 'kg',
      minStock: 2,
      unitCost: 50,
      eateryId: 'tenant-b',
      tenantId: 'tenant-b',
    },
  };
  const createRes = makeRes();
  await controller.createInventoryItem(createReq, createRes);
  assert.equal(createRes.statusCode, 201);
  const created = calls.find((call) => call[0] === 'create')[1];
  assert.equal(created.eateryId, 'tenant-a');
  assert.equal(created.tenantId, undefined);
});
