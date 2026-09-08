// WebSocket 实时推送测试：A 连 WS，B 发消息/触发通知，验证 A 实时收到
const WebSocket = require('./server/node_modules/ws');
const BASE = 'http://127.0.0.1:8898';

async function api(method, path, token, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await res.json().catch(() => ({}));
  if (!j.ok) throw new Error(`${method} ${path} -> ${j.error && j.error.msg}`);
  return j.data;
}

(async () => {
  const RUN = Date.now().toString(36);
  const c1 = await api('POST', '/api/auth/send-code', null, { email: `wsa_${RUN}@test.com`, purpose: 'register' });
  const A = await api('POST', '/api/auth/register', null, { email: `wsa_${RUN}@test.com`, code: c1.dev_code, nickname: '实甲', school_id: 1, gender: 'male' });
  const c2 = await api('POST', '/api/auth/send-code', null, { email: `wsb_${RUN}@test.com`, purpose: 'register' });
  const B = await api('POST', '/api/auth/register', null, { email: `wsb_${RUN}@test.com`, code: c2.dev_code, nickname: '实乙', school_id: 1, gender: 'female' });

  // A 挂全周时间格的单
  const slots = [];
  for (let d = 0; d < 7; d++) for (let h = 8; h <= 23; h++) slots.push({ day: d, hour: h });
  const ord = await api('POST', '/api/orders', A.token, { playground_id: 1, remark: 'WS 测试单', price_cents: 250, slots, run_count: 2, gender_required: 'none' });
  const detail = await api('GET', '/api/orders/' + ord.id, B.token);
  const take = await api('POST', '/api/orders/' + ord.id + '/take', B.token, { date: detail.available_dates[0].date });

  // A 连 WebSocket
  const ws = new WebSocket(BASE.replace('http', 'ws') + '/ws?token=' + A.token);
  const received = [];
  ws.on('message', (d) => received.push(JSON.parse(d.toString())));
  await new Promise((r) => ws.on('open', r));
  await new Promise((r) => setTimeout(r, 300));

  // B 发聊天消息 -> A 应实时收到 t=chat
  await api('POST', '/api/chats/' + take.chat_id + '/messages', B.token, { type: 'text', text: 'WS 实时消息测试' });
  await new Promise((r) => setTimeout(r, 600));

  // B 再次接 A 的另一单会触发 take_request 通知 -> A 应收到 t=notif
  const take2 = await api('POST', '/api/orders/' + ord.id + '/take', B.token, { date: detail.available_dates[1].date });
  await new Promise((r) => setTimeout(r, 600));

  const chatEvt = received.find((e) => e.t === 'chat' && e.m && e.m.text === 'WS 实时消息测试');
  const notifEvt = received.find((e) => e.t === 'notif' && e.n && e.n.type === 'take_request');
  console.log('WS chat 事件:', chatEvt ? 'PASS' : 'FAIL', JSON.stringify(received.map((e) => e.t)));
  console.log('WS notif 事件:', notifEvt ? 'PASS' : 'FAIL');
  ws.close();
  process.exit(chatEvt && notifEvt ? 0 : 1);
})().catch((e) => { console.error('FATAL', e.message); process.exit(2); });
