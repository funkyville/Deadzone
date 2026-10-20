require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const authRoutes = require('./routes/auth');
const resourceRoutes = require('./routes/resources');
const sessionRoutes = require('./routes/session');

const app = express();

// ---------------------------------------------------
// Middleware
// ---------------------------------------------------
app.use(helmet());
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  credentials: true,
}));
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));

// Rate limiter for auth endpoints (brute force protection)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 min
  max: 20,
  message: { success: false, message: 'Too many requests, please try again later' },
  standardHeaders: true,
  legacyHeaders: false,
});

// ---------------------------------------------------
// Routes
// ---------------------------------------------------
app.get('/', (req, res) => {
  res.json({
    success: true,
    message: '🧟 Survival Game API - Online',
    version: '1.0.0',
    endpoints: {
      health: 'GET /api/health',
      register: 'POST /api/auth/register',
      login: 'POST /api/auth/login',
      verify: 'GET /api/auth/verify (Bearer token)',
      me: 'GET /api/auth/me (Bearer token)',
      resources: 'GET /api/resources/:userId (Bearer)',
      updateResources: 'PUT /api/resources/:userId (Bearer)',
      increment: 'PATCH /api/resources/:userId/increment (Bearer)',
      sessionCreate: 'POST /api/session (Bearer) {x, y, zone}',
      getSession: 'GET /api/session/:userId (Bearer)',
      updateCoords: 'PUT /api/session/:userId/coordinates (Bearer) {x, y}',
      listSessions: 'GET /api/session (Bearer)',
    },
    docs: 'See README.md for full API spec',
  });
});

app.get('/api/health', async (req, res) => {
  // Check DB & Redis health
  let dbStatus = 'unknown';
  let redisStatus = 'unknown';

  try {
    const { pool } = require('./config/db');
    await pool.query('SELECT 1');
    dbStatus = 'connected';
  } catch (e) {
    dbStatus = `error: ${e.message}`;
  }

  try {
    const { getRedis } = require('./config/redis');
    const client = getRedis();
    await client.ping();
    redisStatus = 'connected (PONG)';
  } catch (e) {
    redisStatus = `error: ${e.message}`;
  }

  res.json({
    success: true,
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    services: {
      postgresql: dbStatus,
      redis: redisStatus,
    },
  });
});

app.use('/api/auth', authLimiter, authRoutes);
app.use('/api/resources', resourceRoutes);
app.use('/api/session', sessionRoutes);

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: `Route ${req.method} ${req.originalUrl} not found`,
  });
});

// Global error handler
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, _next) => {
  console.error('Unhandled error:', err);
  res.status(err.status || 500).json({
    success: false,
    message: err.message || 'Internal server error',
    ...(process.env.NODE_ENV === 'development' && { stack: err.stack }),
  });
});

module.exports = app;
