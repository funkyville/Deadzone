const { createClient } = require('redis');
require('dotenv').config();

let redisClient;

async function initRedis() {
  const url = process.env.REDIS_URL || `redis://${process.env.REDIS_HOST || 'localhost'}:${process.env.REDIS_PORT || 6379}`;

  redisClient = createClient({
    url,
    password: process.env.REDIS_PASSWORD || undefined,
    socket: {
      reconnectStrategy: (retries) => {
        if (retries > 10) {
          console.error('❌ Redis max retries reached');
          return new Error('Redis max retries');
        }
        return Math.min(retries * 100, 3000);
      },
    },
  });

  redisClient.on('error', (err) => console.error('❌ Redis Client Error', err));
  redisClient.on('connect', () => console.log('🔌 Redis connecting...'));
  redisClient.on('ready', () => console.log('✅ Redis ready'));
  redisClient.on('reconnecting', () => console.log('🔄 Redis reconnecting...'));

  await redisClient.connect();
  return redisClient;
}

function getRedis() {
  if (!redisClient || !redisClient.isOpen) {
    throw new Error('Redis client not initialized. Call initRedis() first.');
  }
  return redisClient;
}

// Helpers for session states
const SESSION_PREFIX = 'player:session:';
const SESSION_TTL_SECONDS = 60 * 60 * 2; // 2 hours, refresh on activity

async function setPlayerSession(userId, sessionData, ttl = SESSION_TTL_SECONDS) {
  const client = getRedis();
  const key = `${SESSION_PREFIX}${userId}`;
  // Store as hash + JSON for flexibility
  const payload = {
    userId: String(userId),
    x: sessionData.x ?? 0,
    y: sessionData.y ?? 0,
    zone: sessionData.zone || 'wasteland',
    status: sessionData.status || 'online', // online | idle | in_combat | offline
    health: sessionData.health ?? 100,
    lastActive: new Date().toISOString(),
    ...sessionData,
  };
  await client.set(key, JSON.stringify(payload), { EX: ttl });
  return payload;
}

async function getPlayerSession(userId) {
  const client = getRedis();
  const key = `${SESSION_PREFIX}${userId}`;
  const raw = await client.get(key);
  if (!raw) return null;
  return JSON.parse(raw);
}

async function updatePlayerCoordinates(userId, x, y, extra = {}) {
  const session = await getPlayerSession(userId);
  if (!session) {
    // Create new session if not exists
    return setPlayerSession(userId, { x, y, ...extra });
  }
  const updated = { ...session, x, y, lastActive: new Date().toISOString(), ...extra };
  return setPlayerSession(userId, updated);
}

async function deletePlayerSession(userId) {
  const client = getRedis();
  const key = `${SESSION_PREFIX}${userId}`;
  return client.del(key);
}

async function getAllActiveSessions(cursor = '0', count = 50) {
  const client = getRedis();
  // SCAN for session keys - efficient for production
  const result = await client.scan(cursor, { MATCH: `${SESSION_PREFIX}*`, COUNT: count });
  const sessions = [];
  for (const key of result.keys) {
    const raw = await client.get(key);
    if (raw) sessions.push(JSON.parse(raw));
  }
  return { cursor: result.cursor, sessions };
}

module.exports = {
  initRedis,
  getRedis,
  setPlayerSession,
  getPlayerSession,
  updatePlayerCoordinates,
  deletePlayerSession,
  getAllActiveSessions,
  SESSION_PREFIX,
  SESSION_TTL_SECONDS,
};
