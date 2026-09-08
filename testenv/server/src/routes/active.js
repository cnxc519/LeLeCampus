// 进行中：已确认跑单的处理（完成 / 爽约 / 雨天终止 / 申诉 / 到达打卡）
const express = require('express');
const { db, tx, getSettings } = require('../db');
const { requireUser } = require('../auth');
const { ok, fail, nowTs, todayKey, dateKeyToEpoch, clampInt } = require('../util');
const { runCard, ensureChat } = require('../business');
const { pushToUser } = require('../ws');
const { finishOrderIfDone, closeChatIfDone } = require('../sweeps');

const router = express.Router();
router.use(requireUser);

function notify(userId, type, title, body, data) {
  const r = db.prepare(`INSERT INTO notifications(user_id,type,title,body,data_json,created_at) VALUES(?,?,?,?,?,?)`)
    .run(userId, type, title, body, JSON.stringify(data || {}), nowTs());
  pushToUser(userId, { t: 'notif', n: { id: r.lastInsertRowid, type, title, body, data } });
}

function getRunOrFail(req, res) {
  const run = db.prepare(`SELECT * FROM runs WHERE id=?`).get(parseInt(req.params.id, 10));
  if (!run) { fail(res, '跑单不存在', 404, 'NOT_FOUND'); return null; }
  const o = db.prepare(`SELECT * FROM orders WHERE id=?`).get(run.order_id);
  if (!o) { fail(res, '挂单不存在', 404, 'NOT_FOUND'); return null; }
  const isPoster = o.poster_id === req.user.id;
  const isReceiver = run.receiver_id === req.user.id;
  if (!isPoster && !isReceiver) { fail(res, '无权操作该跑单', 403, 'FORBIDDEN'); return null; }
  return { run, order: o, isPoster, isReceiver };
}

// ---------- 进行中列表（含我的待处理申请） ----------
router.get('/', (req, res) => {
  const me = req.user.id;
  const runs = db.prepare(`SELECT r.* FROM runs r JOIN orders o ON o.id=r.order_id
      WHERE r.status IN ('requested','confirmed') AND (o.poster_id=? OR r.receiver_id=?) ORDER BY r.date, r.id DESC`)
    .all(me, me);
  const list = runs.map((r) => {
    const o = db.prepare(`SELECT poster_id FROM orders WHERE id=?`).get(r.order_id);
    const card = runCard(r);
    card.role = o.poster_id === me ? 'poster' : 'receiver';
    const chat = db.prepare(`SELECT id FROM chats WHERE order_id=? AND receiver_id=?`).get(r.order_id, r.receiver_id);
    card.chat_id = chat ? chat.id : 0;
    return card;
  });
  ok(res, { list });
});

// ---------- 跑单详情 ----------
router.get('/:id', (req, res) => {
  const { run, order, isPoster } = getRunOrFail(req, res);
  if (!run) return;
  const card = runCard(run);
  const s = getSettings();
  const meetTs = dateKeyToEpoch(run.date) + card.meet_hour * 3600e3; // 集合时刻
  ok(res, {
    ...card,
    role: isPoster ? 'poster' : 'receiver',
    meet_ts: meetTs,
    claimable: nowTs() >= meetTs + 15 * 60e3 && nowTs() <= meetTs + 25 * 3600e3, // 可发起爽约时间窗
    appeal_deadline: run.noshow_at ? run.noshow_at + s.appeal_hours * 3600e3 : null,
    chat_id: (db.prepare(`SELECT id FROM chats WHERE order_id=? AND receiver_id=?`).get(order.id, run.receiver_id) || {}).id,
  });
});

// ---------- 挂单方：委托完成（费用已在见面时线下当面结算） ----------
router.post('/:id/complete', (req, res) => {
  const { run, order, isPoster } = getRunOrFail(req, res);
  if (!run) return;
  if (!isPoster) return fail(res, '只有挂单方可以确认委托完成', 403, 'FORBIDDEN');
  if (run.status !== 'confirmed') return fail(res, '当前状态不能确认完成');

  db.prepare(`UPDATE runs SET status='completed', completed_at=? WHERE id=?`).run(new Date().toISOString(), run.id);
  db.prepare(`UPDATE users SET completed_count=completed_count+1 WHERE id=?`).run(run.receiver_id);
  finishOrderIfDone(order.id);

  const chat = ensureChat(order.id, run.receiver_id);
  db.prepare(`INSERT INTO chat_messages(chat_id,sender_id,type,text,created_at) VALUES(?,0,'system',?,?)`)
    .run(chat.id, `挂单方确认委托完成，感谢双方！记得互相评价哦`, nowTs());
  db.prepare(`UPDATE chats SET unread_receiver=unread_receiver+1, last_at=? WHERE id=?`).run(nowTs(), chat.id);

  notify(run.receiver_id, 'run_completed', '委托已完成', `你完成了 ${run.date} 的代跑，辛苦了！可以给对方评价`, { run_id: run.id });
  pushToUser(run.receiver_id, { t: 'run', run_id: run.id, status: 'completed' });
  ok(res, { run_id: run.id, status: 'completed' });
});

