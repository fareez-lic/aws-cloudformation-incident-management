import { scryptSync, timingSafeEqual } from 'node:crypto';
import express from 'express';
import session from 'express-session';
import connectPgSimple from 'connect-pg-simple';
import { rateLimit } from 'express-rate-limit';
import { initializeDatabase, pool, waitForDatabase } from './db.js';

const app = express();
const port = Number(process.env.PORT || 5000);
const host = process.env.HOST || '127.0.0.1';
const validSeverities = new Set(['low', 'medium', 'high', 'critical']);
const validStatuses = new Set(['open', 'investigating', 'resolved']);
const sessionCookieSecure = process.env.SESSION_COOKIE_SECURE === 'true';

for (const key of ['ADMIN_USERNAME', 'ADMIN_PASSWORD_SALT', 'ADMIN_PASSWORD_HASH', 'SESSION_SECRET']) {
  if (!process.env[key]) {
    throw new Error(`Missing required authentication setting: ${key}. Run scripts/setup-database.sh.`);
  }
}

const PgSession = connectPgSimple(session);
app.set('trust proxy', 1);
app.use(express.json({ limit: '100kb' }));
app.use(session({
  store: new PgSession({
    pool,
    tableName: 'user_sessions',
    createTableIfMissing: true,
  }),
  name: 'incident.sid',
  secret: process.env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  rolling: true,
  cookie: {
    httpOnly: true,
    sameSite: 'strict',
    secure: sessionCookieSecure,
    maxAge: 8 * 60 * 60 * 1000,
  },
}));

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many sign-in attempts. Try again in 15 minutes.' },
});

function requireAuth(request, response, next) {
  if (!request.session?.user) {
    return response.status(401).json({ message: 'Please sign in to continue.' });
  }
  return next();
}

function requireSameOrigin(request, response, next) {
  if (['GET', 'HEAD', 'OPTIONS'].includes(request.method)) return next();
  const origin = request.get('origin');
  if (!origin) {
    return response.status(403).json({ message: 'Origin header required.' });
  }
  try {
    if (new URL(origin).host !== request.get('host')) {
      return response.status(403).json({ message: 'Cross-origin request rejected.' });
    }
  } catch {
    return response.status(403).json({ message: 'Invalid request origin.' });
  }
  return next();
}

app.get('/health', async (_request, response) => {
  try {
    await pool.query('SELECT 1');
    response.status(200).json({
      service: 'incident-backend',
      status: 'healthy',
      database: 'connected',
    });
  } catch {
    response.status(503).json({
      service: 'incident-backend',
      status: 'unhealthy',
      database: 'disconnected',
      message: 'Database unavailable',
    });
  }
});

app.get('/api/auth/me', (request, response) => {
  if (!request.session.user) {
    return response.status(401).json({ message: 'Not signed in.' });
  }
  return response.json({ user: request.session.user });
});

app.post('/api/auth/login', loginLimiter, requireSameOrigin, async (request, response, next) => {
  try {
    const { username, password } = request.body ?? {};
    const suppliedPassword = typeof password === 'string' && password.length <= 1024 ? password : '';
    const actualHash = scryptSync(suppliedPassword, process.env.ADMIN_PASSWORD_SALT, 64);
    const expectedHash = Buffer.from(process.env.ADMIN_PASSWORD_HASH, 'hex');
    const passwordMatches =
      expectedHash.length === actualHash.length && timingSafeEqual(actualHash, expectedHash);

    if (
      typeof username !== 'string' ||
      username !== process.env.ADMIN_USERNAME ||
      !passwordMatches
    ) {
      return response.status(401).json({ message: 'Invalid username or password.' });
    }

    await new Promise((resolve, reject) => {
      request.session.regenerate((error) => (error ? reject(error) : resolve()));
    });
    request.session.user = { username: process.env.ADMIN_USERNAME };
    await new Promise((resolve, reject) => {
      request.session.save((error) => (error ? reject(error) : resolve()));
    });
    return response.json({ user: request.session.user });
  } catch (error) {
    return next(error);
  }
});

app.post('/api/auth/logout', requireSameOrigin, (request, response, next) => {
  request.session.destroy((error) => {
    if (error) return next(error);
    response.clearCookie('incident.sid', {
      httpOnly: true,
      sameSite: 'strict',
      secure: sessionCookieSecure,
    });
    return response.status(204).send();
  });
});

app.use('/api/incidents', requireAuth, requireSameOrigin);

app.get('/api/incidents', async (_request, response, next) => {
  try {
    const result = await pool.query(
      `SELECT id, title, description, severity, status, created_at, updated_at
       FROM incidents
       ORDER BY created_at DESC`,
    );
    response.json(result.rows);
  } catch (error) {
    next(error);
  }
});

app.post('/api/incidents', async (request, response, next) => {
  try {
    const { title, description = '', severity = 'medium', status = 'open' } = request.body ?? {};

    if (!title || typeof title !== 'string' || title.trim().length < 3) {
      return response.status(400).json({
        message: 'title is required and must contain at least 3 characters',
      });
    }
    if (!validSeverities.has(severity)) {
      return response.status(400).json({ message: 'invalid severity' });
    }
    if (!validStatuses.has(status)) {
      return response.status(400).json({ message: 'invalid status' });
    }

    const result = await pool.query(
      `INSERT INTO incidents (title, description, severity, status)
       VALUES ($1, $2, $3, $4)
       RETURNING id, title, description, severity, status, created_at, updated_at`,
      [title.trim(), String(description).trim(), severity, status],
    );
    return response.status(201).json(result.rows[0]);
  } catch (error) {
    return next(error);
  }
});

app.patch('/api/incidents/:id/status', async (request, response, next) => {
  try {
    const incidentId = Number(request.params.id);
    const { status } = request.body ?? {};

    if (!Number.isInteger(incidentId) || incidentId <= 0) {
      return response.status(400).json({ message: 'invalid incident id' });
    }
    if (!validStatuses.has(status)) {
      return response.status(400).json({ message: 'invalid status' });
    }

    const result = await pool.query(
      `UPDATE incidents
       SET status = $1, updated_at = NOW()
       WHERE id = $2
       RETURNING id, title, description, severity, status, created_at, updated_at`,
      [status, incidentId],
    );
    if (result.rowCount === 0) {
      return response.status(404).json({ message: 'incident not found' });
    }
    return response.json(result.rows[0]);
  } catch (error) {
    return next(error);
  }
});

app.delete('/api/incidents/:id', async (request, response, next) => {
  try {
    const incidentId = Number(request.params.id);
    if (!Number.isInteger(incidentId) || incidentId <= 0) {
      return response.status(400).json({ message: 'invalid incident id' });
    }

    const result = await pool.query('DELETE FROM incidents WHERE id = $1', [incidentId]);
    if (result.rowCount === 0) {
      return response.status(404).json({ message: 'incident not found' });
    }
    return response.status(204).send();
  } catch (error) {
    return next(error);
  }
});

app.use((error, _request, response, _next) => {
  console.error(error);
  response.status(500).json({ message: 'internal server error' });
});

async function start() {
  try {
    await waitForDatabase();
    await initializeDatabase();
    app.listen(port, host, () => {
      console.log(`Incident backend listening on http://${host}:${port}`);
    });
  } catch (error) {
    console.error('Backend startup failed:', error);
    process.exit(1);
  }
}

async function shutdown(signal) {
  console.log(`${signal} received. Closing database connections.`);
  await pool.end();
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

start();
