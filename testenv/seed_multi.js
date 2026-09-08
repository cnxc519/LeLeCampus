// 多用户 UI 测试种子：A(挂单方/卖家) + B(接单方/买家)，输出双 token 到 harness/ui_seed_multi.json
// 数据覆盖：待确认接单申请(A的铃铛)、双方书市消息、位置消息、多时间点挂单
const fs = require('fs');
const BASE = 'http://127.0.0.1:8898';

async function api(method, path, token, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await res.json().catch(() => ({}));
  if (!j.ok) throw new Error(`${method} ${path} -> ${res.status} ${j.error && j.error.msg}`);
  return j.data;
}

(async () => {
  const RUN = Date.now().toString(36);
  const schools = await api('GET', '/api/schools');
  const schoolId = schools.list[0].id, pgId = schools.list[0].playgrounds[0].id;

  // A：挂单方/卖家（男）；B：接单方/买家（女）
  const c1 = await api('POST', '/api/auth/send-code', null, { email: `ma_${RUN}@test.com`, purpose: 'register' });
  const A = await api('POST', '/api/auth/register', null, { email: `ma_${RUN}@test.com`, code: c1.dev_code, nickname: '阿明（挂单方）', school_id: schoolId, gender: 'male' });
  const c2 = await api('POST', '/api/auth/send-code', null, { email: `mb_${RUN}@test.com`, purpose: 'register' });
  const B = await api('POST', '/api/auth/register', null, { email: `mb_${RUN}@test.com`, code: c2.dev_code, nickname: '小红（接单方）', school_id: schoolId, gender: 'female' });

  // 挂单：每天 18/19/20 三个时间点，全周，5 次 —— 用于测试按小时接单
  const slots = [];
  for (let d = 0; d < 7; d++) for (const h of [18, 19, 20]) slots.push({ day: d, hour: h });
  const ord = await api('POST', '/api/orders', A.token, { playground_id: pgId, remark: '帮我占座+带饭，谢谢', price_cents: 300, slots, run_count: 5, gender_required: 'none' });

  // B 接第一天的单（产生：A 的 take_request 通知 + 代跑会话）
  const detail = await api('GET', '/api/orders/' + ord.id, B.token);
  const day1 = detail.available_dates[0];
  const take = await api('POST', '/api/orders/' + ord.id + '/take', B.token, { date: day1.date, hours: day1.hours });
  await api('POST', '/api/chats/' + take.chat_id + '/messages', B.token, { type: 'text', text: '你好，接了你的单，明天 8 点 55 操场北门见？' });
  await api('POST', '/api/chats/' + take.chat_id + '/messages', B.token, { type: 'location', text: '工学部松园操场北门', lat: 30.54, lon: 114.37 });
  await api('POST', '/api/chats/' + take.chat_id + '/messages', A.token, { type: 'text', text: '好的，我到时候穿蓝色外套，到了一起去' });
  // A 侧未读：B 再发一条
  await api('POST', '/api/chats/' + take.chat_id + '/messages', B.token, { type: 'text', text: '好嘞，不见不散～' });

  // 书市：A 出书，B 联系（买卖双方各有多条消息 + 位置）
  const book = await api('POST', '/api/books', A.token, { title: '线性代数（同济第七版）', course: '线性代数', cond: 2, price_cents: 1200, note: '九成新，无划线' });
  const contact = await api('POST', '/api/books/' + book.id + '/contact', B.token, {});
  await api('POST', '/api/book-chats/' + contact.chat_id + '/messages', B.token, { type: 'text', text: '同学你好，书还在吗？12 块诚心要' });
  await api('POST', '/api/book-chats/' + contact.chat_id + '/messages', A.token, { type: 'text', text: '在的在的，可以面交，图书馆门口？' });
  await api('POST', '/api/book-chats/' + contact.chat_id + '/messages', B.token, { type: 'location', text: '东区图书馆正门', lat: 30.55, lon: 114.36 });
  await api('POST', '/api/book-chats/' + contact.chat_id + '/messages', A.token, { type: 'text', text: '行，明天下午三点，我先不带书钱，当面验书' });

  // 第二本书：B 卖 A 买（让 A 也有书市会话）
  const book2 = await api('POST', '/api/books', B.token, { title: '高等数学上册', course: '高等数学', cond: 3, price_cents: 800 });
  const contact2 = await api('POST', '/api/books/' + book2.id + '/contact', A.token, {});
  await api('POST', '/api/book-chats/' + contact2.chat_id + '/messages', A.token, { type: 'text', text: '这本书还在吗？' });

  const seed = {
    tokenA: A.token, myIdA: A.user.id, nicknameA: A.user.nickname,
    tokenB: B.token, myIdB: B.user.id, nicknameB: B.user.nickname,
    chatId: take.chat_id, bookChatId: contact.chat_id, bookChatId2: contact2.chat_id, orderId: ord.id, bookId: book.id,
  };
  fs.writeFileSync(__dirname + '/harness/ui_seed_multi.json', JSON.stringify(seed, null, 2));
  console.log('seeded', JSON.stringify(seed));
})().catch((e) => { console.error('SEED FAILED:', e.message); process.exit(1); });
