const express = require('express');
const {
  requestPasswordReset,
  verifyPasswordResetCode,
  confirmPasswordReset,
} = require('../controllers/passwordResetController');

const router = express.Router();

router.use((req, res, next) => {
  res.set('Cache-Control', 'no-store');
  next();
});

router.post('/password-reset/request', requestPasswordReset);
router.post('/password-reset/verify', verifyPasswordResetCode);
router.post('/password-reset/confirm', confirmPasswordReset);

module.exports = router;
