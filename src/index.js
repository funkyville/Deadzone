require('dotenv').config();
const app = require('./app');
const { pool } = require('./config/db');
const { initRedis } = require('./config/redis');

const PORT = process.env.PORT || 3000;

async function start() {
  try {
    // 1. Test PostgreSQL connection with retries (Render DB can be slow to start)
    let retries = 5;
    let connected = false;
    while (retries > 0 && !connected) {
      try {
        const client = await pool.connect();
        const res = await client.query('SELECT NOW() as now');
        console.log(`✅ PostgreSQL connected @ ${res.rows[0].now}`);
        client.release();
        connected = true;
      } catch (dbErr) {
        retries--;
        console.warn(`⚠️ PostgreSQL not ready (${dbErr.message}), retries left: ${retries}`);
        if (retries === 0) {
          // Don't crash - start in preview mode so health check still passes
          console.error('❌ PostgreSQL failed after retries - starting with in-memory fallback');
          console.error('   Check DATABASE_URL env var. Health will show error but app will stay up.');
          break;
        }
        await new Promise(r => setTimeout(r, 5000));
      }
    }

    // 2. Initialize Redis (optional - don't crash if fails)
    try {
      await initRedis();
    } catch (redisErr) {
      console.warn('⚠️ Redis failed to connect - session endpoints will error until Redis is available:', redisErr.message);
      // Don't crash - allow API to run without Redis for development
    }

    // 3. Start HTTP server (always)
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`\n🚀 Survival Game API running on http://0.0.0.0:${PORT}`);
      console.log(`   Environment: ${process.env.NODE_ENV || 'development'}`);
      console.log(`   Health: http://localhost:${PORT}/api/health`);
      console.log(`   Github: https://github.com/funkyville/Deadzone\n`);
    });
  } catch (err) {
    console.error('❌ Failed to start server:', err);
    // Still try to start server for health check
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`⚠️ Server started in degraded mode on ${PORT} - check logs`);
    });
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received - shutting down');
  try { await pool.end(); } catch {}
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('SIGINT received - shutting down');
  try { await pool.end(); } catch {}
  process.exit(0);
});

start();
