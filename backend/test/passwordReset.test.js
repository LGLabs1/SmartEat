const test = require('node:test');
const assert = require('node:assert/strict');
const {
  normalizeEmail,
  isValidEmail,
  normalizePhMobile,
  isValidChannel,
  sha256Hex,
  randomOtp,
  randomToken,
  hashOtp,
  hashResetToken,
  safeEqualHex,
  validatePassword,
  secondsUntil,
} = require('../src/utils/passwordReset');

test('normalizeEmail trims and lowercases', () => {
  assert.equal(normalizeEmail('  Admin@Example.COM '), 'admin@example.com');
  assert.equal(normalizeEmail(null), '');
});

test('isValidEmail validates common addresses', () => {
  assert.equal(isValidEmail('admin@example.com'), true);
  assert.equal(isValidEmail(' admin@example.com '), true);
  assert.equal(isValidEmail('not-an-email'), false);
  assert.equal(isValidEmail(''), false);
});

test('normalizePhMobile accepts common PH formats', () => {
  assert.equal(normalizePhMobile('09171234567'), '639171234567');
  assert.equal(normalizePhMobile('+63 917 123 4567'), '639171234567');
  assert.equal(normalizePhMobile('9171234567'), '639171234567');
  assert.equal(normalizePhMobile('00639171234567'), '639171234567');
  assert.equal(normalizePhMobile('12345'), null);
  assert.equal(normalizePhMobile(''), null);
});

test('isValidChannel only accepts email or sms', () => {
  assert.equal(isValidChannel('email'), true);
  assert.equal(isValidChannel('sms'), true);
  assert.equal(isValidChannel('EMAIL'), false);
  assert.equal(isValidChannel('phone'), false);
});

test('sha256Hex is deterministic', () => {
  assert.equal(sha256Hex('abc'), sha256Hex('abc'));
  assert.notEqual(sha256Hex('abc'), sha256Hex('abd'));
  assert.equal(sha256Hex('abc').length, 64);
});

test('randomOtp is always six digits', () => {
  for (let index = 0; index < 100; index += 1) {
    assert.match(randomOtp(), /^\d{6}$/);
  }
});

test('randomToken is 32 random bytes as hex', () => {
  const first = randomToken();
  const second = randomToken();
  assert.match(first, /^[a-f0-9]{64}$/);
  assert.notEqual(first, second);
});

test('hashOtp is deterministic and secret-dependent', () => {
  const first = hashOtp('123456', 'salt', 'secret-a');
  const second = hashOtp('123456', 'salt', 'secret-a');
  const third = hashOtp('123456', 'salt', 'secret-b');
  assert.equal(first, second);
  assert.notEqual(first, third);
});

test('hashResetToken is deterministic and secret-dependent', () => {
  const first = hashResetToken('token', 'secret-a');
  const second = hashResetToken('token', 'secret-a');
  const third = hashResetToken('token', 'secret-b');
  assert.equal(first, second);
  assert.notEqual(first, third);
});

test('safeEqualHex compares valid hashes safely', () => {
  const hash = sha256Hex('value');
  assert.equal(safeEqualHex(hash, hash), true);
  assert.equal(safeEqualHex(hash, sha256Hex('other')), false);
  assert.equal(safeEqualHex('', ''), false);
  assert.equal(safeEqualHex('abc', 'abcd'), false);
});

test('validatePassword enforces length bounds', () => {
  assert.equal(validatePassword('12345'), 'Password must be at least 6 characters');
  assert.equal(validatePassword('123456'), null);
  assert.equal(validatePassword('a'.repeat(128)), null);
  assert.equal(validatePassword('a'.repeat(129)), 'Password must be at most 128 characters');
});

test('secondsUntil rounds up and never goes negative', () => {
  assert.equal(secondsUntil(1000), 1);
  assert.equal(secondsUntil(1001), 2);
  assert.equal(secondsUntil(-500), 0);
  assert.equal(secondsUntil(0), 0);
});