// ---------- 雨天终止订单：一方发起，对方同意后订单终止（无线上费用）；超时默认同意 ----------
router.post('/:id/rain', (req, res) => {
  const { run, order, isPoster } = getRunOrFail(req, res);
  if (!run) return;
  if (run.status !== 'confirmed') return fail(res, '当前状态不能发起雨天终止');
  const s = getSettings();
  const agree = req.body.agree === true;

  const byMe = isPoster ? 'requested_by_poster' : 'requested_by_receiver';
  const byOther = isPoster ? 'requested_by_receiver' : 'requested_by_poster';

  if (!run.rain_state) {
    if (run.rain_at) return fail(res, '请稍后重试');
    db.prepare(`UPDATE runs SET rain_state=?, rain_at=? WHERE id=?`).run(byMe, nowTs(), run.id);
    const otherId = isPoster ? run.receiver_id : order.poster_id;
    notify(otherId, 'rain_request', '雨天终止订单请求', '对方发起了雨天终止订单，同意后订单终止（无线上费用，默认超时自动同意）', { run_id: run.id });
    pushToUser(otherId, { t: 'run', run_id: run.id, rain_state: byMe });
    return ok(res, { rain_state: byMe, msg: '已发送雨天终止请求，等待对方确认（默认 6 小时未回复自动同意）' });
  }

  if (run.rain_state === byMe) return fail(res, '对方尚未回复，请耐心等待（超时自动同意并退款）');
  if (run.rain_state !== byOther) return fail(res, '状态异常');

  if (!agree) {
    db.prepare(`UPDATE runs SET rain_state=NULL, rain_at=NULL WHERE id=?`).run(run.id);
    const otherId = isPoster ? run.receiver_id : order.poster_id;
    notify(otherId, 'rain_declined', '雨天终止请求被拒绝', '对方拒绝了雨天终止，订单按原计划进行', { run_id: run.id });
    return ok(res, { rain_state: null });
  }

  db.prepare(`UPDATE runs SET status='rain_cancelled', completed_at=? WHERE id=?`).run(new Date().toISOString(), run.id);
  finishOrderIfDone(order.id);
  notify(order.poster_id, 'rain_cancelled', '雨天订单已终止', '双方同意终止', { run_id: run.id });
  notify(run.receiver_id, 'rain_cancelled', '雨天订单已终止', '双方同意终止', { run_id: run.id });
  pushToUser(run.receiver_id, { t: 'run', run_id: run.id, status: 'rain_cancelled' });
  ok(res, { run_id: run.id, status: 'rain_cancelled' });
});

// ---------- 爽约认定：集合时间后 15 分钟可发起，对方 12 小时内未申诉即生效 ----------
router.post('/:id/noshows', (req, res) => {
  const { run, order, isPoster } = getRunOrFail(req, res);
  if (!run) return;
  if (run.status !== 'confirmed') return fail(res, '当前状态不能发起爽约认定');
  const target = req.body.target;
  const want = isPoster ? 'receiver' : 'poster';
  if (target !== want) return fail(res, '只能认定对方爽约');

  const card = runCard(run);
  const meetTs = dateKeyToEpoch(run.date) + card.meet_hour * 3600e3;
  if (nowTs() < meetTs + 15 * 60e3) return fail(res, '集合时间后 15 分钟才能发起爽约认定');
  if (nowTs() > meetTs + 25 * 3600e3) return fail(res, '认定时间已过（集合后 24 小时内可发起）');

  db.prepare(`UPDATE runs SET noshow_claimed_by=?, noshow_target=?, noshow_at=? WHERE id=?`)
    .run(req.user.id, target, nowTs(), run.id);
  const s = getSettings();
  const otherId = isPoster ? run.receiver_id : order.poster_id;
  notify(otherId, 'noshows_claimed', '对方认定你爽约', `对方认定你在 ${run.date} 的代跑中爽约。如不认可可在 ${s.appeal_hours} 小时内反驳（订单终止、不计爽约）；逾期按爽约处理并记入主页`,
    { run_id: run.id });
  pushToUser(otherId, { t: 'run', run_id: run.id, noshow_target: target });
  ok(res, { noshow_target: target, msg: `已提交认定，对方 ${s.appeal_hours} 小时内可申诉，逾期自动生效` });
});

