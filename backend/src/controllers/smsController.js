const { sendSmsMessage, extractProviderMessage } = require('../services/smsService');

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

    const response = await sendSmsMessage({
      phoneNumber: phone_number,
      message,
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

    const errMsg = extractProviderMessage(data) || `HTTP ${response.status}`;
    return res.status(response.status).json({ status: response.status, message: errMsg, data });
  } catch (error) {
    console.error('[SMS] send error:', error.message);
    const status = error.status || error.response?.status || 502;
    const message = error.response?.data?.message || error.message || 'SMS provider request failed';
    return res.status(status).json({ status, message });
  }
}

module.exports = { sendSms };
