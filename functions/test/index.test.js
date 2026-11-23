const test = require('node:test');
const assert = require('node:assert/strict');
const Module = require('node:module');
const path = require('node:path');

const indexPath = path.resolve(__dirname, '..', 'index.js');
const expectedExports = [
  'requestEmailVerificationCode',
  'verifyEmailVerificationCode',
  'createAccountAfterEmailOtp',
  'onOrderCreatedAdjustMenuServings',
];

function installStubs() {
  const originalLoad = Module._load;

  const adminStub = {
    apps: [],
    initializeApp() {},
    auth() {
      return {};
    },
  };

  const httpsStub = {
    HttpsError: class HttpsError extends Error {
      constructor(code, message) {
        super(message);
        this.code = code;
      }
    },
    onCall(optionsOrHandler, maybeHandler) {
      return typeof optionsOrHandler === 'function' ? optionsOrHandler : maybeHandler;
    },
  };

  const firestoreStub = {
    onDocumentCreated: (handler) => handler,
  };

  const paramsStub = {
    defineSecret: (name) => ({ name, value: () => 'test-value' }),
  };

  const resendStub = {
    Resend: class Resend {
      constructor() {
        this.emails = { send: async () => ({}) };
      }
    },
  };

  Module._load = function patchedLoad(request, parent, isMain) {
    if (request === 'firebase-admin') return adminStub;
    if (request === 'firebase-functions/v2/https') return httpsStub;
    if (request === 'firebase-functions/v2/firestore') return firestoreStub;
    if (request === 'firebase-functions/params') return paramsStub;
    if (request === 'resend') return resendStub;
    return originalLoad.apply(this, arguments);
  };

  return () => {
    Module._load = originalLoad;
  };
}

test('index.js loads without undefined symbols and exposes expected exports', () => {
  delete require.cache[indexPath];
  const restore = installStubs();

  try {
    let loaded;
    assert.doesNotThrow(() => {
      loaded = require(indexPath);
    });

    assert.ok(loaded, 'index.js should export an object');
    assert.deepEqual(Object.keys(loaded).sort(), expectedExports.slice().sort());
    for (const name of expectedExports.slice(0, 3)) {
      assert.equal(typeof loaded[name], 'function', `${name} should be a function`);
    }
    assert.ok(loaded.onOrderCreatedAdjustMenuServings, 'Firestore trigger should be registered');
  } finally {
    delete require.cache[indexPath];
    restore();
  }
});
