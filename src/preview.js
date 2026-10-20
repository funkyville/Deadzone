/**
 * Preview Server - In-Memory Deployment (No Postgres/Redis required)
 * Mirrors the real API shape but uses Maps so you can test instantly
 * This is what powers the Live Preview URL
 */
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const Joi = require('joi');

const app = express();
const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'dev_super_secret_preview_key_32chars_long!';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d';

// Middleware
app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN || '*', credentials: true }));
app.use(express.json({ limit: '10kb' }));
app.use(morgan('dev'));

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 50,
  message: { success: false, message: 'Too many requests' },
});

// In-Memory Stores (simulating Postgres + Redis)
const users = new Map(); // id -> {id, username, email, password_hash, continent_id, created_at}
const resources = new Map(); // user_id -> {food, metal, ammo, hard_currency}
const sessions = new Map(); // userId -> {x, y, zone, status, health, lastActive}
let nextId = 1;

const continents = [
  { id: 1, name: 'North America', code: 'NA' },
  { id: 2, name: 'Europe', code: 'EU' },
  { id: 3, name: 'Asia', code: 'AS' },
  { id: 4, name: 'Africa', code: 'AF' },
  { id: 5, name: 'South America', code: 'SA' },
  { id: 6, name: 'Oceania', code: 'OC' },
];

// Validation
const registerSchema = Joi.object({
  username: Joi.string().alphanum().min(3).max(30).required(),
  email: Joi.string().email().required(),
  password: Joi.string().min(6).max(128).required(),
  continent_id: Joi.number().integer().min(1).max(6).optional(),
});
const loginSchema = Joi.object({ email: Joi.string().email().required(), password: Joi.string().required() });

function validate(schema) {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.body, { abortEarly: false, stripUnknown: true });
    if (error) return res.status(400).json({ success: false, errors: error.details.map(d => d.message) });
    req.body = value;
    next();
  };
}

