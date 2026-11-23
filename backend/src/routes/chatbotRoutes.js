const express = require('express');
const { verifyToken } = require('../middleware/auth');
const chatbotController = require('../controllers/chatbotController');

const router = express.Router();

router.use(verifyToken);

router.get('/status', chatbotController.getStatus);
router.post('/chat', chatbotController.chat);
// SSE streaming variant — returns tokens progressively for a faster UI.
router.post('/chat/stream', chatbotController.chatStream);
router.get('/insights', chatbotController.getInsights);

module.exports = router;
