const allowedOrigins = new Set([
  'https://redo-orcin.vercel.app',
  'https://olx-orcin.vercel.app',
  'http://localhost:8780',
  'http://127.0.0.1:8780',
]);
const recentRequests = new Map();

module.exports = async function customerCare(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Vary', 'Origin');
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Use POST to send a message.' });
  }

  const origin = req.headers.origin;
  if (origin && !allowedOrigins.has(origin)) return res.status(403).json({ error: 'This site is not allowed to use redo care.' });
  const ip = String(req.headers['x-forwarded-for'] || 'unknown').split(',')[0].trim();
  const now = Date.now();
  const recent = (recentRequests.get(ip) || []).filter(time => now - time < 60_000);
  if (recent.length >= 15) return res.status(429).json({ error: 'Please wait a moment before sending another message.' });
  recent.push(now);
  recentRequests.set(ip, recent);

  if (!process.env.GEMINI_API_KEY) return res.status(503).json({ error: 'Customer care is not configured yet. Please try again later.' });
  const body = typeof req.body === 'string' ? (() => { try { return JSON.parse(req.body); } catch { return null; } })() : req.body;
  const messages = Array.isArray(body?.messages) ? body.messages.slice(-12) : [];
  if (!messages.length || messages.length > 12 || Buffer.byteLength(JSON.stringify(body || {}), 'utf8') > 14_000) {
    return res.status(400).json({ error: 'Please send a shorter message and try again.' });
  }
  const contents = messages.map(message => {
    const text = typeof message?.text === 'string' ? message.text.trim() : '';
    if (!text || text.length > 1200) return null;
    return { role: message.role === 'model' ? 'model' : 'user', parts: [{ text }] };
  });
  if (contents.some(message => !message)) return res.status(400).json({ error: 'Messages must be between 1 and 1,200 characters.' });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 22_000);
  try {
    const response = await fetch('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': process.env.GEMINI_API_KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: 'You are redo care, the helpful customer-care assistant for redo, a second-hand marketplace in India. Answer clearly, warmly, and briefly in the user’s language. Help with browsing, categories, posting/editing ads, chats, Deal OK, account settings, and practical marketplace safety. Never claim to access a user account, alter a listing, send messages, verify a payment, or complete an action. Give step-by-step directions in the redo site when useful. Do not request passwords, one-time codes, card/bank details, or private phone numbers. For urgent account or safety issues, direct them to the site’s Help & support link. If you do not know, say so.' }] },
        contents,
        generationConfig: { temperature: 0.45, maxOutputTokens: 500 },
      }),
      signal: controller.signal,
    });
    if (!response.ok) {
      const providerError = await response.json().catch(() => ({}));
      const providerMessage = String(providerError?.error?.message || '').replace(/AIza[\w-]{20,}|AQ\.[\w.-]{20,}/g, '[redacted]').slice(0, 180);
      console.error('Gemini customer-care request failed', response.status, providerError?.error?.status || 'unknown', providerMessage);
      return res.status(502).json({ error: 'redo care could not reply just now. Please try again.' });
    }
    const data = await response.json();
    const reply = data?.candidates?.[0]?.content?.parts?.map(part => part.text || '').join('').trim();
    if (!reply) return res.status(502).json({ error: 'redo care could not form a reply just now. Please try again.' });
    return res.status(200).json({ reply });
  } catch (error) {
    if (error?.name === 'AbortError') return res.status(504).json({ error: 'That took too long. Please try again.' });
    console.error('Gemini customer-care connection failed');
    return res.status(502).json({ error: 'redo care is temporarily unavailable. Please try again.' });
  } finally {
    clearTimeout(timer);
  }
};
