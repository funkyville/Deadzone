# 🚀 Step-by-Step Deployment Guide — Survival Game Backend

Your backend has 3 deployment options. Follow **Option A** for a public URL.

---

## ✅ What You Have Ready

- GitHub: **https://github.com/funkyville/Deadzone** (pushed, includes `render.yaml`, `Dockerfile`, `docker-compose.yml`)
- Code: Express + PostgreSQL schema + Redis session + JWT auth — fully tested locally

---

## OPTION A: Render.com (Recommended - Free, 5 min)

This gives you a **public HTTPS URL** like `https://survival-api.onrender.com`

### Step 1: Create Render Account
1. Go to https://render.com → **Get Started**
2. Sign in with GitHub → Authorize `funkyville`
3. You will see your repos including `Deadzone`

### Step 2: Deploy with Blueprint (uses your `render.yaml` automatically)
1. In Render Dashboard click **New + → Blueprint**
2. Select **funkyville/Deadzone** → **Connect**
3. Render reads `render.yaml` and shows:
   - **Web Service:** `survival-api` (Node)
   - **Database:** `survival_postgres` (PostgreSQL free)
4. Click **Apply**
5. Wait 2-3 minutes for build:
   ```
   ==> Installing dependencies...
   ==> Building...
   ==> Starting: npm start
   ==> PostgreSQL created
   ```

### Step 3: Set Environment Variables
In Render → Your Service → **Environment**:
- `NODE_ENV` = `production` (already set)
- `JWT_SECRET` = click **Generate** (or paste a 32+ char random string)
- `JWT_EXPIRES_IN` = `7d`
- `DATABASE_URL` = auto-filled from the Postgres you created (copy value)
- `REDIS_URL` = see Step 4

### Step 4: Add Redis (Required for sessions/coordinates)
Render free does not include Redis. Use Upstash (free):
1. Go to https://upstash.com → Sign in with GitHub
2. **Create Database** → Type: Redis → Region: closest to you → Create
3. Copy **Redis URL** (looks like `redis://default:PASS@host:6379`)
4. Back in Render → **Environment** → Add:
   - Key: `REDIS_URL` Value: `redis://...` (from Upstash)
5. Click **Save Changes** → Render auto-redeploys

### Step 5: Run Database Migration
Render runs `npm start` but you need to create tables:
1. In Render → Your Service → **Shell** (top right)
2. Run:
   ```bash
   npm run migrate
   ```
   Expected:
   ```
   ✅ Migration completed successfully
   Tables: continents, users, player_resources, player_stats
   Continents seeded: 6
   ```
3. Alternative: Use Render Postgres → **Connect → External Connection** → copy `psql` command and run locally:
   ```bash
   psql $DATABASE_URL -f src/db/schema.sql
   ```

### Step 6: Test Your Live Public URL
Render gives you a URL like `https://survival-api-xxxx.onrender.com`

Test in terminal/Postman:
```bash
# 1. Health check (should be {"status":"ok","postgresql":"connected","redis":"connected"})
curl https://YOUR_URL.onrender.com/api/health

# 2. Register a survivor
curl -X POST https://YOUR_URL.onrender.com/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"wastelander","email":"test@deadzone.com","password":"password123","continent_id":1}'

# Copy the "token" from response

# 3. Verify token
curl https://YOUR_URL.onrender.com/api/auth/verify \
  -H "Authorization: Bearer <paste_token>"

# 4. Create session (store coordinates in Redis)
curl -X POST https://YOUR_URL.onrender.com/api/session \
  -H "Authorization: Bearer <paste_token>" \
  -H "Content-Type: application/json" \
  -d '{"x":500,"y":600,"zone":"forest","status":"online"}'

# 5. Move (update coords)
curl -X PUT https://YOUR_URL.onrender.com/api/session/1/coordinates \
  -H "Authorization: Bearer <paste_token>" \
  -H "Content-Type: application/json" \
  -d '{"x":505,"y":610}'

# 6. Add resources
curl -X PATCH https://YOUR_URL.onrender.com/api/resources/1/increment \
  -H "Authorization: Bearer <paste_token>" \
  -H "Content-Type: application/json" \
  -d '{"resource":"metal","amount":25}'
```

