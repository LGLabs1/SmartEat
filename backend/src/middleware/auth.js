const { admin } = require('../config/firebase');

/**
 * Verify Firebase ID token from Authorization header
 */
async function verifyToken(req, res, next) {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;

    if (!token) {
      return res.status(401).json({ error: 'No token provided' });
    }

    const decoded = await admin.auth().verifyIdToken(token);
    req.user = {
      uid: decoded.uid,
      email: decoded.email,
      eateryId: decoded.eateryId || req.headers['x-eatery-id'] || '',
      role: decoded.role || 'staff',
    };
    next();
  } catch (error) {
    console.error('Auth error:', error.message);
    return res.status(401).json({ error: 'Invalid token' });
  }
}

/**
 * Optional Auth: Parses token if present, but doesn't block if missing/invalid
 */
async function optionalAuth(req, res, next) {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;

    if (token && token !== 'null') {
      const decoded = await admin.auth().verifyIdToken(token);
      req.user = {
        uid: decoded.uid,
        email: decoded.email,
        eateryId: decoded.eateryId || req.headers['x-eatery-id'] || '',
        role: decoded.role || 'staff',
      };
    }
  } catch (error) {
    console.error('Optional Auth error (ignored):', error.message);
  }
  next();
}

/**
 * Check user role
 */
function checkRole(allowedRoles) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Not authenticated' });
    }
    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }
    next();
  };
}

module.exports = { verifyToken, checkRole, optionalAuth };
