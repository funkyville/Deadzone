-- ============================================================
-- Survival Game - PostgreSQL Schema
-- ============================================================
-- Run: psql -U postgres -d survival_game -f src/db/schema.sql
-- Or:  npm run migrate (requires DATABASE_URL in .env)
-- ============================================================

-- Enable UUID extension if you want UUIDs later (optional)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------
-- 1. CONTINENTS (lookup for user continent_id)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS continents (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    code VARCHAR(10) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed continents
INSERT INTO continents (name, code, description) VALUES
    ('North America', 'NA', 'Wastelands of North America'),
    ('Europe', 'EU', 'Ruins of Europe'),
    ('Asia', 'AS', 'Asian Badlands'),
    ('Africa', 'AF', 'African Outback'),
    ('South America', 'SA', 'Jungles of South America'),
    ('Oceania', 'OC', 'Islands of Oceania')
ON CONFLICT (code) DO NOTHING;

-- ------------------------------------------------------------
-- 2. USERS TABLE
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    continent_id INTEGER REFERENCES continents(id) ON DELETE SET NULL ON UPDATE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for fast lookup
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_continent_id ON users(continent_id);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ------------------------------------------------------------
-- 3. PLAYER_RESOURCES TABLE
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS player_resources (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE ON UPDATE CASCADE,
    food INTEGER NOT NULL DEFAULT 100 CHECK (food >= 0),
    metal INTEGER NOT NULL DEFAULT 50 CHECK (metal >= 0),
    ammo INTEGER NOT NULL DEFAULT 30 CHECK (ammo >= 0),
    hard_currency INTEGER NOT NULL DEFAULT 0 CHECK (hard_currency >= 0),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_player_resources_user_id ON player_resources(user_id);

DROP TRIGGER IF EXISTS trg_player_resources_updated_at ON player_resources;
CREATE TRIGGER trg_player_resources_updated_at
    BEFORE UPDATE ON player_resources
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Optional: Auto-create resources row when user is created
CREATE OR REPLACE FUNCTION create_default_resources()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO player_resources (user_id, food, metal, ammo, hard_currency)
    VALUES (NEW.id, 100, 50, 30, 0);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_create_resources_on_user ON users;
CREATE TRIGGER trg_create_resources_on_user
    AFTER INSERT ON users
    FOR EACH ROW EXECUTE FUNCTION create_default_resources();

-- ------------------------------------------------------------
-- 4. (Optional) PLAYER_STATS for survival mechanics
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS player_stats (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    level INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
    xp INTEGER NOT NULL DEFAULT 0 CHECK (xp >= 0),
    health INTEGER NOT NULL DEFAULT 100 CHECK (health >= 0 AND health <= 100),
    last_login TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_player_stats_updated_at ON player_stats;
CREATE TRIGGER trg_player_stats_updated_at
    BEFORE UPDATE ON player_stats
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE FUNCTION create_default_stats()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO player_stats (user_id) VALUES (NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_create_stats_on_user ON users;
CREATE TRIGGER trg_create_stats_on_user
    AFTER INSERT ON users
    FOR EACH ROW EXECUTE FUNCTION create_default_stats();

-- ------------------------------------------------------------
-- 5. Views (convenience)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW v_player_full AS
SELECT 
    u.id,
    u.username,
    u.email,
    u.continent_id,
    c.name AS continent_name,
    c.code AS continent_code,
    u.created_at,
    pr.food,
    pr.metal,
    pr.ammo,
    pr.hard_currency,
    ps.level,
    ps.xp,
    ps.health
FROM users u
LEFT JOIN continents c ON c.id = u.continent_id
LEFT JOIN player_resources pr ON pr.user_id = u.id
LEFT JOIN player_stats ps ON ps.user_id = u.id;