✅ If health shows `connected`, your game can now call the API!

---

## OPTION B: Local Docker (Test Production Locally)

No GitHub needed, runs Postgres+Redis+API together:

```bash
git clone https://github.com/funkyville/Deadzone
cd Deadzone  # your repo folder (contains docker-compose.yml)

# Create .env from example
cp .env.example .env
# Edit .env: set JWT_SECRET to a random 32-char string

# Start everything
docker-compose up --build

# Wait for:
#   survival_postgres | database system is ready
#   survival_redis    | Ready to accept connections
#   survival_api      | 🚀 Survival Game API running on http://0.0.0.0:3000

# Test (same as above but localhost)
curl http://localhost:3000/api/health
curl http://localhost:3000/api/auth/register ... etc
```

Stop: `docker-compose down`

---

## OPTION C: Railway.app (Alternative Free)

1. Go to https://railway.app → Login with GitHub
2. **New Project → Deploy from GitHub** → select `Deadzone`
3. **Add Plugin → PostgreSQL** → Railway injects `DATABASE_URL` automatically
4. **Add Plugin → Redis** → Railway injects `REDIS_URL`
5. **Variables** → Add:
   - `JWT_SECRET` = random 32+ chars
   - `JWT_EXPIRES_IN` = `7d`
6. **Deploy** → Wait → Click **Settings → Generate Domain** to get public URL
7. Run migration in Railway Shell:
   ```bash
   npm run migrate
   ```

Test same curl commands with the generated domain.

---

## 🔧 Environment Variables Cheat Sheet

You need these in production:

| Variable | Where to get it | Example |
|----------|-----------------|---------|
| `PORT` | Render/Railway sets automatically | `3000` |
| `NODE_ENV` | Set to `production` | `production` |
| `DATABASE_URL` | Render Postgres → Internal URL or Railway Postgres | `postgresql://user:pass@host:5432/db` |
| `REDIS_URL` | Upstash Redis → Redis URL | `redis://default:pass@host:6379` |
| `JWT_SECRET` | Generate: `openssl rand -base64 32` | `a_long_random_string_32_chars_min` |
| `JWT_EXPIRES_IN` | Your choice | `7d` |
| `CORS_ORIGIN` | Your game domain or `*` for testing | `*` |

---

## 🧪 Testing Locally Right Now (Without Deploying)

You have a **preview server running here** in the workspace:

```bash
# These work now (no deploy needed):
curl http://localhost:3000/api/health
curl http://localhost:3000/api/demo  # shows all endpoints

# Register locally
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"demo","email":"demo@test.com","password":"password123"}'
```

Use this to test your mobile game logic before deploying.

---

## ❗ Troubleshooting

| Problem | Fix |
|---------|-----|
| `500 Internal server error` on register | Check Render Logs → usually `JWT_SECRET` missing or `DATABASE_URL` wrong. Set them in Environment. |
| `Redis error` on session endpoints | `REDIS_URL` not set or wrong. Add Upstash URL. |
| `DATABASE_URL` connection timeout | Render DB may be sleeping (free tier). First request takes 30s. Retry. |
| Tables not found | Run `npm run migrate` in Render Shell. |
| `401 Unauthorized` | Did you add `Authorization: Bearer <token>` header? Token from login/register. |
| `403 Forbidden` on resources | You can only access your own `userId`. Login as that user. |

---

## 🔒 Security After Deploy

After your public URL works:
1. Delete exposed tokens at https://github.com/settings/tokens
2. In `Deadzone` repo on GitHub → **Settings → Secrets** → add `JWT_SECRET` there if using Actions
3. Change `JWT_SECRET` in Render after first deploy (Generate new)

---

## Next Steps

- Public URL working → Connect your Unity/Unreal/Godot mobile client to `https://YOUR_URL/api/...`
- Need real-time movement? Ask to add **Socket.io** (uses Redis pub/sub) for multiplayer map
- Need file uploads? Ask to add S3

**Your current live test URL (workspace only):** `http://localhost:3000` — working now
**Your future public URL:** `https://YOUR_APP.onrender.com` — after Option A steps above
