const express = require('express');
const { verifyToken, optionalAuth } = require('../middleware/auth');
const chatbotController = require('../controllers/chatbotController');

const router = express.Router();

// Public/optional-auth routes
router.get('/status', chatbotController.getStatus);
router.post('/chat', optionalAuth, chatbotController.chat);
router.get('/insights', optionalAuth, chatbotController.getInsights);

module.exports = router;
