const axios = require('axios');

/**
 * POST /api/sms/send
 * Proxies SMS send to IPROG server-side to avoid browser CORS and keep the
 * provider token out of the client. Requires a verified Firebase user.
 */
async function sendSms(req, res) {
  try {
    const { phone_number, message } = req.body || {};
    if (!phone_number || !message) {
      return res.status(400).json({ status: 400, message: 'phone_number and message are required' });
    }

    const apiToken = (process.env.IPROG_SMS_API_TOKEN || process.env.SMS_API_TOKEN || '').trim();
    if (!apiToken) {
      return res.status(500).json({
        status: 500,
        message: 'SMS provider token not configured on server (set IPROG_SMS_API_TOKEN)',
      });
    }

    const payload = {
      api_token: apiToken,
      phone_number: String(phone_number),
      message: String(message),
    };

    const response = await axios.post('https://www.iprogsms.com/api/v1/sms_messages', payload, {
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      timeout: 60000,
      validateStatus: () => true,
    });

    const data = response.data;
    const ok = response.status >= 200 && response.status < 300;
    if (ok) {
      const messageId = data && typeof data === 'object'
        ? (data.message_id || data.id || data.messageId || null)
        : null;
      return res.status(response.status).json({
        status: response.status,
        message: (data && data.message) || 'SMS sent',
        message_id: messageId,
        data,
      });
    }

    const errMsg = (data && typeof data === 'object' && (data.message || data.error))
      ? (data.message || data.error)
      : (typeof data === 'string' && data ? data : `HTTP ${response.status}`);
    return res.status(response.status).json({ status: response.status, message: errMsg, data });
  } catch (error) {
    console.error('[SMS] send error:', error.message);
    const status = error.response?.status || 502;
    const message = error.response?.data?.message || error.message || 'SMS provider request failed';
    return res.status(status).json({ status, message });
  }
}

module.exports = { sendSms };
