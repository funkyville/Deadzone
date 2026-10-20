const express = require('express');
const db = require('../config/db');
const { authenticateToken, authorizeSelfOrAdmin } = require('../middleware/auth');
const { resourcesUpdateSchema, resourcesIncrementSchema, validate } = require('../utils/validation');

const router = express.Router();

// All resource routes require authentication
router.use(authenticateToken);

// GET /api/resources/:userId - get player resources
router.get('/:userId', authorizeSelfOrAdmin, async (req, res) => {
  const { userId } = req.params;
  try {
    const result = await db.query(
      `SELECT user_id, food, metal, ammo, hard_currency, created_at, updated_at
       FROM player_resources WHERE user_id = $1`,
      [userId]
    );
    if (result.rows.length === 0) {
      // Check if user exists
      const userExists = await db.query('SELECT id FROM users WHERE id = $1', [userId]);
      if (userExists.rows.length === 0) {
        return res.status(404).json({ success: false, message: 'User not found' });
      }
      // Create default if missing (fallback if trigger didn't run)
      const created = await db.query(
        `INSERT INTO player_resources (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING RETURNING *`,
        [userId]
      );
      // Re-fetch
      const retry = await db.query('SELECT * FROM player_resources WHERE user_id = $1', [userId]);
      return res.json({ success: true, resources: retry.rows[0] });
    }
    res.json({ success: true, resources: result.rows[0] });
  } catch (err) {
    console.error('Get resources error:', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// PUT /api/resources/:userId - set absolute values (full replace)
router.put('/:userId', authorizeSelfOrAdmin, validate(resourcesUpdateSchema), async (req, res) => {
  const { userId } = req.params;
  const updates = req.body;

  try {
    // Build dynamic SET clause safely
    const fields = Object.keys(updates);
    const values = Object.values(updates);
    const setClause = fields.map((f, i) => `${f} = $${i + 1}`).join(', ');

    const result = await db.query(
      `UPDATE player_resources SET ${setClause}, updated_at = NOW()
       WHERE user_id = $${fields.length + 1}
       RETURNING user_id, food, metal, ammo, hard_currency, updated_at`,
      [...values, userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Resources not found for user' });
    }

    res.json({ success: true, message: 'Resources updated', resources: result.rows[0] });
  } catch (err) {
    console.error('Put resources error:', err);
    if (err.code === '23514') { // check violation
      return res.status(400).json({ success: false, message: 'Resource value cannot be negative', detail: err.message });
    }
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// PATCH /api/resources/:userId/increment - atomic add/subtract (for gathering, spending, trading)
// Body: { resource: "food"|"metal"|"ammo"|"hard_currency", amount: 10 }
router.patch('/:userId/increment', authorizeSelfOrAdmin, validate(resourcesIncrementSchema), async (req, res) => {
  const { userId } = req.params;
  const { resource, amount } = req.body;

  const allowed = ['food', 'metal', 'ammo', 'hard_currency'];
  if (!allowed.includes(resource)) {
    return res.status(400).json({ success: false, message: `Invalid resource. Allowed: ${allowed.join(', ')}` });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // Lock row for update to prevent race conditions (important for multiplayer economy)
    const current = await client.query(
      `SELECT ${resource} FROM player_resources WHERE user_id = $1 FOR UPDATE`,
      [userId]
    );

    if (current.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, message: 'Resources not found' });
    }

    const newValue = current.rows[0][resource] + amount;
    if (newValue < 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        success: false,
        message: `Insufficient ${resource}. Current: ${current.rows[0][resource]}, tried to change by ${amount}`,
      });
    }

    const updated = await client.query(
      `UPDATE player_resources SET ${resource} = $1, updated_at = NOW() WHERE user_id = $2 RETURNING *`,
      [newValue, userId]
    );

    await client.query('COMMIT');
    res.json({
      success: true,
      message: `${amount >= 0 ? 'Added' : 'Deducted'} ${Math.abs(amount)} ${resource}`,
      resources: updated.rows[0],
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Increment error:', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  } finally {
    client.release();
  }
});

// POST /api/resources/:userId/transfer - transfer resources between players (example game logic)
router.post('/:userId/transfer', authenticateToken, async (req, res) => {
  const { userId } = req.params; // sender = authenticated user
  const { toUserId, resource, amount } = req.body;

  if (String(req.user.id) !== String(userId)) {
    return res.status(403).json({ success: false, message: 'You can only transfer from your own account' });
  }
  if (!toUserId || !resource || !amount) {
    return res.status(400).json({ success: false, message: 'toUserId, resource, amount required' });
  }
  if (!['food', 'metal', 'ammo', 'hard_currency'].includes(resource)) {
    return res.status(400).json({ success: false, message: 'Invalid resource' });
  }
  if (amount <= 0) {
    return res.status(400).json({ success: false, message: 'Amount must be positive' });
  }

  const client = await db.getClient();
  try {
    await client.query('BEGIN');

    // Lock both rows in consistent order to avoid deadlock
    const [lowId, highId] = [Math.min(userId, toUserId), Math.max(userId, toUserId)];
    await client.query('SELECT user_id FROM player_resources WHERE user_id IN ($1, $2) FOR UPDATE', [lowId, highId]);

    const sender = await client.query(`SELECT ${resource} FROM player_resources WHERE user_id = $1`, [userId]);
    const receiver = await client.query(`SELECT ${resource} FROM player_resources WHERE user_id = $1`, [toUserId]);

    if (sender.rows.length === 0 || receiver.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, message: 'Sender or receiver resources not found' });
    }
    if (sender.rows[0][resource] < amount) {
      await client.query('ROLLBACK');
      return res.status(400).json({ success: false, message: `Insufficient ${resource}` });
    }

    await client.query(`UPDATE player_resources SET ${resource} = ${resource} - $1 WHERE user_id = $2`, [amount, userId]);
    await client.query(`UPDATE player_resources SET ${resource} = ${resource} + $1 WHERE user_id = $2`, [amount, toUserId]);

    const senderAfter = await client.query('SELECT * FROM player_resources WHERE user_id = $1', [userId]);

    await client.query('COMMIT');
    res.json({ success: true, message: `Transferred ${amount} ${resource} to user ${toUserId}`, resources: senderAfter.rows[0] });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Transfer error:', err);
    res.status(500).json({ success: false, message: 'Internal server error' });
  } finally {
    client.release();
  }
});

module.exports = router;
