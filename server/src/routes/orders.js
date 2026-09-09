// 挂单：发布 / 列表（筛选+排序）/ 详情 / 接单申请 / 取消
const express = require('express');
const { db, getSettings } = require('../db');
const { requireUser } = require('../auth');
const { ok, fail, nowTs, todayKey, dateKeyToEpoch, epochToDateKey, weekdayOfKey, chinaHour, isDateKey, clampInt } = require('../util');
const {
  normalizeSlots, remainingCount, availableDates, capacityOk, orderCard, runCard, ensureChat, bookedHoursByDate,
} = require('../business');
const { pushToUser } = require('../ws');

const router = express.Router();
router.use(requireUser);

function notify(userId, type, title, body, data) {
  const r = db.prepare(`INSERT INTO notifications(user_id,type,title,body,data_json,created_at) VALUES(?,?,?,?,?,?)`)
    .run(userId, type, title, body, JSON.stringify(data || {}), nowTs());
  pushToUser(userId, { t: 'notif', n: { id: r.lastInsertRowid, type, title, body, data } });
}

// ---------- 发布挂单 ----------
router.post('/', (req, res) => {
  const s = getSettings();
  const me = req.user;
  const { playground_id, remark, slots, run_count, gender_required } = req.body;

  const pg = db.prepare(`SELECT * FROM playgrounds WHERE id=? AND school_id=?`).get(parseInt(playground_id, 10), me.school_id);
  if (!pg) return fail(res, '请选择操场');
  if (!remark || String(remark).trim().length < 1) return fail(res, '请填写委托内容');
  if (String(remark).trim().length > 200) return fail(res, '委托内容最多 200 字');
  // 期望报酬（分）：必填，每次不少于 1.99 元；金额只作双方参考，平台不代收，线下当面结算
  const price = Math.round(parseFloat(req.body.price_cents));
  if (!Number.isFinite(price) || price < 199 || price > 99999) return fail(res, '期望报酬需在 1.99-999.99 元之间');
  const norm = normalizeSlots(slots);
  if (!norm) return fail(res, '请选择至少一个有效时间格（8 点-23 点）');
  const rc = clampInt(run_count, 1, s.run_count_max, s.run_count_default);
  const gr = ['none', 'male', 'female'].includes(gender_required) ? gender_required : 'none';

  const r = db.prepare(`INSERT INTO orders(poster_id,school_id,playground_id,remark,price_cents,gender_required,run_count,slots_json,created_at)
    VALUES(?,?,?,?,?,?,?,?,?)`)
    .run(me.id, me.school_id, pg.id, String(remark).trim(), price, gr, rc, JSON.stringify(norm), new Date().toISOString());
  ok(res, { id: r.lastInsertRowid });
});

// ---------- 我的挂单（挂单页展示，含无跑单的活跃挂单） ----------
router.get('/mine', (req, res) => {
  const orders = db.prepare(`SELECT * FROM orders WHERE poster_id=? AND status='active' ORDER BY id DESC LIMIT 50`).all(req.user.id);
  ok(res, { list: orders.map(orderCard) });
});

