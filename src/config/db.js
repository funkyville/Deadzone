const { Pool } = require('pg');
require('dotenv').config();

// Support both DATABASE_URL and individual PG* vars
const pool = process.env.DATABASE_URL
  ? new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    })
  : new Pool({
      host: process.env.PGHOST || 'localhost',
      port: parseInt(process.env.PGPORT || '5432', 10),
      database: process.env.PGDATABASE || 'survival_game',
      user: process.env.PGUSER || 'postgres',
      password: process.env.PGPASSWORD || 'postgres',
    });

// Test connection on startup
pool.on('connect', () => {
  console.log('✅ PostgreSQL pool connected');
});

pool.on('error', (err) => {
  console.error('❌ Unexpected PG pool error:', err.message);
});

async function query(text, params) {
  const start = Date.now();
  const res = await pool.query(text, params);
  const duration = Date.now() - start;
  if (process.env.NODE_ENV === 'development') {
    console.log('executed query', { text: text.substring(0, 80), duration, rows: res.rowCount });
  }
  return res;
}

async function getClient() {
  const client = await pool.connect();
  return client;
}

module.exports = {
  pool,
  query,
  getClient,
};
