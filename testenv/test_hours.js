// 按天接单语义冒烟：一天一单；某天任一时间点被接 → 该日整日消失；没人接自动顺延
const BASE = 'http://127.0.0.1:8898';
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
  const schools = (await api('GET', '/api/schools')).data;
  const schoolId = schools.list[0].id, pgId = schools.list[0].playgrounds[0].id;
  const mk = async (em, nk, g) => {
    const c = await api('POST', '/api/auth/send-code', null, { email: `${em}_${RUN}@t.com`, purpose: 'register' });
    return (await api('POST', '/api/auth/register', null, { email: `${em}_${RUN}@t.com`, code: c.data.dev_code, nickname: nk, school_id: schoolId, gender: g })).data;
  };
  const A = await mk('d1', '按天甲', 'male');
  const B = await mk('d2', '按天乙', 'female');
  const C = await mk('d3', '按天丙', 'male');

  const slots = [];
  for (let d = 0; d < 7; d++) for (const h of [18, 19, 20]) slots.push({ day: d, hour: h });
  const ord = (await api('POST', '/api/orders', A.token, { playground_id: pgId, remark: '按天冒烟', price_cents: 300, slots, run_count: 3, gender_required: 'none' })).data;

  const det0 = (await api('GET', '/api/orders/' + ord.id, B.token)).data;
  const day = det0.available_dates.find((x) => x.date !== det0.available_dates[0].date) || det0.available_dates[0];
  const allH = day.hours.slice();
  check('可接日期带全部时间点', allH.length === 3, allH);

  let r = await api('POST', `/api/orders/${ord.id}/take`, B.token, { date: day.date });
  check('不带 hours 被拒', !r.ok, r.msg);
  r = await api('POST', `/api/orders/${ord.id}/take`, B.token, { date: day.date, hours: [allH[0], 999] });
  check('含非法时间点被拒', !r.ok, r.msg);

  // B 一次勾选当天两个时间点（一天一单、多时间点）
  r = await api('POST', `/api/orders/${ord.id}/take`, B.token, { date: day.date, hours: [allH[0], allH[1]] });
  check('B 接该日 2 个时间点（一单）', r.ok, r.msg);

  let det1 = (await api('GET', '/api/orders/' + ord.id, C.token)).data;
  check('该日整日消失（每天一单）', !det1.available_dates.some((x) => x.date === day.date));

  r = await api('POST', `/api/orders/${ord.id}/take`, C.token, { date: day.date, hours: [allH[2]] });
  check('C 再接该日剩余时间点被拒', !r.ok, r.msg);

  // 顺延：下一个可接日期应含该星期剩下的全部时间点
  det1 = (await api('GET', '/api/orders/' + ord.id, C.token)).data;
  const nextDay = det1.available_dates[0];
  check('顺延到后续日期且时间点完整', nextDay && nextDay.hours.join() === allH.join(), nextDay && nextDay.hours);

  // C 接下一个日期的一个时间点
  r = await api('POST', `/api/orders/${ord.id}/take`, C.token, { date: nextDay.date, hours: [nextDay.hours[0]] });
  check('C 接顺延日期的一个时间点', r.ok, r.msg);

  const detB = (await api('GET', '/api/orders/' + ord.id, B.token)).data;
  check('B 的 my_runs 含所选时间', detB.my_runs.length === 1 && JSON.parse(detB.my_runs[0].hours_json).join() === [allH[0], allH[1]].join(), detB.my_runs);
  det1 = (await api('GET', '/api/orders/' + ord.id, C.token)).data;
  check('C 的 my_runs 只在顺延日', det1.my_runs.length === 1 && det1.my_runs[0].date === nextDay.date, det1.my_runs);

  console.log(`\n== 结果: ${pass} PASS, ${failCnt} FAIL ==`);
  process.exit(failCnt ? 1 : 0);
})().catch((e) => { console.error('SMOKE ERROR:', e.message); process.exit(1); });
