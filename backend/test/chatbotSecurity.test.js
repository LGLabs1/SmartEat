const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');

process.env.GEMINI_API_KEY = 'test-key';
process.env.SAGE_DISABLED = 'false';
process.env.GEMINI_MODEL = 'test-model';

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
    setHeader() {
      return this;
    },
    flushHeaders() {},
    write() {},
    end() {},
  };
}

const postCalls = [];
const axiosStub = {
  post: async (...args) => {
    postCalls.push(args);
    const index = postCalls.length;
    return {
      data: {
        candidates: [{ content: { parts: [{ text: `reply-${index}` }] } }],
      },
    };
  },
  get: async () => ({ data: { models: [] } }),
};

function loadChatbotController() {
  delete require.cache[require.resolve('../src/controllers/chatbotController')];

  const originalLoad = Module._load;
  Module._load = function patchedLoad(request, parent, isMain) {
    if (request === 'axios') return axiosStub;
    if (request === '../config/firebase') {
      return { admin: {}, db: { collection: () => ({}) } };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('../src/controllers/chatbotController');
  } finally {
    Module._load = originalLoad;
  }
}

const chatbot = loadChatbotController();

test('chatbot requires a trusted tenant and ignores client-supplied tenant fields', async () => {
  const req = {
    user: { uid: 'uid-1', role: 'admin' },
    headers: { 'x-eatery-id': 'attacker-tenant' },
    body: {
      eateryId: 'attacker-tenant',
      message: 'No trusted tenant question',
      context: 'SMARTEAT BUSINESS SNAPSHOT\nIntent: General\n\nclient context',
    },
  };
  const res = makeRes();

  await chatbot.chat(req, res);

  assert.equal(res.statusCode, 403);
  assert.equal(res.payload.error, 'eatery_required');
  assert.equal(postCalls.length, 0);
});

test('chatbot cache is scoped to the trusted tenant', async () => {
  const context = 'SMARTEAT BUSINESS SNAPSHOT\nIntent: General\n\nidentical context for both tenants';
  const message = 'identical question for both tenants';

  async function ask(eateryId) {
    const req = {
      user: { uid: `uid-${eateryId}`, eateryId, role: 'admin' },
      headers: { 'x-eatery-id': 'attacker-tenant' },
      body: { eateryId: 'attacker-tenant', message, context },
    };
    const res = makeRes();
    await chatbot.chat(req, res);
    return res.payload;
  }

  const first = await ask('eatery-a');
  const second = await ask('eatery-b');

  assert.equal(first.statusCode ?? 200, 200);
  assert.equal(second.statusCode ?? 200, 200);
  assert.equal(first.cached, false);
  assert.equal(second.cached, false);
  assert.equal(first.response, 'reply-1');
  assert.equal(second.response, 'reply-2');
  assert.equal(postCalls.length, 2);
});