// ---------- 接单列表 ----------
router.get('/', (req, res) => {
  const me = req.user;
  const s = getSettings();
  const page = clampInt(req.query.page, 1, 1000, 1);
  const size = 20;
  const sortMode = ['smart', 'price_asc', 'price_desc'].includes(req.query.sort) ? req.query.sort : 'smart';

  const fPlayground = parseInt(req.query.playground_id, 10) || 0;
  const fDays = String(req.query.days || '').split(',').map((s) => s.trim()).filter((s) => s !== '').map(Number).filter((d) => d >= 0 && d <= 6);
  const fMinHour = clampInt(req.query.min_hour, 0, 23, 0);
  const fMaxHour = clampInt(req.query.max_hour, 0, 23, 23);

  const orders = db.prepare(`SELECT * FROM orders WHERE school_id=? AND status='active' AND poster_id!=?
      AND NOT EXISTS(SELECT 1 FROM users u WHERE u.id=orders.poster_id AND u.banned=1)`)
    .all(me.school_id, me.id);

  const cards = [];
  for (const o of orders) {
    if (o.gender_required !== 'none' && o.gender_required !== me.gender) continue; // 性别要求过滤
    if (fPlayground && o.playground_id !== fPlayground) continue;
    const avail = availableDates(o);
    if (avail.length === 0) continue;
    // 时间筛选：存在符合条件的可用日期
    if (fDays.length > 0 || fMinHour > 0 || fMaxHour < 23) {
      const hit = avail.some((a) =>
        (fDays.length === 0 || fDays.includes(a.weekday)) &&
        a.hours.some((h) => h >= fMinHour && h <= fMaxHour));
      if (!hit) continue;
    }
    cards.push(orderCard(o));
  }

  // 排序：
  //  smart      今明有可接时间的最前（内部按剩余格子数降序，再随机）；今明没有的靠后（同样规则）
  //  price_*    先按金额排序（同价回落智能规则的次要因子），可在线切换
  for (const c of cards) c._r = Math.random();
  const smartCmp = (a, b) => {
    const ta = a.avail_today || a.avail_tomorrow ? 0 : 1;
    const tb = b.avail_today || b.avail_tomorrow ? 0 : 1;
    if (ta !== tb) return ta - tb;
    if (b.avail_count !== a.avail_count) return b.avail_count - a.avail_count;
    return a._r - b._r;
  };
  cards.sort((a, b) => {
    if (sortMode === 'price_asc' || sortMode === 'price_desc') {
      const d = sortMode === 'price_asc' ? a.price_cents - b.price_cents : b.price_cents - a.price_cents;
      if (d !== 0) return d;
      const ta = a.avail_today || a.avail_tomorrow ? 0 : 1;
      const tb = b.avail_today || b.avail_tomorrow ? 0 : 1;
      if (ta !== tb) return ta - tb;
      if (b.avail_count !== a.avail_count) return b.avail_count - a.avail_count;
      return a._r - b._r;
    }
    return smartCmp(a, b);
  });
  for (const c of cards) delete c._r;

  const slice = cards.slice((page - 1) * size, page * size);
  ok(res, { list: slice, total: cards.length, has_more: page * size < cards.length });
});

// ---------- 挂单详情 ----------
router.get('/:id', (req, res) => {
  const me = req.user;
  const o = db.prepare(`SELECT * FROM orders WHERE id=? AND school_id=?`).get(parseInt(req.params.id, 10), me.school_id);
  if (!o) return fail(res, '挂单不存在', 404, 'NOT_FOUND');
  const poster = db.prepare(`SELECT id,nickname,gender,avatar,school_id,completed_count,no_show_count,no_show_count_poster,created_at FROM users WHERE id=?`).get(o.poster_id);
  const school = db.prepare(`SELECT name FROM schools WHERE id=?`).get(poster.school_id);
  const pg = db.prepare(`SELECT name FROM playgrounds WHERE id=?`).get(o.playground_id);
  const card = orderCard(o);
  const avail = availableDates(o);
  const myRuns = db.prepare(`SELECT id,date,status,hours_json FROM runs WHERE order_id=? AND receiver_id=?`).all(o.id, me.id);
  ok(res, {
    ...card,
    poster: { ...poster, school: school ? school.name : '' },
    playground_name: pg ? pg.name : '',
    available_dates: avail,
    my_runs: myRuns,
    is_mine: o.poster_id === me.id,
  });
});

