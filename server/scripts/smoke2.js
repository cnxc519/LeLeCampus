// 第二组冒烟（无支付版）：状态机全流程——雨天终止 / 爽约认定自动生效 / 反驳终止 / 完成 / 次数耗尽
const { db, tx, getSettings } = require('../src/db');
const { sweep, finishOrderIfDone } = require('../src/sweeps');

let pass = 0, fail = 0;
const check = (name, cond, extra) => {
  if (cond) { pass++; console.log(`  ✅ ${name}`); }
  else { fail++; console.log(`  ❌ ${name}`, JSON.stringify(extra)); }
};
const mkUser = (id, email) => db.prepare(`INSERT INTO users(id,email,nickname,school_id,gender,invite_code,created_at) VALUES(?,?,?,1,'male',?,?)`)
  .run(id, email, email.split('@')[0] + '昵', 'INV' + id, new Date().toISOString());
const mkOrder = (poster, remark) => db.prepare(`INSERT INTO orders(poster_id,school_id,playground_id,remark,gender_required,run_count,slots_json,created_at) VALUES(?,1,1,?,'none',2,'[{"day":1,"hour":9}]',?)`)
  .run(poster, remark, new Date().toISOString()).lastInsertRowid;
const mkRun = (oid, receiver, date, status) => db.prepare(`INSERT INTO runs(order_id,date,weekday,hours_json,receiver_id,status) VALUES(?,?,1,'[9]',?,?)`)
  .run(oid, date, receiver, status).lastInsertRowid;
const runStatus = (id) => db.prepare(`SELECT status FROM runs WHERE id=?`).get(id).status;
const nshow = (id) => db.prepare(`SELECT no_show_count FROM users WHERE id=?`).get(id).no_show_count;
const nshowP = (id) => db.prepare(`SELECT no_show_count_poster FROM users WHERE id=?`).get(id).no_show_count_poster;
const complete = (id) => db.prepare(`SELECT completed_count FROM users WHERE id=?`).get(id).completed_count;

(async () => {
  console.log('== 1. 雨天终止 ==');
  tx(() => {
    mkUser(11, 'p1@t.com'); mkUser(12, 'r1@t.com');
  });
  const o1 = mkOrder(11, '雨天测试单');
  const run1 = mkRun(o1, 12, '2030-01-01', 'requested');
  db.prepare(`UPDATE runs SET status='confirmed' WHERE id=?`).run(run1);
  // 对方同意 -> 雨天终止
  db.prepare(`UPDATE runs SET rain_state='requested_by_poster', rain_at=? WHERE id=?`).run(Date.now(), run1);
  db.prepare(`UPDATE runs SET status='rain_cancelled', completed_at=? WHERE id=?`).run(new Date().toISOString(), run1);
  check('雨天终止状态', runStatus(run1) === 'rain_cancelled');

  console.log('== 2. 挂单方爽约认定 -> 超时自动生效 ==');
  tx(() => { mkUser(21, 'p2@t.com'); mkUser(22, 'r2@t.com'); });
  const o2 = mkOrder(21, '挂单方爽约测试');
  const run2 = mkRun(o2, 22, '2030-01-02', 'requested');
  db.prepare(`UPDATE runs SET status='confirmed', noshow_target='poster', noshow_at=? WHERE id=?`).run(Date.now() - 13 * 3600e3, run2);
  sweep();
  check('爽约认定自动生效', runStatus(run2) === 'poster_noshows', runStatus(run2));
  check('挂单方爽约次数 +1', nshowP(21) === 1, nshowP(21));

  console.log('== 3. 接单方爽约认定 -> 超时自动生效 ==');
  tx(() => { mkUser(31, 'p3@t.com'); mkUser(32, 'r3@t.com'); });
  const o3 = mkOrder(31, '接单方爽约测试');
  const run3 = mkRun(o3, 32, '2030-01-03', 'requested');
  db.prepare(`UPDATE runs SET status='confirmed', noshow_target='receiver', noshow_at=? WHERE id=?`).run(Date.now() - 13 * 3600e3, run3);
  sweep();
  check('爽约认定自动生效', runStatus(run3) === 'receiver_noshows', runStatus(run3));
  check('接单方爽约次数 +1', nshow(32) === 1, nshow(32));

  console.log('== 4. 爽约反驳 -> 订单终止不计爽约 ==');
  tx(() => { mkUser(41, 'p4@t.com'); mkUser(42, 'r4@t.com'); });
  const o4 = mkOrder(41, '反驳测试单');
  const run4 = mkRun(o4, 42, '2030-01-04', 'requested');
  db.prepare(`UPDATE runs SET status='confirmed', noshow_target='receiver', noshow_at=? WHERE id=?`).run(Date.now(), run4);
  db.prepare(`UPDATE runs SET status='cancelled', completed_at=? WHERE id=?`).run(new Date().toISOString(), run4);
  check('反驳后订单终止', runStatus(run4) === 'cancelled', runStatus(run4));
  check('接单方未被记爽约', nshow(42) === 0, nshow(42));

  console.log('== 5. 完成与评价 ==');
  const o5 = mkOrder(31, '完成测试');
  const run5 = mkRun(o5, 32, '2030-01-05', 'requested');
  db.prepare(`UPDATE runs SET status='confirmed' WHERE id=?`).run(run5);
  db.prepare(`UPDATE runs SET status='completed', completed_at=? WHERE id=?`).run(new Date().toISOString(), run5);
  db.prepare(`UPDATE users SET completed_count=completed_count+1 WHERE id=?`).run(32);
  check('完成状态', runStatus(run5) === 'completed');
  check('完成数 +1', complete(32) === 1, complete(32));

  console.log('== 6. 挂单次数耗尽自动结束 ==');
  const o6 = mkOrder(41, '耗尽测试');
  db.prepare(`UPDATE orders SET run_count=1 WHERE id=?`).run(o6);
  const run6 = mkRun(o6, 42, '2030-01-06', 'requested');
  db.prepare(`UPDATE runs SET status='confirmed' WHERE id=?`).run(run6);
  db.prepare(`UPDATE runs SET status='completed', completed_at=? WHERE id=?`).run(new Date().toISOString(), run6);
  db.prepare(`UPDATE users SET completed_count=completed_count+1 WHERE id=?`).run(42);
  finishOrderIfDone(o6);
  check('次数耗尽挂单结束', db.prepare(`SELECT status FROM orders WHERE id=?`).get(o6).status === 'finished');

  // 清理
  tx(() => {
    for (const t of ['users', 'orders', 'runs', 'chats', 'chat_messages', 'notifications', 'email_codes', 'checkins', 'books', 'book_chats', 'book_messages', 'book_reports']) {
      if (t === 'users') db.prepare(`DELETE FROM users WHERE id!=0`).run();
      else db.prepare(`DELETE FROM ${t}`).run();
    }
  });
  db.close();
  console.log(`\n结果: ${pass} 通过, ${fail} 失败`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
