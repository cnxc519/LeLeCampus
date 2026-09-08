// 第三组冒烟：评价 / 公告 / 举报 / 提现限频 / 学校管理
const BASE = 'http://127.0.0.1:8899';
const TS = Date.now(); // 时间戳邮箱，避免限流与残留冲突
let pass = 0, fail = 0;
const check = (name, cond, extra) => { if (cond) { pass++; console.log(`  ✅ ${name}`); } else { fail++; console.log(`  ❌ ${name}`, JSON.stringify(extra)); } };
async function api(method, path, body, token) {
  const r = await fetch(BASE + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return r.json();
}
async function codeOf(email, purpose) {
  const r = await api('POST', '/api/auth/send-code', { email, purpose });
  return r.data.dev_code;
}
async function regUser(email, nick, gender) {
  const c = await codeOf(email, 'register');
  const r = await api('POST', '/api/auth/register', { email, code: c, nickname: nick, school_id: 1, gender });
  return r.data.token;
}

(async () => {
  console.log('== 1. 评价 ==');
  const ta = await regUser('r1_' + TS + '@t.com', '评价者', 'female');
  const tb = await regUser('r2_' + TS + '@t.com', '被评者', 'male');
  const o = await api('POST', '/api/orders', { playground_id: 1, remark: '评价测试单', price_cents: 500, slots: [{ day: 2, hour: 10 }], run_count: 1, gender_required: 'none' }, ta);
  const det = await api('GET', '/api/orders/' + o.data.id, null, tb);
  const date = det.data.available_dates[0].date;
  const hours = det.data.available_dates[0].hours;
  const tk = await api('POST', '/api/orders/' + o.data.id + '/take', { date, hours }, tb);
  await api('POST', '/api/orders/requests/' + tk.data.run_id + '/confirm', {}, ta);
  await api('POST', '/api/active/' + tk.data.run_id + '/complete', {}, ta);

  const rv1 = await api('POST', '/api/active/' + tk.data.run_id + '/review', { score: 5, comment: '非常靠谱！' }, ta);
  check('挂单方评价成功', rv1.ok, rv1);
  const rv2 = await api('POST', '/api/active/' + tk.data.run_id + '/review', { score: 4, comment: '准时到达' }, tb);
  check('接单方评价成功', rv2.ok, rv2);
  const rv3 = await api('POST', '/api/active/' + tk.data.run_id + '/review', { score: 3 }, ta);
  check('重复评价被拒绝', !rv3.ok, rv3);
  const prof2 = await api('GET', '/api/users/' + (await api('GET', '/api/auth/me', null, tb)).data.id + '/profile', null, ta);
  check('主页显示评价统计', prof2.data.user.review_count === 1 && prof2.data.user.review_good === 1, prof2.data.user);

  console.log('== 2. 公告 ==');
  const adminLogin = await api('POST', '/api/admin/login', { username: 'admin', password: 'leleadmin888' });
  const at = adminLogin.data.token;
  const n1 = await api('POST', '/api/admin/notices', { title: '系统上线啦', content: '欢迎大家使用乐乐代跑！' }, at);
  check('发布公告', n1.ok, n1);
  const notices = await api('GET', '/api/notices', null, ta);
  check('App 看到公告', notices.ok && notices.data.list.length === 1 && notices.data.list[0].title === '系统上线啦', notices.data);
  const n2 = await api('PUT', '/api/admin/notices/' + n1.data.id, { status: 'offline' }, at);
  check('公告下线', n2.ok, n2);
  const notices2 = await api('GET', '/api/notices', null, ta);
  check('下线后 App 不可见', notices2.data.list.length === 0, notices2.data);

  console.log('== 3. 举报 ==');
  const rp = await api('POST', '/api/active/' + tk.data.run_id + '/report', { reason: '对方在聊天中辱骂我' }, tb);
  check('提交举报', rp.ok, rp);
  const rpShort = await api('POST', '/api/active/' + tk.data.run_id + '/report', { reason: '短' }, tb);
  check('过短原因被拒', !rpShort.ok, rpShort);
  const rps = await api('GET', '/api/admin/reports', null, at);
  check('管理端看到举报', rps.ok && rps.data.list.length === 1 && rps.data.list[0].status === 'open', rps.data);
  const rp2 = await api('POST', '/api/admin/reports/' + rps.data.list[0].id + '/resolve', { note: '已警告对方' }, at);
  check('举报结案', rp2.ok, rp2);

  console.log('== 4. 学校管理 ==');
  const sch = await api('POST', '/api/admin/schools', { name: '华中科技大学' }, at);
  check('添加学校', sch.ok, sch);
  const schools = await api('GET', '/api/schools', null, ta);
  check('App 学校列表含新学校', schools.data.list.some((s) => s.name === '华中科技大学'), schools.data.list.map((s) => s.name));
  const dup = await api('POST', '/api/admin/schools', { name: '华中科技大学' }, at);
  check('重复学校被拒', !dup.ok, dup);

  // 清理
  const { db, tx } = require('../src/db');
  tx(() => {
    for (const t of ['users', 'orders', 'runs', 'chats', 'chat_messages', 'notifications', 'email_codes', 'checkins', 'reviews', 'notices', 'reports', 'schools', 'books', 'book_chats', 'book_messages', 'book_reports']) {
      if (t === 'users') db.prepare(`DELETE FROM users WHERE email LIKE '%@t.com'`).run();
      else if (t === 'notices') db.prepare(`DELETE FROM notices`).run();
      else if (t === 'schools') db.prepare(`DELETE FROM schools WHERE name='华中科技大学'`).run();
      else db.prepare(`DELETE FROM ${t}`).run();
    }
  });
  db.close();
  console.log(`\n结果: ${pass} 通过, ${fail} 失败`);
  process.exit(fail ? 1 : 0);
})().catch((e) => {
  try { const { db } = require('../src/db'); db.close(); } catch (x) {}
  console.error(e); process.exit(1);
});
