const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const projectId = 'demo-smarteat-rules';
const [emulatorHost, emulatorPort] = (
  process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8085'
).split(':');
const rules = fs.readFileSync(
  path.join(__dirname, '..', '..', 'firestore.rules'),
  'utf8',
);

let env;

test.before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules,
      host: emulatorHost,
      port: Number(emulatorPort),
    },
  });
});

test.after(async () => {
  if (env) await env.cleanup();
});

test.beforeEach(async () => {
  await env.clearFirestore();
});

async function seed(builder) {
  await env.withSecurityRulesDisabled(async (context) => {
    await builder(context.firestore());
  });
}

function user(eateryId, role, approved) {
  return {
    eateryId,
    role,
    isAdmin: role === 'admin',
    approved,
    firstName: 'Seed',
    email: `${role}@example.com`,
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

const joinMetadata = (eateryId, ownerUid, name) => ({
  eateryId,
  ownerUid,
  name,
  createdAt: new Date(),
  updatedAt: new Date(),
});

async function seedBase() {
  await seed(async (db) => {
    await db.doc('eateries/E1').set(joinMetadata('E1', 'admin', 'Main'));
    await db.doc('eateries/E2').set(joinMetadata('E2', 'other', 'Other'));
    await db.doc('users/admin').set(user('E1', 'admin', true));
    await db.doc('users/staff').set(user('E1', 'staff', true));
    await db.doc('users/pending').set(user('E1', 'staff', false));
    await db.doc('users/other').set(user('E2', 'admin', true));
    await db.doc('users/other_staff').set(user('E2', 'staff', false));
  });
}

const db = (uid) => env.authenticatedContext(uid).firestore();

const notification = (eateryId, overrides = {}) => ({
  eateryId,
  title: 'Notice',
  body: 'Something happened',
  type: 'info',
  source: 'system',
  audience: 'all',
  targetUids: [],
  dedupeKey: 'notice_1',
  data: {},
  active: true,
  ...overrides,
});

test('users: role and admin escalation is denied', async () => {
  await seedBase();
  const admin = db('admin');
  const staff = db('staff');

  await assertFails(staff.doc('users/staff').update({ role: 'admin' }));
  await assertFails(staff.doc('users/staff').update({ isAdmin: true }));
  await assertFails(admin.doc('users/staff').update({ role: 'admin' }));
  await assertFails(admin.doc('users/staff').update({ isAdmin: true }));
  await assertFails(admin.doc('users/staff').update({ eateryId: 'E2' }));
  await assertSucceeds(staff.doc('users/staff').update({ firstName: 'Edited' }));
});

test('payables: staff writes are denied and amounts are validated', async () => {
  await seedBase();
  const admin = db('admin');
  const staff = db('staff');
  const ref = 'eateries/E1/payables/p1';

  await assertFails(
    staff.doc(ref).set({ eateryId: 'E1', name: 'Rent', amount: 1000 }),
  );
  await assertSucceeds(
    admin.doc(ref).set({ eateryId: 'E1', name: 'Rent', amount: 1000, status: 'unpaid' }),
  );
  await assertFails(admin.doc(ref).update({ amount: -100 }));
  await assertFails(admin.doc(ref).update({ amount: '1000' }));
  await assertSucceeds(admin.doc(ref).update({ status: 'paid' }));
});

test('tenant isolation: cross-eatery admin writes are denied', async () => {
  await seedBase();
  await seed(async (firestore) => {
    await firestore.doc('eateries/E1/payables/p1').set({
      eateryId: 'E1',
      name: 'Rent',
      amount: 100,
    });
    await firestore.doc('eateries/E1/settings/pos').set({ eateryId: 'E1' });
  });

  const otherAdmin = db('other');
  await assertFails(
    otherAdmin.doc('eateries/E1/payables/p1').update({ amount: 1 }),
  );
  await assertFails(
    otherAdmin.doc('eateries/E1/settings/pos').update({ receiptFooter: 'x' }),
  );
});

test('expenses: forged inventory purchase posts are denied', async () => {
  await seedBase();
  await seed(async (firestore) => {
    await firestore.doc('eateries/E1/purchase_receipts/R1').set({
      eateryId: 'E1',
      receiptNumber: 'PL-1',
      status: 'received',
      items: [
        {
          itemId: 'i1',
          qtyBase: 1,
          qtyPurchased: 1,
          conversionFactor: 1,
          unitCostPerBase: 10,
        },
      ],
      receivedAt: new Date(),
    });
  });

  const staff = db('staff');
  const admin = db('admin');

  await assertFails(
    staff.doc('eateries/E1/expenses/forged').set({
      eateryId: 'E1',
      name: 'Fake purchase',
      amount: 999999,
      source: 'inventory_purchase',
      linkedPurchaseId: 'R1',
    }),
  );
  await assertFails(
    staff.doc('eateries/E1/purchase_receipts/R2').set({
      eateryId: 'E1',
      receiptNumber: 'PL-2',
      status: 'received',
      items: [{ itemId: 'i1', qtyBase: 1, qtyPurchased: 1, unitCostPerBase: 1 }],
      receivedAt: new Date(),
    }),
  );
  await assertSucceeds(
    admin.doc('eateries/E1/expenses/valid').set({
      eateryId: 'E1',
      name: 'Inventory purchase - PL-1',
      amount: 10,
      source: 'inventory_purchase',
      linkedPurchaseId: 'R1',
    }),
  );
});

test('orders: forged totals are denied and legitimate POS flows still work', async () => {
  await seedBase();
  const staff = db('staff');
  const order = {
    eateryId: 'E1',
    createdBy: 'staff',
    createdByName: 'Seed Staff',
    status: 'pending',
    items: [{ menuItemId: 'm1', quantity: 2, price: 10 }],
    totalAmount: 20,
  };

  await assertSucceeds(staff.doc('eateries/E1/orders/o1').set(order));
  await assertFails(
    staff.doc('eateries/E1/orders/negative').set({ ...order, totalAmount: -50 }),
  );
  await assertFails(
    staff.doc('eateries/E1/orders/huge').set({ ...order, totalAmount: 1e12 }),
  );
  await assertFails(
    staff.doc('eateries/E1/orders/spoofed').set({ ...order, createdBy: 'admin' }),
  );

  const o1 = staff.doc('eateries/E1/orders/o1');
  await assertSucceeds(
    o1.update({
      status: 'completed',
      completedAt: new Date(),
      updatedAt: new Date(),
    }),
  );
  await assertFails(o1.update({ status: 'pending', totalAmount: -1 }));
  await assertFails(o1.update({ eateryId: 'E2' }));

  await assertSucceeds(
    staff.doc('eateries/E1/orders/o2').set(order),
  );
  await assertSucceeds(
    staff.doc('eateries/E1/orders/o2').update({
      items: [{ menuItemId: 'm1', quantity: 3, price: 10 }],
      totalAmount: 30,
      updatedAt: new Date(),
    }),
  );
});

test('POS: staff stock deductions work on admin-created records', async () => {
  await seedBase();
  await seed(async (db) => {
    await db.doc('eateries/E1/inventory/i1').set({
      eateryId: 'E1',
      createdBy: 'admin',
      name: 'Rice',
      currentStock: 10,
      minStock: 2,
      unitCost: 10,
      sellingPrice: 20,
    });
    await db.doc('eateries/E1/menu/m1').set({
      eateryId: 'E1',
      createdBy: 'admin',
      name: 'Rice Bowl',
      price: 100,
      cost: 20,
      availableServings: 5,
      isAvailable: true,
      inventoryItemId: 'i1',
    });
  });

  const staff = db('staff');
  await assertSucceeds(
    staff.doc('eateries/E1/inventory/i1').update({
      currentStock: 9,
      updatedAt: new Date(),
    }),
  );
  await assertSucceeds(
    staff.doc('eateries/E1/menu/m1').update({
      availableServings: 9,
      isAvailable: true,
      updatedAt: new Date(),
    }),
  );
  await assertSucceeds(
    staff.doc('eateries/E1/stock_movements/sale-o1-i1').set({
      eateryId: 'E1',
      itemId: 'i1',
      type: 'saleConsumption',
    }),
  );
});

test('settings: staff writes are denied and sensitive reads stay restricted', async () => {
  await seedBase();
  await seed(async (firestore) => {
    await firestore.doc('eateries/E1/settings/pos').set({ eateryId: 'E1' });
    await firestore.doc('eateries/E1/settings/sms').set({ eateryId: 'E1' });
  });

  const admin = db('admin');
  const staff = db('staff');
  const pos = staff.doc('eateries/E1/settings/pos');

  await assertFails(pos.update({ receiptFooter: 'spoof' }));
  await assertFails(
    staff.doc('eateries/E1/settings/new').set({ eateryId: 'E1' }),
  );
  await assertFails(staff.doc('eateries/E1/settings/sms').get());
  await assertSucceeds(pos.get());
  await assertSucceeds(
    admin.doc('eateries/E1/settings/pos').update({ receiptFooter: 'ok' }),
  );
});

test('notifications: spoofed creates are denied, read-state updates work', async () => {
  await seedBase();
  const staff = db('staff');
  const pending = db('pending');
  const admin = db('admin');

  await assertFails(
    pending.doc('notifications/E1_unapproved').set(notification('E1')),
  );
  await assertFails(
    staff.doc('notifications/E2_spoof').set(notification('E2')),
  );
  await assertFails(
    staff.doc('notifications/random_id').set(notification('E1')),
  );
  await assertSucceeds(
    staff.doc('notifications/E1_notice_1').set(notification('E1')),
  );

  const valid = staff.doc('notifications/E1_notice_1');
  await assertSucceeds(valid.update({ readBy: { staff: new Date() } }));
  await assertFails(valid.update({ title: 'Spoofed by staff' }));
  await assertSucceeds(admin.doc('notifications/E1_notice_1').delete());
});

test('eateries: join lookup works while non-metadata docs stay private', async () => {
  await seedBase();
  await seed(async (firestore) => {
    await firestore.doc('eateries/E2').update({ internalNote: 'private' });
  });

  const joiner = env.authenticatedContext('new-user').firestore();
  await assertSucceeds(joiner.doc('eateries/E1').get());
  await assertFails(joiner.doc('eateries/E2').get());
  await assertFails(env.unauthenticatedContext().firestore().doc('eateries/E1').get());
  await assertSucceeds(db('other').doc('eateries/E2').get());
});

test('users: legitimate approval works and stays eatery-scoped', async () => {
  await seedBase();
  const admin = db('admin');

  await assertFails(
    db('pending').doc('users/pending').update({ approved: true }),
  );
  await assertSucceeds(
    admin.doc('users/pending').update({ approved: true, updatedAt: new Date() }),
  );
  await assertFails(
    admin.doc('users/other_staff').update({ approved: true }),
  );
  await assertFails(
    admin.doc('users/pending').update({ approved: false }),
  );
});
