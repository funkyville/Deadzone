require('dotenv').config();
const app = require('./app');
const { pool } = require('./config/db');
const { initRedis } = require('./config/redis');

const PORT = process.env.PORT || 3000;

async function start() {
  try {
    // 1. Test PostgreSQL connection
    const client = await pool.connect();
    const res = await client.query('SELECT NOW() as now');
    console.log(`✅ PostgreSQL connected @ ${res.rows[0].now}`);
    client.release();

    // 2. Initialize Redis
    try {
      await initRedis();
    } catch (redisErr) {
      console.warn('⚠️ Redis failed to connect - session endpoints will error until Redis is available:', redisErr.message);
      // Don't crash - allow API to run without Redis for development
    }

    // 3. Start HTTP server
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`\n🚀 Survival Game API running on http://0.0.0.0:${PORT}`);
      console.log(`   Environment: ${process.env.NODE_ENV || 'development'}`);
      console.log(`   Docs: http://localhost:${PORT}/api/health\n`);
    });
  } catch (err) {
    console.error('❌ Failed to start server:', err);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('SIGTERM received - shutting down');
  await pool.end();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('SIGINT received - shutting down');
  await pool.end();
  process.exit(0);
});

start();
