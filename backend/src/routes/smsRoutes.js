const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');
const { sendSms } = require('../controllers/smsController');

router.post('/send', verifyToken, sendSms);

module.exports = router;
