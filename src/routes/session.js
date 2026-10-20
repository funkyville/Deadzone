const express = require('express');
const { authenticateToken } = require('../middleware/auth');
const {
  setPlayerSession,
  getPlayerSession,
  updatePlayerCoordinates,
  deletePlayerSession,
  getAllActiveSessions,
} = require('../config/redis');
const { sessionCreateSchema, coordinatesUpdateSchema, validate } = require('../utils/validation');

const router = express.Router();

// POST /api/session - create / refresh session (cache active player state)
// This is the main Redis integration endpoint
router.post('/', authenticateToken, validate(sessionCreateSchema), async (req, res) => {
  const userId = req.user.id;
  const { x, y, zone, status, health } = req.body;

  try {
    const session = await setPlayerSession(userId, {
      x, y, zone, status, health,
      username: req.user.username,
      continent_id: req.user.continent_id,
    });

    res.status(201).json({
      success: true,
      message: 'Player session cached in Redis',
      session,
      ttl: '2 hours (auto-refresh on update)',
    });
  } catch (err) {
    console.error('Create session error:', err);
    res.status(500).json({ success: false, message: 'Redis error', error: err.message });
  }
});

// GET /api/session/:userId - retrieve cached session
router.get('/:userId', authenticateToken, async (req, res) => {
  const { userId } = req.params;
  try {
    const session = await getPlayerSession(userId);
    if (!session) {
      return res.status(404).json({ success: false, message: 'No active session found in Redis (player offline or expired)' });
    }
    res.json({ success: true, session });
  } catch (err) {
    console.error('Get session error:', err);
    res.status(500).json({ success: false, message: 'Redis error', error: err.message });
  }
});

// GET /api/session - list all active sessions (for map / admin)
router.get('/', authenticateToken, async (req, res) => {
  try {
    const cursor = req.query.cursor || '0';
    const count = parseInt(req.query.count || '50', 10);
    const result = await getAllActiveSessions(cursor, count);
    res.json({
      success: true,
      count: result.sessions.length,
      nextCursor: result.cursor,
      sessions: result.sessions,
      note: 'All sessions stored in Redis with 2h TTL, scanned via SCAN',
    });
  } catch (err) {
    console.error('List sessions error:', err);
    res.status(500).json({ success: false, message: 'Redis error', error: err.message });
  }
});

// PUT /api/session/:userId/coordinates - fast coordinate update (core survival mechanic)
// Client will call this every few seconds while moving
router.put('/:userId/coordinates', authenticateToken, validate(coordinatesUpdateSchema), async (req, res) => {
  const { userId } = req.params;
  const { x, y, zone, status } = req.body;

  // Only allow updating your own coordinates (anti-cheat basic)
  if (String(req.user.id) !== String(userId) && req.user.role !== 'admin') {
    return res.status(403).json({ success: false, message: 'Cannot update another player coordinates' });
  }

  try {
    const updated = await updatePlayerCoordinates(userId, x, y, { zone, status });
    res.json({
      success: true,
      message: 'Coordinates updated in Redis',
      session: updated,
    });
  } catch (err) {
    console.error('Update coordinates error:', err);
    res.status(500).json({ success: false, message: 'Redis error', error: err.message });
  }
});

// PATCH /api/session/:userId/status - update status only (in_combat, idle, etc.)
router.patch('/:userId/status', authenticateToken, async (req, res) => {
  const { userId } = req.params;
  const { status, health } = req.body;

  if (String(req.user.id) !== String(userId)) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }

  try {
    const session = await getPlayerSession(userId);
    if (!session) {
      return res.status(404).json({ success: false, message: 'No active session. Create one first via POST /api/session' });
    }
    const updated = await setPlayerSession(userId, {
      ...session,
      status: status || session.status,
      health: health ?? session.health,
    });
    res.json({ success: true, session: updated });
  } catch (err) {
    console.error('Update status error:', err);
    res.status(500).json({ success: false, message: 'Redis error', error: err.message });
  }
});

// DELETE /api/session/:userId - logout / clear session
router.delete('/:userId', authenticateToken, async (req, res) => {
  const { userId } = req.params;
  if (String(req.user.id) !== String(userId)) {
    return res.status(403).json({ success: false, message: 'Forbidden' });
  }
  try {
    const deleted = await deletePlayerSession(userId);
    res.json({ success: true, message: deleted ? 'Session cleared' : 'No session to clear', deletedCount: deleted });
  } catch (err) {
    console.error('Delete session error:', err);
    res.status(500).json({ success: false, message: 'Redis error', error: err.message });
  }
});

module.exports = router;
