const crypto = require('crypto');

function requireCronSecret(req, res, next) {
  const expected = String(process.env.CRON_SECRET || '').trim();
  const actual = String(req.header('x-cron-secret') || '').trim();
  if (!expected || !actual) {
    return res.status(401).json({ error: 'Unauthorized', code: 'cron_unauthorized' });
  }
  const actualBuffer = Buffer.from(actual);
  const expectedBuffer = Buffer.from(expected);
  if (
    actualBuffer.length !== expectedBuffer.length ||
    !crypto.timingSafeEqual(actualBuffer, expectedBuffer)
  ) {
    return res.status(401).json({ error: 'Unauthorized', code: 'cron_unauthorized' });
  }
  return next();
}

module.exports = { requireCronSecret };
