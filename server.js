import express from 'express';
import fs from 'fs';

const KEY = process.env.ANTHROPIC_API_KEY;
const MODEL = process.env.MODEL || 'claude-sonnet-5-5';
const FILE = 'kb.json';
let db = {};
try { db = JSON.parse(fs.readFileSync(FILE, 'utf8')); } catch {}
const persist = () => fs.writeFileSync(FILE, JSON.stringify(db));

const system = (kb) => `Sen SUHBATDOSH AI — J.A.R.V.I.S uslubidagi aqlli, xushmuomala o'zbekcha yordamchisan.
Yaratuvching: Abduholiqov Azizbek. Kim seni yaratgan/yasagan deb so'rashsa, doim shunday javob ber.
Bilgan narsangni aniq va qisqa ayt. Aniq bilmasang, o'ylab topma: foydalanuvchidan so'ra va o'rgatishini iltimos qil.
Agar oldingi xabaringda savol bergan bo'lsang va foydalanuvchi o'rgatayotgan bo'lsa, rahmat ayt va bilimni save ga yoz.
Foydalanuvchi o'zi haqida yoki biror fakt aytsa ham save ga yoz.
O'rganilgan bilimlar: ${JSON.stringify(kb.slice(-60))}
Faqat JSON qaytar: {"reply":"...","save":[{"q":"mavzu","a":"fakt"}]} (save bo'sh bo'lishi mumkin).`;

const app = express();
app.use(express.json({ limit: '100kb' }));

app.post('/chat', async (req, res) => {
  try {
    const { deviceId, messages } = req.body;
    if (!deviceId || !Array.isArray(messages)) return res.status(400).json({ error: 'bad request' });
    const kb = (db[deviceId] ||= []);
    let msgs = messages.slice(-10);
    while (msgs.length && msgs[0].role !== 'user') msgs.shift();

    const r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-api-key': KEY, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({ model: MODEL, max_tokens: 800, system: system(kb), messages: msgs }),
    });
    const data = await r.json();
    const text = (data.content || []).map((c) => c.text || '').join('');
    let out;
    try { out = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1)); }
    catch { out = { reply: text || 'Kechirasiz, javob olinmadi.', save: [] }; }

    for (const s of out.save || []) if (s && s.q && s.a) kb.push({ q: s.q, a: s.a });
    if (out.save?.length) persist();
    res.json({ reply: out.reply, learned: out.save?.length || 0 });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'server error' });
  }
});

app.listen(process.env.PORT || 3000, () => console.log('SUHBATDOSH server ishga tushdi'));
