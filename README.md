# 🧟 Survival Game Backend — Express + PostgreSQL + Redis + JWT

A production-ready Node.js backend for a mobile survival game, built with **Express**, **PostgreSQL**, **Redis**, and **JWT Authentication**.

---

## 📦 Features

- **Users table** (`id, username, email, password_hash, continent_id, created_at`) + `continents` lookup
- **Player Resources** table (`food, metal, ammo, hard_currency`) with atomic increment & transfer logic
- **JWT Auth** — register, login, verify token
- **Redis** — cache active player `session states + coordinates (x, y)` with 2-hour TTL + fast updates

---

## 🗂 Project Structure

```
survival-backend/
├── src/
│   ├── app.js                 # Express app (no listen)
│   ├── index.js               # Entry — connects PG + Redis then listens
│   ├── config/
│   │   ├── db.js              # PG Pool (DATABASE_URL or PG* vars)
│   │   └── redis.js           # Redis client + session helpers
│   ├── middleware/
│   │   └── auth.js            # authenticateToken, authorizeSelfOrAdmin
│   ├── routes/
│   │   ├── auth.js            # /api/auth/*
│   │   ├── resources.js       # /api/resources/*
│   │   └── session.js         # /api/session/* (Redis)
│   ├── db/
│   │   ├── schema.sql         # Full PostgreSQL schema
│   │   └── migrate.js         # Node migration runner
│   └── utils/
│       └── validation.js      # Joi schemas
├── docker-compose.yml
├── Dockerfile
├── package.json
└── .env.example
```

---

## 🚀 Quick Start

### 1. Clone & Install

```bash
git clone <repo>
cd survival-backend
npm install
cp .env.example .env
# Edit .env — set JWT_SECRET (min 32 chars), DATABASE_URL, REDIS_URL
```

### 2. Option A: Local Postgres + Redis

