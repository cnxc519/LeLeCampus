// 为 UI 试验台灌数据：两个用户 + 挂单/接单/聊天/书市会话/通知，输出 ui_seed.json
const fs = require('fs');
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
  const schools = await api('GET', '/api/schools');
  const schoolId = schools.list[0].id, pgId = schools.list[0].playgrounds[0].id;

  const c1 = await api('POST', '/api/auth/send-code', null, { email: `uia_${RUN}@test.com`, purpose: 'register' });
  const A = await api('POST', '/api/auth/register', null, { email: `uia_${RUN}@test.com`, code: c1.dev_code, nickname: '甲（UI）', school_id: schoolId, gender: 'male' });
  const c2 = await api('POST', '/api/auth/send-code', null, { email: `uib_${RUN}@test.com`, purpose: 'register' });
  const B = await api('POST', '/api/auth/register', null, { email: `uib_${RUN}@test.com`, code: c2.dev_code, nickname: '乙（UI）', school_id: schoolId, gender: 'female' });

  // A 挂单 -> B 接单（产生会话 + 待确认申请 + A 的 take_request 通知）
  const slots = [];
  for (let d = 0; d < 7; d++) for (let h = 8; h <= 23; h++) slots.push({ day: d, hour: h });
  const ord = await api('POST', '/api/orders', A.token, { playground_id: pgId, remark: '帮我占座+带饭，谢谢', price_cents: 300, slots, run_count: 5, gender_required: 'none' });
  const detail = await api('GET', '/api/orders/' + ord.id, B.token);
  const take = await api('POST', '/api/orders/' + ord.id + '/take', B.token, { date: detail.available_dates[0].date, hours: detail.available_dates[0].hours });
  await api('POST', '/api/chats/' + take.chat_id + '/messages', B.token, { type: 'text', text: '你好，接了你的单，明天 8 点 55 操场北门见？' });
  await api('POST', '/api/chats/' + take.chat_id + '/messages', B.token, { type: 'location', text: '工学部松园操场北门', lat: 30.54, lon: 114.37 });

  // A 出书 -> B 联系卖家（产生书市会话 + 系统消息）
  const book = await api('POST', '/api/books', A.token, { title: '线性代数（同济第七版）', course: '线性代数', cond: 2, price_cents: 1200, note: '九成新，无划线' });
  const contact = await api('POST', '/api/books/' + book.id + '/contact', B.token, {});
  await api('POST', '/api/book-chats/' + contact.chat_id + '/messages', B.token, { type: 'text', text: '同学你好，书还在吗？12 块诚心要' });

  const seed = { tokenA: A.token, myIdA: A.user.id, nicknameA: A.user.nickname, chatId: take.chat_id, bookChatId: contact.chat_id, orderId: ord.id };
  fs.writeFileSync(__dirname + '/harness/ui_seed.json', JSON.stringify(seed));
  console.log('seeded', JSON.stringify(seed));
})().catch((e) => { console.error('FATAL', e.message); process.exit(1); });
