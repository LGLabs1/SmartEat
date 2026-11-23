const express = require('express');
const router = express.Router();
const { verifyToken, checkRole } = require('../middleware/auth');
const { sendSms } = require('../controllers/smsController');

router.post('/send', verifyToken, checkRole(['admin', 'manager']), sendSms);

module.exports = router;
