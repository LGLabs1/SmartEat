const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');

process.env.IPROG_SMS_API_TOKEN = 'test-token';
process.env.SMS_MAX_PER_UID = '10';
process.env.SMS_MAX_PER_IP = '20';
process.env.SMS_MAX_PER_PHONE = '2';
process.env.SMS_RATE_WINDOW_MS = '60000';

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

function makeReq(overrides = {}) {
  return {
    user: { uid: 'uid-1', eateryId: 'eatery-a', role: 'admin' },
    body: {
      phone_number: '09171234567',
      message: 'Hello from SmartEat',
      purpose: 'test',
    },
    ip: '203.0.113.10',
    headers: {},
    socket: { remoteAddress: '203.0.113.10' },
    ...overrides,
  };
}

const postCalls = [];
const axiosStub = { post: async () => ({ status: 200, data: {} }) };

function loadSmsModules() {
  delete require.cache[require.resolve('../src/services/smsService')];
  delete require.cache[require.resolve('../src/controllers/smsController')];

  const originalLoad = Module._load;
  Module._load = function patchedLoad(request, parent, isMain) {
    if (request === 'axios') return axiosStub;
    return originalLoad.apply(this, arguments);
  };
  try {
    const service = require('../src/services/smsService');
    const controller = require('../src/controllers/smsController');
    return { service, controller };
  } finally {
    Module._load = originalLoad;
  }
}

const { service, controller } = loadSmsModules();

function resetProvider(successData = { message_id: 'msg-1' }) {
  postCalls.length = 0;
  axiosStub.post = async (...args) => {
    postCalls.push(args);
    return { status: 200, data: successData };
  };
}

async function captureAudit(fn) {
  const original = console.info;
  const lines = [];
  console.info = (...args) => {
    lines.push(args.join(' '));
  };
  try {
    const result = await fn();
    return { result, lines };
  } finally {
    console.info = original;
  }
}

test.beforeEach(() => {
  service.resetSmsRateLimits();
  resetProvider();
});

test('SMS send rejects non-privileged roles before touching the provider', async () => {
  const req = makeReq({ user: { uid: 'uid-2', eateryId: 'eatery-a', role: 'staff' } });
  const res = makeRes();
  await controller.sendSms(req, res);

  assert.equal(res.statusCode, 403);
  assert.equal(res.payload.code, 'insufficient_permissions');
  assert.equal(postCalls.length, 0);
});

test('SMS send validates purpose, phone, and message length', async () => {
  const cases = [
    [{ body: { purpose: 'spam', phone_number: '09171234567', message: 'Hi' } }, 'invalid_purpose'],
    [{ body: { purpose: 'test', phone_number: '12345', message: 'Hi' } }, 'invalid_phone'],
    [{ body: { purpose: 'test', phone_number: '09171234567', message: '' } }, 'invalid_message'],
    [{ body: { purpose: 'test', phone_number: '09171234567', message: 'x'.repeat(460) } }, 'message_too_long'],
  ];

  for (const [override, expectedCode] of cases) {
    const res = makeRes();
    await controller.sendSms(makeReq(override), res);
    assert.equal(res.statusCode, 400, expectedCode);
    assert.equal(res.payload.code, expectedCode);
  }
  assert.equal(postCalls.length, 0);
});

test('SMS send normalizes phone and writes a redacted audit record', async () => {
  const req = makeReq({
    body: {
      purpose: 'LOW STOCK',
      phone_number: '+63 917 123 4567',
      message: 'Low stock alert from SmartEat',
    },
  });
  const res = makeRes();

  const { lines } = await captureAudit(() => controller.sendSms(req, res));

  assert.equal(res.statusCode, 200);
  assert.equal(res.payload.message_id, 'msg-1');
  assert.equal(postCalls.length, 1);
  assert.equal(postCalls[0][1].phone_number, '639171234567');
  assert.equal(postCalls[0][1].message, 'Low stock alert from SmartEat');

  const auditText = lines.join('\n');
  assert.equal(auditText.includes('+63 917 123 4567'), false);
  assert.equal(auditText.includes('639171234567'), false);
  assert.equal(auditText.includes('Low stock alert from SmartEat'), false);
  assert.equal(auditText.includes('"phoneTail":"4567"'), true);
  assert.equal(auditText.includes('"purpose":"low_stock"'), true);
});

test('SMS send enforces per-phone rate limits', async () => {
  const first = makeRes();
  const second = makeRes();
  const third = makeRes();

  await controller.sendSms(makeReq(), first);
  await controller.sendSms(makeReq(), second);
  await controller.sendSms(makeReq(), third);

  assert.equal(first.statusCode, 200);
  assert.equal(second.statusCode, 200);
  assert.equal(third.statusCode, 429);
  assert.equal(third.payload.code, 'rate_limited');
  assert.ok(third.payload.retryAfterSeconds > 0);
  assert.equal(postCalls.length, 2);
});

test('SMS provider errors are generic and never leak provider payloads', async () => {
  axiosStub.post = async (...args) => {
    postCalls.push(args);
    return {
      status: 400,
      data: { error: 'api_token=TOPSECRET_TOKEN rejected' },
    };
  };

  const res = makeRes();
  const { lines } = await captureAudit(() => controller.sendSms(makeReq(), res));

  assert.equal(res.statusCode, 502);
  assert.equal(res.payload.code, 'sms_provider_error');
  const responseText = JSON.stringify(res.payload);
  assert.equal(responseText.includes('TOPSECRET_TOKEN'), false);
  assert.equal(responseText.includes('api_token'), false);
  assert.equal(responseText.includes('"data"'), false);

  const auditText = lines.join('\n');
  assert.equal(auditText.includes('TOPSECRET_TOKEN'), false);
  assert.equal(auditText.includes('api_token'), false);
});

test('password reset SMS still uses the provider with its code intact', async () => {
  const result = await service.sendPasswordResetSms({
    phoneNumber: '639171234567',
    code: '123456',
    expiresMinutes: 10,
  });

  assert.equal(result.status, 200);
  assert.equal(postCalls.length, 1);
  assert.equal(postCalls[0][1].phone_number, '639171234567');
  assert.match(postCalls[0][1].message, /123456/);
});
