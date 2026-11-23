const express = require('express');
const router = express.Router();
const { verifyToken, checkRole } = require('../middleware/auth');
const { requireCronSecret } = require('../middleware/cronAuth');
const { sendDailySummaryCron, sendSms } = require('../controllers/smsController');

router.post('/send', verifyToken, checkRole(['admin', 'manager']), sendSms);
router.post('/daily-summary/cron', requireCronSecret, sendDailySummaryCron);

module.exports = router;