// ---------- 接单申请（按日期 + 具体时间点申请；同一时间点最多 N 单并行） ----------
router.post('/:id/take', (req, res) => {
  const me = req.user;
  const s = getSettings();
  const o = db.prepare(`SELECT * FROM orders WHERE id=? AND school_id=?`).get(parseInt(req.params.id, 10), me.school_id);
  if (!o) return fail(res, '挂单不存在', 404, 'NOT_FOUND');
  if (o.status !== 'active') return fail(res, '该挂单已结束');
  if (o.poster_id === me.id) return fail(res, '不能接自己发布的挂单');
  if (o.gender_required !== 'none' && o.gender_required !== me.gender) return fail(res, '该挂单对性别有要求，你不能接');

  const date = String(req.body.date || '');
  if (!isDateKey(date)) return fail(res, '日期格式不正确');
  // 只能接未来日期
  if (dateKeyToEpoch(date) < dateKeyToEpoch(todayKey())) return fail(res, '不能申请过去的日期');

  // 该日期必须是当前可接日期
  const avail = availableDates(o);
  const target = avail.find((a) => a.date === date);
  if (!target) return fail(res, '该日期暂不可接（时间点可能已被接走），请刷新后重试');

  // 接单必须明确选择具体时间点（一天仅可选一个：乐跑每天只能跑一次；
  // 同日其余时间点由下方 bookedHoursByDate 整日占用规则挡掉）
  const reqHours = Array.isArray(req.body.hours) ? [...new Set(req.body.hours.map((h) => parseInt(h, 10)))] : [];
  if (reqHours.length === 0) return fail(res, '请先选择要接的具体时间点');
  if (reqHours.length > 1) return fail(res, '一天仅能选择一个时间点');
  const invalid = reqHours.filter((h) => !target.hours.includes(h));
  if (invalid.length > 0) return fail(res, '所选时间点已不可接，请刷新后重试');
  const hours = reqHours.sort((a, b) => a - b);
  if (date === todayKey()) {
    const hNow = chinaHour();
    if (hours.some((h) => h <= hNow)) return fail(res, '不能接今天已过的时间点');
  }

  // 所选每个时间点：同一时间点最多同时接 5 单
  if (!capacityOk(me.id, date, hours, s.receiver_max_concurrent)) {
    return fail(res, `你在这个时间段已同时在跑 ${s.receiver_max_concurrent} 单，不能再接`);
  }

  // 写入前最终校验：每天最多一单 —— 该日期已被任何非关闭申请占用则拒绝
  // （原 UNIQUE(order_id,date) 约束已迁移去除，改由业务层把关）
  if (bookedHoursByDate(o.id).has(date)) {
    return fail(res, '该日期已被同学接走（每天最多一单），请选择其他日期');
  }

  const r = db.prepare(`INSERT INTO runs(order_id,date,weekday,hours_json,receiver_id,status)
    VALUES(?,?,?,?,?,'requested')`)
    .run(o.id, date, target.weekday, JSON.stringify(hours), me.id);

  const hoursText = hours.map((h) => `${h}:00`).join('、');

  // 私聊会话（临时性质，订单结束后消失）
  const chat = ensureChat(o.id, me.id);
  db.prepare(`INSERT INTO chat_messages(chat_id,sender_id,type,text,created_at) VALUES(?,0,'system',?,?)`)
    .run(chat.id, `${me.nickname} 申请接 ${date} ${hoursText} 的单，等待挂单方确认`, nowTs());
  db.prepare(`UPDATE chats SET unread_poster=unread_poster+1, last_at=? WHERE id=?`).run(nowTs(), chat.id);

  // 通知挂单方：确认 / 拒绝 / 私聊
  notify(o.poster_id, 'take_request', '新的接单申请', `${me.nickname} 想接 ${date} ${hoursText} 的代跑，请同意或拒绝`,
    { run_id: r.lastInsertRowid, order_id: o.id, receiver_id: me.id, date, hours });
  pushToUser(o.poster_id, { t: 'run', run_id: r.lastInsertRowid, status: 'requested' });
  pushToUser(me.id, { t: 'chat', chat_id: chat.id });

  ok(res, { run_id: r.lastInsertRowid, chat_id: chat.id });
});

// ---------- 确认接单（直接进入进行中；费用线下见面后当面结算） ----------
router.post('/requests/:rid/confirm', (req, res) => {
  const run = db.prepare(`SELECT * FROM runs WHERE id=?`).get(parseInt(req.params.rid, 10));
  if (!run || run.status !== 'requested') return fail(res, '申请不存在或已处理');
  const o = db.prepare(`SELECT * FROM orders WHERE id=?`).get(run.order_id);
  if (o.poster_id !== req.user.id) return fail(res, '只有挂单方可以确认', 403, 'FORBIDDEN');
  if (o.status !== 'active') return fail(res, '挂单已结束');

  const receiver = db.prepare(`SELECT * FROM users WHERE id=?`).get(run.receiver_id);
  if (!receiver || receiver.banned) return fail(res, '接单方账号异常，请拒绝该申请');

  // 确认时再校验容量（防止期间爆满）
  const s = getSettings();
  const hours = JSON.parse(run.hours_json);
  if (!capacityOk(run.receiver_id, run.date, hours, s.receiver_max_concurrent)) {
    return fail(res, `对方这个时间段已在跑 ${s.receiver_max_concurrent} 单，无法继续，建议拒绝`);
  }

  db.prepare(`UPDATE runs SET status='confirmed' WHERE id=?`).run(run.id);

  const chat = ensureChat(o.id, run.receiver_id);
  db.prepare(`INSERT INTO chat_messages(chat_id,sender_id,type,text,created_at) VALUES(?,0,'system',?,?)`)
    .run(chat.id, `挂单方已确认接单，订单进入进行中，报酬 ¥${(o.price_cents / 100).toFixed(2)}/次，费用线下当面结算，请按约定时间集合`, nowTs());
  db.prepare(`UPDATE chats SET unread_receiver=unread_receiver+1, last_at=? WHERE id=?`).run(nowTs(), chat.id);

  notify(run.receiver_id, 'request_confirmed', '接单申请已被确认', `挂单方确认了你 ${run.date} 的单（报酬 ¥${(o.price_cents / 100).toFixed(2)}，线下当面结算），请按时赴约（集合时间 ${JSON.parse(run.hours_json).map((h) => `${h}:00`).join('、')}）`,
    { run_id: run.id, order_id: o.id });
  pushToUser(run.receiver_id, { t: 'run', run_id: run.id, status: 'confirmed' });

  ok(res, { run_id: run.id, status: 'confirmed' });
});

