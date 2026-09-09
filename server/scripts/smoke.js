// 端到端冒烟测试（无支付版）：注册 -> 挂单 -> 接单 -> 确认 -> 完成 -> 评价 -> 管理端
const BASE = 'http://127.0.0.1:8899';
let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass++; console.log(`  ✅ ${name}`); }
  else { fail++; console.log(`  ❌ ${name}`, extra !== undefined ? JSON.stringify(extra) : ''); }
}
async function api(method, path, body, token) {
  const r = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return r.json();
}
async function codeOf(email, purpose) {
  const r = await api('POST', '/api/auth/send-code', { email, purpose });
  return r.data && r.data.dev_code;
}

(async () => {
  console.log('== 1. 注册与登录 ==');
  const a = 'alice@test.com', b = 'bob@test.com';
  const ca = await codeOf(a, 'register');
  const ra = await api('POST', '/api/auth/register', { email: a, code: ca, nickname: '阿乐', school_id: 1, gender: 'female' });
  check('A 注册', ra.ok, ra);
  const ta = ra.data.token;
  const inv = await api('GET', '/api/invite', null, ta);
  const cb2 = await codeOf(b, 'register');
  const rb2 = await api('POST', '/api/auth/register', { email: b, code: cb2, nickname: '小跑', school_id: 1, gender: 'male', invite_code: inv.data.invite_code });
  check('B 注册(带邀请码)', rb2.ok, rb2);
  const tb = rb2.data.token;

  console.log('== 2. A 发布挂单 ==');
  const po = await api('POST', '/api/orders', { playground_id: 1, remark: '帮拿快递到松园操场', price_cents: 500, slots: [{ day: 1, hour: 9 }, { day: 3, hour: 9 }], run_count: 3, gender_required: 'none' }, ta);
  check('发布挂单', po.ok, po);
  const oid = po.data.id;

  const list = await api('GET', '/api/orders', null, tb);
  check('B 看到挂单列表', list.ok && list.data.list.some((o) => o.id === oid), list.data && list.data.list[0]);
  const det = await api('GET', `/api/orders/${oid}`, null, tb);
  check('详情含可用日期', det.ok && det.data.available_dates.length === 3, det.data && det.data.available_dates);
  const date = det.data.available_dates[0].date;
  const hours = [det.data.available_dates[0].hours[0]]; // 一天仅可接一个时间点

  console.log('== 3. B 接单 -> A 直接确认（无支付） ==');
  const tk = await api('POST', `/api/orders/${oid}/take`, { date, hours }, tb);
  check('B 接单成功', tk.ok, tk);
  const runId = tk.data.run_id;

  const reqs = await api('GET', '/api/active', null, ta);
  check('A 看到待确认申请', reqs.ok && reqs.data.list.some((r) => r.id === runId && r.status === 'requested'), reqs.data.list);

  const c2 = await api('POST', `/api/orders/requests/${runId}/confirm`, {}, ta);
  check('A 直接确认成功', c2.ok, c2);

  console.log('== 4. 进行中 -> 完成 ==');
  const active = await api('GET', '/api/active', null, ta);
  check('A 进行中有该单', active.data.list.some((r) => r.id === runId && r.status === 'confirmed'), active.data.list);
  const cp = await api('POST', `/api/active/${runId}/complete`, {}, ta);
  check('委托完成', cp.ok, cp);
  const meB = await api('GET', '/api/auth/me', null, tb);
  check('B 完成数 +1', meB.data.completed_count === 1, meB.data);

  console.log('== 5. 评价 ==');
  const rv1 = await api('POST', '/api/active/' + runId + '/review', { score: 5, comment: '很靠谱！' }, ta);
  check('A 评价成功', rv1.ok, rv1);
  const rv2 = await api('POST', '/api/active/' + runId + '/review', { score: 4, comment: '准时' }, tb);
  check('B 评价成功', rv2.ok, rv2);
  const rv3 = await api('POST', '/api/active/' + runId + '/review', { score: 3 }, ta);
  check('重复评价被拒', !rv3.ok, rv3);

  console.log('== 6. 聊天（文字+位置） ==');
  const chats = await api('GET', '/api/chats', null, tb);
  const chatId = chats.data.list.find((c) => c.order_id === oid).id;
  check('B 看到会话', !!chatId, chats.data.list);
  const m1 = await api('POST', `/api/chats/${chatId}/messages`, { type: 'text', text: '明天见' }, tb);
  check('发文字', m1.ok, m1);
  const m2 = await api('POST', `/api/chats/${chatId}/messages`, { type: 'location', text: '松园操场正门', lat: 30.535, lon: 114.361 }, ta);
  check('发位置', m2.ok, m2);

  console.log('== 7. 历史记录与公告 ==');
  const h1 = await api('GET', '/api/me/history?role=poster', null, ta);
  check('A 挂单历史', h1.data.list.some((r) => r.id === runId));
  const notices = await api('GET', '/api/notices', null, ta);
  check('公告接口', notices.ok);

  console.log('== 8. 管理端 ==');
  const al = await api('POST', '/api/admin/login', { username: 'admin', password: 'leleadmin888' });
  check('管理端登录', al.ok, al);
  const at = al.data.token;
  const dash = await api('GET', '/api/admin/dashboard', null, at);
  check('管理端概览', dash.ok && dash.data.users >= 2, dash.data);
  const us = await api('GET', '/api/admin/users?q=bob', null, at);
  check('管理端搜索用户', us.ok && us.data.list.some((u) => u.email === b));

  console.log('== 9. 版本检查 ==');
  const v = await api('GET', '/api/version');
  check('版本接口', v.ok, v);

  // 收尾：清空测试数据
  const { db, tx } = require('../src/db');
  tx(() => {
    for (const t of ['users', 'orders', 'runs', 'chats', 'chat_messages', 'notifications', 'email_codes', 'reviews', 'notices', 'reports', 'checkins', 'books', 'book_chats', 'book_messages', 'book_reports']) {
      if (t === 'users') db.prepare(`DELETE FROM users WHERE id!=0`).run();
      else if (t === 'notices') db.prepare(`DELETE FROM notices`).run();
      else db.prepare(`DELETE FROM ${t}`).run();
    }
  });
  db.close();
  console.log(`\n结果: ${pass} 通过, ${fail} 失败`);
  process.exit(fail > 0 ? 1 : 0);
})().catch((e) => { console.error('测试异常:', e); process.exit(1); });