Install [PostgreSQL 16](https://www.postgresql.org/download/) & [Redis 7](https://redis.io/download/)

```bash
createdb survival_game
npm run migrate        # runs src/db/schema.sql via Node
# or
psql -U postgres -d survival_game -f src/db/schema.sql

redis-server           # in another terminal
npm run dev            # nodemon on :3000
```

### 3. Option B: Docker (recommended)

```bash
docker-compose up --build
# API -> http://localhost:3000
# Postgres -> localhost:5432 (postgres/postgres)
# Redis -> localhost:6379
# Schema auto-runs on first boot via /docker-entrypoint-initdb.d/
```

### 4. Verify

```bash
curl http://localhost:3000/api/health
```

Expected:
```json
{
  "success": true,
  "status": "ok",
  "services": {
    "postgresql": "connected",
    "redis": "connected (PONG)"
  }
}
```

---

## 🗄 PostgreSQL Schema

### `continents` (lookup)

| id | name | code | description |
|---|---|---|---|
| 1 | North America | NA | ... |
| 2 | Europe | EU | ... |
| ... | ... | ... | ... |

Seeded with 6 continents.

### `users`

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    continent_id INTEGER REFERENCES continents(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### `player_resources`

```sql
CREATE TABLE player_resources (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    food INTEGER DEFAULT 100 CHECK (food >= 0),
    metal INTEGER DEFAULT 50 CHECK (metal >= 0),
    ammo INTEGER DEFAULT 30 CHECK (ammo >= 0),
    hard_currency INTEGER DEFAULT 0 CHECK (hard_currency >= 0),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
-- Auto-created on user insert via trigger
```

### `player_stats` (optional)

```sql
CREATE TABLE player_stats (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    level INTEGER DEFAULT 1,
    xp INTEGER DEFAULT 0,
    health INTEGER DEFAULT 100,
    last_login TIMESTAMPTZ
);
```

### View

```sql
SELECT * FROM v_player_full; -- joins users + continents + resources + stats
```

---

## 🔐 Auth Endpoints

### POST /api/auth/register

Register a new survivor.

```bash
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "wastelander42",
    "email": "wastelander@example.com",
    "password": "s3cur3Pass!",
    "continent_id": 1
  }'
```

Response `201`:
```json
{
  "success": true,
  "user": { "id": 1, "username": "wastelander42", "email": "...", "continent_id": 1, "created_at": "..." },
  "resources": { "food": 100, "metal": 50, "ammo": 30, "hard_currency": 0 },
  "token": "eyJhbGciOiJIUzI1NiIs..."
}
```

### POST /api/auth/login

```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{ "email": "wastelander@example.com", "password": "s3cur3Pass!" }'
```

Response `200`:
```json
{
  "success": true,
  "user": { "id": 1, "username": "wastelander42", "email": "...", "continent_id": 1 },
  "token": "eyJhbGc..."
}
```

### GET /api/auth/verify

Verify token validity (protected).

```bash
curl http://localhost:3000/api/auth/verify \
  -H "Authorization: Bearer <token>"
```

Response:
```json
{
  "success": true,
  "message": "Token is valid",
  "user": { "id": 1, "username": "...", "continent_name": "North America", "continent_code": "NA" },
  "tokenPayload": { "id": 1, "username": "...", "iat": 123, "exp": 456 }
}
```

### GET /api/auth/me

Returns current user + resources.

---

## 🎒 Player Resources Endpoints (PostgreSQL)

All require `Authorization: Bearer <token>` and enforce **self-or-admin** access.

### GET /api/resources/:userId

```bash
curl http://localhost:3000/api/resources/1 \
  -H "Authorization: Bearer <token>"
```

### PUT /api/resources/:userId

Set absolute values (e.g., admin correction).

```bash
curl -X PUT http://localhost:3000/api/resources/1 \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{ "food": 200, "ammo": 100 }'
```

### PATCH /api/resources/:userId/increment

**Atomic** increment/decrement — use for gathering, consuming, buying. Prevents negative & race conditions via `SELECT ... FOR UPDATE`.

```bash
# Gather 25 metal
curl -X PATCH http://localhost:3000/api/resources/1/increment \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{ "resource": "metal", "amount": 25 }'

# Spend 5 ammo (shooting)
curl -X PATCH http://localhost:3000/api/resources/1/increment \
  -H "Authorization: Bearer <token>" \
  -d '{ "resource": "ammo", "amount": -5 }'
```

### POST /api/resources/:userId/transfer

Transfer between players (transactional, deadlock-safe).

```bash
curl -X POST http://localhost:3000/api/resources/1/transfer \
  -H "Authorization: Bearer <token>" \
  -d '{ "toUserId": 2, "resource": "food", "amount": 20 }'
```

---

## ⚡ Redis — Active Session & Coordinates

Redis is used as a **fast ephemeral cache** for player position & session state. Data expires in 2h unless refreshed (player keeps moving).

**Key pattern:** `player:session:{userId}` → JSON string

```json
{
  "userId": "1",
  "x": 1024.5,
  "y": 2048.0,
  "zone": "wasteland",
  "status": "online",
  "health": 85,
  "username": "wastelander42",
  "continent_id": 1,
  "lastActive": "2026-10-20T17:00:00.000Z"
}
```

### POST /api/session

Create/refresh session (called on login / respawn).

```bash
curl -X POST http://localhost:3000/api/session \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{ "x": 100, "y": 200, "zone": "desert_outpost", "status": "online", "health": 100 }'
```

### GET /api/session/:userId

Fetch a player's live coordinates.

```bash
curl http://localhost:3000/api/session/1 \
  -H "Authorization: Bearer <token>"
```

### PUT /api/session/:userId/coordinates

**Hot path** — client calls this every 1-3 seconds while moving.

```bash
curl -X PUT http://localhost:3000/api/session/1/coordinates \
  -H "Authorization: Bearer <token>" \
  -d '{ "x": 105.5, "y": 210.2, "zone": "wasteland" }'
```

### GET /api/session

List all online players (for world map). Uses `SCAN`.

```bash
curl "http://localhost:3000/api/session?count=100&cursor=0" \
  -H "Authorization: Bearer <token>"
```

### PATCH /api/session/:userId/status

Update `status` (`online|idle|in_combat|offline`) or `health` without moving.

### DELETE /api/session/:userId

Clear on logout.

---

## 🔧 Environment Variables

| Var | Description | Example |
|---|---|---|
| `PORT` | API port | `3000` |
| `DATABASE_URL` | Postgres connection | `postgresql://postgres:postgres@localhost:5432/survival_game` |
| `REDIS_URL` | Redis connection | `redis://localhost:6379` |
| `JWT_SECRET` | Secret (min 32 chars) | `your_super_secret...` |
| `JWT_EXPIRES_IN` | Token TTL | `7d` |

See `.env.example`.

---

## 🧪 Testing with curl (full flow)

```bash
# 1. Register
TOKEN=$(curl -s -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","email":"test@test.com","password":"password123","continent_id":2}' | jq -r .token)

# 2. Verify
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/auth/verify

# 3. Get resources
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/resources/1

# 4. Gather resources
curl -X PATCH http://localhost:3000/api/resources/1/increment \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"resource":"food","amount":50}'

# 5. Create session
curl -X POST http://localhost:3000/api/session \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"x":500,"y":600,"zone":"forest"}'

# 6. Move
curl -X PUT http://localhost:3000/api/session/1/coordinates \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"x":505,"y":610}'

# 7. Get session
curl -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/session/1
```

---

## 🛡 Security Notes

- Passwords hashed with `bcryptjs` (10 rounds)
- JWT signed with `JWT_SECRET`, 7-day expiry, verified on protected routes
- `helmet` + `cors` + rate limiting on `/api/auth`
- `Joi` validation on all inputs
- `CHECK (food >= 0)` etc. prevents negative resources at DB level
- `SELECT ... FOR UPDATE` prevents double-spend races
- Auth middleware checks `Authorization: Bearer <token>`
- `authorizeSelfOrAdmin` prevents accessing other players' inventories

---

## 📈 Next Steps (where to extend)

- Add `socket.io` / WebSockets for real-time position broadcast (Redis pub/sub)
- Persist session history to Postgres on logout for analytics
- Add inventory table (`items` + `player_inventory` many-to-many)
- Leaderboards via Redis Sorted Sets (`ZADD leaderboard`)
- Refresh tokens & blacklisting (Redis `blacklist:{jti}`)

---

## 📄 License

MIT
