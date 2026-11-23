const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

function parseAllowedOrigins(value) {
  if (!value || !String(value).trim()) {
    return [
      'http://localhost:3000',
      'http://localhost:5173',
      'http://127.0.0.1:3000',
      'http://127.0.0.1:5173',
      'https://smart-eat-2eaf7.web.app',
      'https://smart-eat-2eaf7.firebaseapp.com',
    ];
  }
  return String(value)
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
}

const allowedOrigins = parseAllowedOrigins(process.env.CORS_ORIGIN);
const allowAnyOrigin =
  allowedOrigins.includes('*') && process.env.NODE_ENV !== 'production';

const corsOptions = {
  origin(origin, callback) {
    if (!origin) return callback(null, true);
    if (allowAnyOrigin || allowedOrigins.includes(origin)) return callback(null, true);
    const error = new Error('Origin not allowed by CORS');
    error.status = 403;
    return callback(error);
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-cron-secret'],
  exposedHeaders: ['Retry-After'],
  credentials: false,
  maxAge: 600,
};

// Initialize Express app
const app = express();

const trustProxy = String(process.env.TRUST_PROXY || '').trim();
app.set('trust proxy', trustProxy
  ? (/^\d+$/.test(trustProxy) ? Number(trustProxy) : trustProxy)
  : 1);

// Middleware
app.use(cors(corsOptions));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging middleware
app.use((req, res, next) => {
  console.log(`${req.method} ${req.path}`);
  next();
});

// Routes
app.use('/api/analytics', require('./routes/analyticsRoutes'));
app.use('/api/inventory', require('./routes/inventoryRoutes'));
app.use('/api/chatbot', require('./routes/chatbotRoutes'));
app.use('/api/sms', require('./routes/smsRoutes'));
app.use('/api/notifications', require('./routes/notificationRoutes'));
app.use('/api/auth', require('./routes/authRoutes'));

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'Backend server is running', timestamp: new Date() });
});

// Error handling middleware
app.use((err, req, res, next) => {
  const status = Number(err.status) || 500;
  const expose = Boolean(err.expose) || status < 500;
  const message = expose && err.message ? err.message : 'Internal server error';

  if (status >= 500) {
    console.error('Error:', err.message);
  } else {
    console.warn('Request error:', err.message);
  }

  const payload = {
    error: message,
    code: err.code || 'internal_error',
  };
  if (err.retryAfterSeconds) {
    payload.retryAfterSeconds = err.retryAfterSeconds;
  }

  res.status(status).json(payload);
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// Initialize server
const PORT = process.env.PORT || 3000;

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`✓ Smart Eat Backend running on port ${PORT}`);

    // Best-effort: verify Sage's AI configuration at startup. Failures are
    // logged and ignored.
    try {
      require('./controllers/chatbotController').warmUpModel();
    } catch (err) {
      console.warn('[Sage] Warm-up could not start:', err.message);
    }
  });
}

module.exports = app;
