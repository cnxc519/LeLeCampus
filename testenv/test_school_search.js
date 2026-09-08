// 书市验证：模糊搜索（子序列）+ 按学校隔离
const BASE = 'http://127.0.0.1:8898';
const { DatabaseSync } = require('node:sqlite');
async function api(method, path, token, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await res.json().catch(() => ({}));
  return { ok: !!j.ok, data: j.data, msg: j.error && j.error.msg };
}
let pass = 0, failCnt = 0;
function check(name, cond, extra) {
  if (cond) { pass++; console.log('  PASS ' + name); }
  else { failCnt++; console.log('  FAIL ' + name + (extra !== undefined ? ' | ' + JSON.stringify(extra).slice(0, 160) : '')); }
}
(async () => {
  const RUN = Date.now().toString(36);
  const db = new DatabaseSync('server/data.db');

  // 建第二所学校，注册一个他校用户（school_id=2）
  const hasS2 = db.prepare(`SELECT id FROM schools WHERE id=2`).get();
  if (!hasS2) db.prepare(`INSERT INTO schools(id,name) VALUES(2,'测试第二高校')`).run();

  const reg = async (em, nk, schoolId) => {
    const c = await api('POST', '/api/auth/send-code', null, { email: `${em}_${RUN}@t.com`, purpose: 'register' });
    return (await api('POST', '/api/auth/register', null, { email: `${em}_${RUN}@t.com`, code: c.data.dev_code, nickname: nk, school_id: schoolId, gender: 'male' })).data;
  };
  // 甲（学校1，复用现有种子学校1）出书：线性代数；确保存在
  const A = await reg('sch1', '书市甲', 1);
  const bk = await api('POST', '/api/books', A.token, { title: '线性代数（同济第七版）', course: '线性代数', cond: 2, price_cents: 1200 });
  check('甲(校1)出书', bk.ok, bk.msg);
  // 乙（学校1）与 丙（学校2）
  const B = await reg('sch1b', '书市乙', 1);
  const C = await reg('sch2c', '书市丙他校', 2);

  // --- 模糊搜索 ---
  let r = await api('GET', '/api/books?q=' + encodeURIComponent('线代'), B.token);
  check('乙搜"线代"命中线性代数', r.ok && r.data.list.some((b) => b.title.includes('线性代数')), r.data && r.data.total);
  r = await api('GET', '/api/books?q=' + encodeURIComponent('高数'), B.token);
  check('乙搜"高数"命中高等数学', r.ok && r.data.list.some((b) => b.title.includes('高等数学')), r.data && r.data.total);
  r = await api('GET', '/api/books?q=' + encodeURIComponent('线性代数'), B.token);
  check('全称搜索仍命中', r.ok && r.data.list.some((b) => b.title.includes('线性代数')));
  r = await api('GET', '/api/books?q=' + encodeURIComponent('xyz'), B.token);
  check('无关词不命中', r.ok && !r.data.list.some((b) => b.title.includes('线性代数')));

  // --- 学校隔离 ---
  r = await api('GET', '/api/books', C.token);
  const cross = r.data.list.filter((b) => b.school && b.school !== '测试第二高校');
  check('丙(校2)列表仅本校书', r.ok && cross.length === 0, r.data.list.map((b) => b.school));
  r = await api('GET', '/api/books?q=' + encodeURIComponent('线代'), C.token);
  check('丙搜"线代"看不到校1的书', r.ok && r.data.total === 0, r.data);
  r = await api('GET', '/api/books/' + bk.data.id, C.token);
  check('丙看校1书详情被拒', !r.ok, r.msg);
  r = await api('POST', `/api/books/${bk.data.id}/contact`, C.token, {});
  check('丙联系校1卖家被拒', !r.ok, r.msg);
  r = await api('GET', '/api/books/' + bk.data.id, B.token);
  check('乙(同校)看详情正常', r.ok, r.msg);

  // --- 挂单学校隔离（原本就有，回归确认）---
  const schools = (await api('GET', '/api/schools')).data;
  const pg1 = schools.list.find((s) => s.id === 1).playgrounds[0].id;
  const ord = await api('POST', '/api/orders', A.token, { playground_id: pg1, remark: '隔离测试', price_cents: 300, slots: [{ day: 1, hour: 18 }], run_count: 2, gender_required: 'none' });
  r = await api('GET', '/api/orders', C.token);
  check('丙(校2)看不到校1挂单', r.ok && !r.data.list.some((o) => o.id === ord.data.id));
  r = await api('GET', '/api/orders/' + ord.data.id, C.token);
  check('丙看校1挂单详情被拒', !r.ok, r.msg);

  console.log(`\n== 结果: ${pass} PASS, ${failCnt} FAIL ==`);
  process.exit(failCnt ? 1 : 0);
})().catch((e) => { console.error('TEST ERROR:', e.message); process.exit(1); });
