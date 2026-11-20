const axios = require('axios');

const EMAILJS_ENDPOINT = 'https://api.emailjs.com/api/v1.0/email/send';

function readEmailConfig() {
  const serviceId = String(process.env.EMAILJS_SERVICE_ID || '').trim();
  const templateId = String(process.env.EMAILJS_PASSWORD_RESET_TEMPLATE_ID || '').trim();
  const publicKey = String(process.env.EMAILJS_PUBLIC_KEY || '').trim();
  const privateKey = String(process.env.EMAILJS_PRIVATE_KEY || '').trim();

  if (!serviceId || !templateId || !publicKey) {
    const error = new Error('Email service is not configured on the server');
    error.status = 500;
    error.code = 'email_not_configured';
    throw error;
  }

  return { serviceId, templateId, publicKey, privateKey };
}

function providerDetail(data) {
  if (typeof data === 'string' && data.trim()) return data.trim();
  if (data && typeof data === 'object') {
    if (typeof data.message === 'string' && data.message.trim()) return data.message.trim();
    if (typeof data.error === 'string' && data.error.trim()) return data.error.trim();
  }
  return '';
}

async function sendPasswordResetEmail({ to, code, expiresMinutes }) {
  const config = readEmailConfig();
  const payload = {
    service_id: config.serviceId,
    template_id: config.templateId,
    user_id: config.publicKey,
    template_params: {
      to_email: to,
      code,
      expires_minutes: String(expiresMinutes),
    },
  };

  if (config.privateKey) {
    payload.accessToken = config.privateKey;
  }

  const response = await axios.post(EMAILJS_ENDPOINT, payload, {
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    timeout: 30000,
    validateStatus: () => true,
  });

  if (response.status < 200 || response.status >= 300) {
    const error = new Error(
      providerDetail(response.data) || `Email provider request failed (HTTP ${response.status})`,
    );
    error.status = 502;
    error.code = 'email_send_failed';
    throw error;
  }

  return { status: response.status, message: 'Email sent' };
}

module.exports = {
  sendPasswordResetEmail,
};
