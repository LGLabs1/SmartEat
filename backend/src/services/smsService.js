const axios = require('axios');

const IPROG_ENDPOINT = 'https://www.iprogsms.com/api/v1/sms_messages';

function extractProviderMessage(data) {
  if (typeof data === 'string' && data.trim()) return data.trim();
  if (data && typeof data === 'object') {
    if (typeof data.message === 'string' && data.message.trim()) return data.message.trim();
    if (typeof data.error === 'string' && data.error.trim()) return data.error.trim();
    if (typeof data.detail === 'string' && data.detail.trim()) return data.detail.trim();
  }
  return '';
}

async function sendSmsMessage({ phoneNumber, message }) {
  const apiToken = String(
    process.env.IPROG_SMS_API_TOKEN || process.env.SMS_API_TOKEN || '',
  ).trim();
  if (!apiToken) {
    const error = new Error('SMS provider token is not configured on the server');
    error.status = 500;
    error.code = 'sms_not_configured';
    throw error;
  }

  const response = await axios.post(
    IPROG_ENDPOINT,
    {
      api_token: apiToken,
      phone_number: String(phoneNumber),
      message: String(message),
    },
    {
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      timeout: 60000,
      validateStatus: () => true,
    },
  );

  return { status: response.status, data: response.data };
}

async function sendPasswordResetSms({ phoneNumber, code, expiresMinutes }) {
  const message =
    `SmartEat: Your password reset code is ${code}. ` +
    `It expires in ${expiresMinutes} minutes. ` +
    'If you did not request this, ignore this message.';

  const result = await sendSmsMessage({ phoneNumber, message });
  if (result.status < 200 || result.status >= 300) {
    const error = new Error(
      extractProviderMessage(result.data) ||
        `SMS provider request failed (HTTP ${result.status})`,
    );
    error.status = 502;
    error.code = 'sms_send_failed';
    throw error;
  }

  return { status: result.status, message: 'SMS sent' };
}

module.exports = {
  extractProviderMessage,
  sendSmsMessage,
  sendPasswordResetSms,
};
