const jwt = require('jsonwebtoken');

function authenticateToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  if (!token) {
    return res.status(401).json({ success: false, message: 'Access token required. Use: Authorization: Bearer <token>' });
  }

  jwt.verify(token, process.env.JWT_SECRET, (err, payload) => {
    if (err) {
      if (err.name === 'TokenExpiredError') {
        return res.status(401).json({ success: false, message: 'Token expired', expiredAt: err.expiredAt });
      }
      return res.status(403).json({ success: false, message: 'Invalid token', error: err.message });
    }
    req.user = payload; // { id, username, email, continent_id, iat, exp }
    next();
  });
}

// Optional: check that :userId param matches token or is admin
function authorizeSelfOrAdmin(req, res, next) {
  const paramId = req.params.userId || req.params.id;
  if (!paramId) return next();
  // Allow if token id matches param, otherwise check role
  if (String(req.user.id) === String(paramId) || req.user.role === 'admin') {
    return next();
  }
  return res.status(403).json({ success: false, message: 'Forbidden: you can only access your own data' });
}

module.exports = {
  authenticateToken,
  authorizeSelfOrAdmin,
};