function signToken(user) {
  return jwt.sign({ id: user.id, username: user.username, email: user.email, continent_id: user.continent_id }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

function authenticateToken(req, res, next) {
  const token = req.headers['authorization']?.split(' ')[1];
  if (!token) return res.status(401).json({ success: false, message: 'Bearer token required' });
  jwt.verify(token, JWT_SECRET, (err, payload) => {
    if (err) return res.status(403).json({ success: false, message: 'Invalid token', error: err.message });
    req.user = payload;
    next();
  });
}

// Routes
app.get('/', (req, res) => {
  res.json({
    success: true,
    message: '🧟 Survival Game API - LIVE PREVIEW (In-Memory)',
    mode: 'preview - no Postgres/Redis needed',
    version: '1.0.0',
    endpoints: {
      health: 'GET /api/health',
      register: 'POST /api/auth/register',
      login: 'POST /api/auth/login',
      verify: 'GET /api/auth/verify',
      me: 'GET /api/auth/me',
      resources: 'GET /api/resources/:userId',
      increment: 'PATCH /api/resources/:userId/increment',
      sessionCreate: 'POST /api/session {x,y,zone}',
      getSession: 'GET /api/session/:userId',
      updateCoords: 'PUT /api/session/:userId/coordinates {x,y}',
      listSessions: 'GET /api/session'
    },
    github: 'https://github.com/funkyville/Deadzone',
    try: 'See /api/demo for Postman examples'
  });
});

app.get('/api/demo', (req, res) => {
  res.json({
    steps: [
      { "1_register": { method: 'POST', url: '/api/auth/register', body: { username: 'wastelander42', email: 'test@test.com', password: 'password123', continent_id: 1 } } },
      { "2_login": { method: 'POST', url: '/api/auth/login', body: { email: 'test@test.com', password: 'password123' } } },
      { "3_verify": { method: 'GET', url: '/api/auth/verify', headers: { Authorization: 'Bearer <token>' } } },
      { "4_resources": { method: 'GET', url: '/api/resources/1', headers: { Authorization: 'Bearer <token>' } } },
      { "5_gather": { method: 'PATCH', url: '/api/resources/1/increment', headers: { Authorization: 'Bearer <token>' }, body: { resource: 'metal', amount: 25 } } },
      { "6_create_session": { method: 'POST', url: '/api/session', headers: { Authorization: 'Bearer <token>' }, body: { x: 500, y: 600, zone: 'forest' } } },
      { "7_move": { method: 'PUT', url: '/api/session/1/coordinates', headers: { Authorization: 'Bearer <token>' }, body: { x: 505, y: 610 } } }
    ]
  });
});

app.get('/api/health', (req, res) => {
  res.json({
    success: true,
    status: 'ok',
    mode: 'preview (in-memory)',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    services: {
      postgresql: 'preview-mode (in-memory Map)',
      redis: 'preview-mode (in-memory Map)',
      users: users.size,
      active_sessions: sessions.size
    }
  });
});

// AUTH
app.post('/api/auth/register', authLimiter, validate(registerSchema), async (req, res) => {
  const { username, email, password, continent_id } = req.body;
  for (const u of users.values()) {
    if (u.email === email || u.username === username) return res.status(409).json({ success: false, message: 'Username or email taken' });
  }
  const password_hash = await bcrypt.hash(password, 10);
  const user = { id: nextId++, username, email, password_hash, continent_id: continent_id || null, created_at: new Date().toISOString() };
  users.set(user.id, user);
  resources.set(user.id, { user_id: user.id, food: 100, metal: 50, ammo: 30, hard_currency: 0, updated_at: new Date().toISOString() });
  const { password_hash: _, ...safe } = user;
  const token = signToken(user);
  res.status(201).json({ success: true, message: 'User registered (preview)', user: safe, resources: resources.get(user.id), token });
});

app.post('/api/auth/login', authLimiter, validate(loginSchema), async (req, res) => {
  const { email, password } = req.body;
  const user = [...users.values()].find(u => u.email === email);
  if (!user) return res.status(401).json({ success: false, message: 'Invalid email or password' });
  const ok = await bcrypt.compare(password, user.password_hash);
  if (!ok) return res.status(401).json({ success: false, message: 'Invalid email or password' });
  const token = signToken(user);
  const { password_hash: _, ...safe } = user;
  res.json({ success: true, message: 'Login successful (preview)', user: safe, token });
});

app.get('/api/auth/verify', authenticateToken, (req, res) => {
  const user = users.get(req.user.id);
  if (!user) return res.status(404).json({ success: false, message: 'User not found' });
  const { password_hash: _, ...safe } = user;
  const cont = continents.find(c => c.id === user.continent_id);
  res.json({ success: true, message: 'Token valid (preview)', user: { ...safe, continent_name: cont?.name, continent_code: cont?.code }, tokenPayload: req.user });
});

app.get('/api/auth/me', authenticateToken, (req, res) => {
  const user = users.get(req.user.id);
  if (!user) return res.status(404).json({ success: false, message: 'User not found' });
  const { password_hash: _, ...safe } = user;
  res.json({ success: true, user: safe, resources: resources.get(user.id) });
});

// RESOURCES
app.get('/api/resources/:userId', authenticateToken, (req, res) => {
  const id = parseInt(req.params.userId);
  if (String(req.user.id) !== String(id)) return res.status(403).json({ success: false, message: 'Forbidden' });
  const r = resources.get(id);
  if (!r) return res.status(404).json({ success: false, message: 'Resources not found' });
  res.json({ success: true, resources: r });
});

app.put('/api/resources/:userId', authenticateToken, (req, res) => {
  const id = parseInt(req.params.userId);
  if (String(req.user.id) !== String(id)) return res.status(403).json({ success: false, message: 'Forbidden' });
  const r = resources.get(id);
  if (!r) return res.status(404).json({ success: false, message: 'Not found' });
  for (const k of ['food', 'metal', 'ammo', 'hard_currency']) if (req.body[k] !== undefined) {
    if (req.body[k] < 0) return res.status(400).json({ success: false, message: `${k} cannot be negative` });
    r[k] = req.body[k];
  }
  r.updated_at = new Date().toISOString();
  res.json({ success: true, resources: r });
});

app.patch('/api/resources/:userId/increment', authenticateToken, (req, res) => {
  const id = parseInt(req.params.userId);
  if (String(req.user.id) !== String(id)) return res.status(403).json({ success: false, message: 'Forbidden' });
  const { resource, amount } = req.body;
  if (!['food', 'metal', 'ammo', 'hard_currency'].includes(resource)) return res.status(400).json({ success: false, message: 'Invalid resource' });
  const r = resources.get(id);
  if (!r) return res.status(404).json({ success: false, message: 'Not found' });
  const nv = r[resource] + amount;
  if (nv < 0) return res.status(400).json({ success: false, message: `Insufficient ${resource}` });
  r[resource] = nv;
  r.updated_at = new Date().toISOString();
  res.json({ success: true, message: `${amount >= 0 ? 'Added' : 'Deducted'} ${Math.abs(amount)} ${resource}`, resources: r });
});

// SESSION (Redis simulation)
app.post('/api/session', authenticateToken, (req, res) => {
  const { x, y, zone, status, health } = req.body;
  if (x === undefined || y === undefined) return res.status(400).json({ success: false, message: 'x and y required' });
  const sess = { userId: String(req.user.id), username: req.user.username, x, y, zone: zone || 'wasteland', status: status || 'online', health: health ?? 100, lastActive: new Date().toISOString(), continent_id: req.user.continent_id };
  sessions.set(String(req.user.id), sess);
  res.status(201).json({ success: true, message: 'Session cached (in-memory, 2h TTL simulated)', session: sess });
});

app.get('/api/session', authenticateToken, (req, res) => {
  res.json({ success: true, count: sessions.size, sessions: [...sessions.values()], note: 'In-memory preview - production uses Redis SCAN' });
});

app.get('/api/session/:userId', authenticateToken, (req, res) => {
  const s = sessions.get(String(req.params.userId));
  if (!s) return res.status(404).json({ success: false, message: 'No active session' });
  res.json({ success: true, session: s });
});

app.put('/api/session/:userId/coordinates', authenticateToken, (req, res) => {
  const uid = String(req.params.userId);
  if (String(req.user.id) !== uid) return res.status(403).json({ success: false, message: 'Cannot update others' });
  const { x, y, zone, status } = req.body;
  let s = sessions.get(uid);
  if (!s) s = { userId: uid, x, y, zone: zone || 'wasteland', status: status || 'online', lastActive: new Date().toISOString() };
  else { s.x = x; s.y = y; if (zone) s.zone = zone; if (status) s.status = status; s.lastActive = new Date().toISOString(); }
  sessions.set(uid, s);
  res.json({ success: true, message: 'Coordinates updated (in-memory)', session: s });
});

app.delete('/api/session/:userId', authenticateToken, (req, res) => {
  const uid = String(req.params.userId);
  if (String(req.user.id) !== uid) return res.status(403).json({ success: false, message: 'Forbidden' });
  const del = sessions.delete(uid);
  res.json({ success: true, message: del ? 'Session cleared' : 'No session', deletedCount: del ? 1 : 0 });
});

app.use((req, res) => res.status(404).json({ success: false, message: `Route ${req.method} ${req.originalUrl} not found` }));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 SURVIVAL PREVIEW running on http://0.0.0.0:${PORT}`);
  console.log(`   Health: http://localhost:${PORT}/api/health`);
  console.log(`   Demo: http://localhost:${PORT}/api/demo`);
  console.log(`   Mode: In-Memory (no external DB) - push to Deadzone for production\n`);
});
