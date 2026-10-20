/**
 * Run schema migration via Node (alternative to psql)
 * Usage: npm run migrate  (requires DATABASE_URL or PG* vars in .env)
 */
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { pool } = require('../config/db');

async function migrate() {
  try {
    console.log('🚀 Starting migration...');
    const schemaPath = path.join(__dirname, 'schema.sql');
    const sql = fs.readFileSync(schemaPath, 'utf8');

    const client = await pool.connect();
    await client.query(sql);
    client.release();

    console.log('✅ Migration completed successfully');
    console.log('   Tables: continents, users, player_resources, player_stats');
    console.log('   Views: v_player_full');
    
    // Show counts
    const c = await pool.query('SELECT count(*) FROM continents');
    console.log(`   Continents seeded: ${c.rows[0].count}`);
    
    await pool.end();
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err);
    process.exit(1);
  }
}

migrate();