// ---------- 拒绝接单申请（须填写原因） ----------
router.post('/requests/:rid/reject', (req, res) => {
  const run = db.prepare(`SELECT * FROM runs WHERE id=?`).get(parseInt(req.params.rid, 10));
  if (!run || run.status !== 'requested') return fail(res, '申请不存在或已处理');
  const o = db.prepare(`SELECT * FROM orders WHERE id=?`).get(run.order_id);
  if (o.poster_id !== req.user.id) return fail(res, '只有挂单方可以拒绝', 403, 'FORBIDDEN');
  const reason = String(req.body.reason || '').trim();
  if (reason.length < 1 || reason.length > 100) return fail(res, '请填写拒绝原因（100 字以内）');

  db.prepare(`UPDATE runs SET status='rejected', reject_reason=? WHERE id=?`).run(reason, run.id);
  const chat = db.prepare(`SELECT id FROM chats WHERE order_id=? AND receiver_id=?`).get(o.id, run.receiver_id);
  if (chat) {
    db.prepare(`INSERT INTO chat_messages(chat_id,sender_id,type,text,created_at) VALUES(?,0,'system',?,?)`)
      .run(chat.id, `挂单方拒绝了你的申请，原因：${reason}`, nowTs());
    db.prepare(`UPDATE chats SET unread_receiver=unread_receiver+1, last_at=? WHERE id=?`).run(nowTs(), chat.id);
  }
  notify(run.receiver_id, 'request_rejected', '接单申请被拒绝', `挂单方拒绝了你的申请，原因：${reason}`, { run_id: run.id });
  pushToUser(run.receiver_id, { t: 'run', run_id: run.id, status: 'rejected' });
  ok(res, { run_id: run.id });
});

// ---------- 挂单方取消挂单（仅限还没有已确认跑单的情况） ----------
router.post('/:id/cancel', (req, res) => {
  const o = db.prepare(`SELECT * FROM orders WHERE id=?`).get(parseInt(req.params.id, 10));
  if (!o || o.poster_id !== req.user.id) return fail(res, '挂单不存在', 404, 'NOT_FOUND');
  if (o.status !== 'active') return fail(res, '该挂单已结束');
  const active = db.prepare(`SELECT COUNT(*) c FROM runs WHERE order_id=? AND status='confirmed'`).get(o.id).c;
  if (active > 0) return fail(res, '已有确认中的跑单，不能取消整个挂单');

  // 待处理的申请全部关闭并通知
  const pending = db.prepare(`SELECT * FROM runs WHERE order_id=? AND status='requested'`).all(o.id);
  db.prepare(`UPDATE runs SET status='rejected', reject_reason='挂单方已取消该挂单' WHERE order_id=? AND status='requested'`).run(o.id);
  db.prepare(`UPDATE orders SET status='cancelled' WHERE id=?`).run(o.id);
  for (const r of pending) {
    notify(r.receiver_id, 'order_cancelled', '挂单已取消', '挂单方取消了该挂单，你的申请已关闭', { order_id: o.id });
    pushToUser(r.receiver_id, { t: 'order', order_id: o.id, status: 'cancelled' });
  }
  ok(res, { id: o.id });
});

module.exports = router;