// ---------- 被认定爽约方的反驳：立即终止、不计爽约（双方自行协商解决） ----------
router.post('/:id/appeal', (req, res) => {
  const { run, order, isPoster } = getRunOrFail(req, res);
  if (!run) return;
  if (!run.noshow_target || run.noshow_at == null) return fail(res, '没有待处理的爽约认定');
  const me = isPoster ? 'poster' : 'receiver';
  if (run.noshow_target !== me) return fail(res, '该认定不是针对你');
  const s = getSettings();
  if (nowTs() > run.noshow_at + s.appeal_hours * 3600e3) return fail(res, '反驳窗口已过，爽约认定已生效');

  db.prepare(`UPDATE runs SET status='cancelled', completed_at=? WHERE id=?`).run(new Date().toISOString(), run.id);
  finishOrderIfDone(order.id);
  notify(order.poster_id, 'noshows_cancelled', '爽约认定已被反驳', '对方反驳了爽约认定，订单已终止（不计爽约、不判定责任），如有异议请与对方协商', { run_id: run.id });
  notify(run.receiver_id, 'noshows_cancelled', '你已反驳爽约认定', '订单已终止（不计爽约、不判定责任）', { run_id: run.id });
  pushToUser(run.receiver_id, { t: 'run', run_id: run.id, status: 'cancelled' });
  ok(res, { ok: true, msg: '已反驳，订单终止，不计爽约' });
});

// ---------- 完成后互评（双方各可评价一次，展示在用户主页） ----------
router.post('/:id/review', (req, res) => {
  const { run, order, isPoster } = getRunOrFail(req, res);
  if (!run) return;
  if (run.status !== 'completed') return fail(res, '订单完成后才能评价');
  const score = parseInt(req.body.score, 10);
  if (score < 1 || score > 5) return fail(res, '请选择 1-5 星');
  const comment = String(req.body.comment || '').trim().slice(0, 200);
  const targetId = isPoster ? run.receiver_id : order.poster_id;
  if (targetId === req.user.id) return fail(res, '不能评价自己');
  const dup = db.prepare(`SELECT id FROM reviews WHERE run_id=? AND reviewer_id=?`).get(run.id, req.user.id);
  if (dup) return fail(res, '你已评价过该订单');
  db.prepare(`INSERT INTO reviews(run_id,order_id,reviewer_id,target_id,score,comment,created_at) VALUES(?,?,?,?,?,?,?)`)
    .run(run.id, order.id, req.user.id, targetId, score, comment, nowTs());
  ok(res, { ok: true });
});

// ---------- 举报（违规/纠纷提交平台审核） ----------
router.post('/:id/report', (req, res) => {
  const { run } = getRunOrFail(req, res);
  if (!run) return;
  if (!['confirmed', 'completed'].includes(run.status)) return fail(res, '当前状态不能举报');
  const reason = String(req.body.reason || '').trim();
  if (reason.length < 5 || reason.length > 200) return fail(res, '请填写举报原因（5-200 字）');
  db.prepare(`INSERT INTO reports(run_id,reporter_id,reason,created_at) VALUES(?,?,?,?)`)
    .run(run.id, req.user.id, reason, nowTs());
  ok(res, { ok: true, msg: '举报已提交，平台将审核处理' });
});

// ---------- 到达打卡（作为爽约争议时的证据） ----------
router.post('/:id/checkin', (req, res) => {
  const { run, order, isPoster } = getRunOrFail(req, res);
  if (!run) return;
  if (run.status !== 'confirmed') return fail(res, '当前状态不能打卡');
  const lat = parseFloat(req.body.lat), lon = parseFloat(req.body.lon);
  const r = db.prepare(`INSERT INTO checkins(run_id,user_id,lat,lon,created_at) VALUES(?,?,?,?,?)`)
    .run(run.id, req.user.id, Number.isFinite(lat) ? lat : null, Number.isFinite(lon) ? lon : null, nowTs());

  const chat = ensureChat(order.id, run.receiver_id);
  const name = isPoster ? '挂单方' : '接单方';
  db.prepare(`INSERT INTO chat_messages(chat_id,sender_id,type,text,created_at) VALUES(?,0,'system',?,?)`)
    .run(chat.id, `${name} 已在集合点打卡到达（时间 ${new Date(nowTs() + 8 * 3600e3).toISOString().slice(11, 16)}）`, nowTs());
  const otherId = isPoster ? run.receiver_id : order.poster_id;
  db.prepare(`UPDATE chats SET unread_${isPoster ? 'receiver' : 'poster'}=unread_${isPoster ? 'receiver' : 'poster'}+1, last_at=? WHERE id=?`).run(nowTs(), chat.id);
  notify(otherId, 'checkin', '对方已到达集合点', `${name} 已打卡到达，请注意相认`, { run_id: run.id });
  ok(res, { checkin_id: r.lastInsertRowid });
});

module.exports = router;
