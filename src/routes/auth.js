const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../config/db');
const { authenticateToken } = require('../middleware/auth');
const { registerSchema, loginSchema, validate } = require('../utils/validation');

const router = express.Router();

// Helper to sign JWT
function signToken(user) {
  return jwt.sign(
    {
      id: user.id,
      username: user.username,
      email: user.email,
      continent_id: user.continent_id,
    },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
  );
}

// POST /api/auth/register
router.post('/register', validate(registerSchema), async (req, res) => {
  const { username, email, password, continent_id } = req.body;

  try {
    // Check existing user
    const exists = await db.query(
      'SELECT id FROM users WHERE email = $1 OR username = $2 LIMIT 1',
      [email, username]
    );
    if (exists.rows.length > 0) {
      return res.status(409).json({ success: false, message: 'Username or email already taken' });
    }

    // Validate continent_id exists if provided
    if (continent_id) {
      const continent = await db.query('SELECT id FROM continents WHERE id = $1', [continent_id]);
      if (continent.rows.length === 0) {
        return res.status(400).json({ success: false, message: `continent_id ${continent_id} does not exist. Valid: 1-6` });
      }
    }

    const password_hash = await bcrypt.hash(password, 10);

    const result = await db.query(
      `INSERT INTO users (username, email, password_hash, continent_id)
       VALUES ($1, $2, $3, $4)
       RETURNING id, username, email, continent_id, created_at`,
      [username, email, password_hash, continent_id || null]
    );

    const user = result.rows[0];
    const token = signToken(user);

    // Resources & stats auto-created via DB trigger; fetch them for response
    const resources = await db.query('SELECT food, metal, ammo, hard_currency FROM player_resources WHERE user_id = $1', [user.id]);

    res.status(201).json({
      success: true,
      message: 'User registered successfully',
      user,
      resources: resources.rows[0] || null,
      token,
    });
  } catch (err) {
    console.error('Register error:', err);
    // Handle unique violation more gracefully
    if (err.code === '23505') {
      return res.status(409).json({ success: false, message: 'Username or email already exists', detail: err.detail });
    }
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// POST /api/auth/login
router.post('/login', validate(loginSchema), async (req, res) => {
  const { email, password } = req.body;

  try {
    const result = await db.query(
      'SELECT id, username, email, password_hash, continent_id, created_at FROM users WHERE email = $1',
      [email]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    const user = result.rows[0];
    const isValid = await bcrypt.compare(password, user.password_hash);
    if (!isValid) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    // Update last_login in player_stats if table exists
    try {
      await db.query('UPDATE player_stats SET last_login = NOW() WHERE user_id = $1', [user.id]);
    } catch (_) {}

    const token = signToken(user);
    const { password_hash, ...safeUser } = user;

    res.json({
      success: true,
      message: 'Login successful',
      user: safeUser,
      token,
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// GET /api/auth/verify  - verify token & return user
router.get('/verify', authenticateToken, async (req, res) => {
  try {
    // Optionally re-fetch from DB to ensure user still exists
    const result = await db.query(
      `SELECT u.id, u.username, u.email, u.continent_id, u.created_at, c.name as continent_name, c.code as continent_code
       FROM users u
       LEFT JOIN continents c ON c.id = u.continent_id
       WHERE u.id = $1`,
      [req.user.id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found (deleted?)' });
    }

    res.json({
      success: true,
      message: 'Token is valid',
      user: result.rows[0],
      tokenPayload: req.user,
    });
  } catch (err) {
    console.error('Verify error:', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// GET /api/auth/me - alias for verify with resources
router.get('/me', authenticateToken, async (req, res) => {
  try {
    const result = await db.query(
      `SELECT u.id, u.username, u.email, u.continent_id, u.created_at,
              pr.food, pr.metal, pr.ammo, pr.hard_currency
       FROM users u
       LEFT JOIN player_resources pr ON pr.user_id = u.id
       WHERE u.id = $1`,
      [req.user.id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }
    // Split user vs resources for cleaner response
    const row = result.rows[0];
    const { food, metal, ammo, hard_currency, ...user } = row;
    res.json({
      success: true,
      user,
      resources: { food, metal, ammo, hard_currency },
    });
  } catch (err) {
    console.error('Me error:', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

module.exports = router;
