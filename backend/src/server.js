const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');

dotenv.config();

// Initialize Express app
const app = express();

// Middleware
app.use(cors());
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

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'Backend server is running', timestamp: new Date() });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : undefined,
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// Initialize server
const PORT = process.env.PORT || 3000;

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

module.exports = app;
