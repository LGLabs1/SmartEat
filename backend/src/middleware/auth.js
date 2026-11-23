const { admin, db } = require('../config/firebase');

/**
 * Resolve the tenant from verified token claims, falling back to the
 * server-side user document. Client-supplied tenant headers are never trusted.
 */
async function resolveTrustedUser(decoded) {
  if (!decoded || !decoded.uid) return null;

  const claimEateryId = String(
    decoded.eateryId || decoded.eatery_id || ''
  ).trim();
  let eateryId = claimEateryId;
  let role = String(decoded.role || 'staff').trim() || 'staff';

  try {
    const snapshot = await db.collection('users').doc(decoded.uid).get();
    if (snapshot.exists) {
      const data = snapshot.data() || {};
      eateryId = eateryId || String(data.eateryId || '').trim();
      role = String(data.role || role).trim() || 'staff';
    }
  } catch (error) {
    if (!eateryId) {
      console.error('Tenant lookup error:', error.message);
      return null;
    }
  }

  if (!eateryId) return null;

  return {
    uid: decoded.uid,
    email: decoded.email,
    eateryId,
    role,
  };
}

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
    const user = await resolveTrustedUser(decoded);

    if (!user) {
      return res.status(403).json({
        error: 'No trusted eatery tenant for this account',
        code: 'tenant_required',
      });
    }

    req.user = user;
    req.tenantId = user.eateryId;
    next();
  } catch (error) {
    console.error('Auth error:', error.message);
    return res.status(401).json({ error: 'Invalid token' });
  }
}

/**
 * Optional Auth: Parses a valid token if present, but never derives a tenant
 * from client input and never blocks when the token is missing/invalid.
 */
async function optionalAuth(req, res, next) {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : authHeader;

    if (token && token !== 'null') {
      const decoded = await admin.auth().verifyIdToken(token);
      const user = await resolveTrustedUser(decoded);
      if (user) {
        req.user = user;
        req.tenantId = user.eateryId;
      } else {
        delete req.user;
        delete req.tenantId;
      }
    }
  } catch (error) {
    console.error('Optional Auth error (ignored):', error.message);
  }
  next();
}

/**
 * Tenant value set by verifyToken/optionalAuth after server-side resolution.
 */
function getRequestEateryId(req) {
  return String(req.tenantId || req.user?.eateryId || '').trim() || null;
}

function requireTenant(req, res) {
  const eateryId = getRequestEateryId(req);
  if (!eateryId) {
    res.status(403).json({
      error: 'Tenant context required',
      code: 'tenant_required',
    });
    return null;
  }
  return eateryId;
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

module.exports = {
  verifyToken,
  checkRole,
  optionalAuth,
  getRequestEateryId,
  requireTenant,
};
