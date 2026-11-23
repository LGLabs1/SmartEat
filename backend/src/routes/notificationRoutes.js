const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');
const {
  deleteNotification,
  listNotifications,
  markAllRead,
  markRead,
  recordNotification,
  syncNotifications,
} = require('../controllers/notificationController');

router.get('/', verifyToken, listNotifications);
router.post('/record', verifyToken, recordNotification);
router.post('/sync', verifyToken, syncNotifications);
router.post('/read-all', verifyToken, markAllRead);
router.post('/:id/read', verifyToken, markRead);
router.delete('/:id', verifyToken, deleteNotification);

module.exports = router;
