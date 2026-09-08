// 私聊：挂单方 <-> 接单方（临时性质，订单结束后记录消失；支持文字与位置，不支持图片）
const express = require('express');
const { db } = require('../db');
const { requireUser } = require('../auth');
const { ok, fail, nowTs, clampInt } = require('../util');
const { pushToUser } = require('../ws');

const router = express.Router();
router.use(requireUser);

// 校验我是会话参与者，返回 chat + 对方
function getChatOrFail(req, res) {
  const chat = db.prepare(`SELECT * FROM chats WHERE id=?`).get(parseInt(req.params.id, 10));
  if (!chat) { fail(res, '会话不存在', 404, 'NOT_FOUND'); return null; }
  const order = db.prepare(`SELECT poster_id FROM orders WHERE id=?`).get(chat.order_id);
  if (!order) { fail(res, '订单不存在', 404, 'NOT_FOUND'); return null; }
  const me = req.user.id;
  if (order.poster_id !== me && chat.receiver_id !== me) { fail(res, '无权访问该会话', 403, 'FORBIDDEN'); return null; }
  const other = db.prepare(`SELECT id,nickname,avatar,gender FROM users WHERE id=?`).get(order.poster_id === me ? chat.receiver_id : order.poster_id);
  return { chat, order, other, me };
}

// 会话列表
router.get('/', (req, res) => {
  const me = req.user.id;
  const rows = db.prepare(`SELECT c.*, o.poster_id, o.remark, o.playground_id FROM chats c JOIN orders o ON o.id=c.order_id
      WHERE c.closed=0 AND (o.poster_id=? OR c.receiver_id=?) ORDER BY c.last_at DESC`)
    .all(me, me);
  const list = rows.map((c) => {
    const other = db.prepare(`SELECT id,nickname,avatar,gender FROM users WHERE id=?`)
      .get(c.poster_id === me ? c.receiver_id : c.poster_id);
    const pg = db.prepare(`SELECT name FROM playgrounds WHERE id=?`).get(c.playground_id);
    const last = db.prepare(`SELECT type,text,created_at FROM chat_messages WHERE chat_id=? ORDER BY id DESC LIMIT 1`).get(c.id);
    const pending = db.prepare(`SELECT id FROM runs WHERE order_id=? AND receiver_id=? AND status='requested'`).get(c.order_id, c.receiver_id);
    return {
      id: c.id, order_id: c.order_id, remark: c.remark,
      playground: pg ? pg.name : '',
      other,
      unread: c.poster_id === me ? c.unread_poster : c.unread_receiver,
      has_pending_request: !!pending,
      last_message: last ? { type: last.type, text: last.text, created_at: last.created_at } : null,
    };
  });
  ok(res, { list });
});

// 消息记录（分页向前翻）
router.get('/:id/messages', (req, res) => {
  const g = getChatOrFail(req, res);
  if (!g) return;
  if (g.chat.closed) return ok(res, { closed: true, list: [] });
  const before = clampInt(req.query.before, 0, Number.MAX_SAFE_INTEGER, Number.MAX_SAFE_INTEGER);
  const rows = before > 0
    ? db.prepare(`SELECT * FROM chat_messages WHERE chat_id=? AND id<? ORDER BY id DESC LIMIT 100`).all(g.chat.id, before)
    : db.prepare(`SELECT * FROM chat_messages WHERE chat_id=? ORDER BY id DESC LIMIT 100`).all(g.chat.id);
  ok(res, { closed: false, list: rows.reverse() });
});

// 发送消息：text 文字 / location 位置（坐标 + 文字描述）
router.post('/:id/messages', (req, res) => {
  const g = getChatOrFail(req, res);
  if (!g) return;
  if (g.chat.closed) return fail(res, '该订单已结束，会话已关闭');
  const type = req.body.type === 'location' ? 'location' : 'text';
  let text = String(req.body.text || '').trim();
  if (type === 'text') {
    if (text.length < 1) return fail(res, '消息不能为空');
    if (text.length > 1000) return fail(res, '消息最长 1000 字');
  } else {
    if (text.length > 200) return fail(res, '位置描述最长 200 字');
  }
  const lat = parseFloat(req.body.lat), lon = parseFloat(req.body.lon);
  const r = db.prepare(`INSERT INTO chat_messages(chat_id,sender_id,type,text,lat,lon,created_at) VALUES(?,?,?,?,?,?,?)`)
    .run(g.chat.id, req.user.id, type, text, Number.isFinite(lat) ? lat : null, Number.isFinite(lon) ? lon : null, nowTs());
  const msg = db.prepare(`SELECT * FROM chat_messages WHERE id=?`).get(r.lastInsertRowid);
  db.prepare(`UPDATE chats SET last_at=?, unread_${g.chat.poster_id === req.user.id ? 'receiver' : 'poster'}=unread_${g.chat.poster_id === req.user.id ? 'receiver' : 'poster'}+1 WHERE id=?`)
    .run(nowTs(), g.chat.id);
  pushToUser(g.other.id, { t: 'chat', chat_id: g.chat.id, m: msg });
  ok(res, { m: msg });
});

// 标记已读
router.post('/:id/read', (req, res) => {
  const g = getChatOrFail(req, res);
  if (!g) return;
  if (g.chat.poster_id === req.user.id) db.prepare(`UPDATE chats SET unread_poster=0 WHERE id=?`).run(g.chat.id);
  else db.prepare(`UPDATE chats SET unread_receiver=0 WHERE id=?`).run(g.chat.id);
  ok(res, { ok: true });
});

// 会话中当前待处理的接单申请（挂单方按钮卡片用）
router.get('/:id/request', (req, res) => {
  const g = getChatOrFail(req, res);
  if (!g) return;
  const run = db.prepare(`SELECT * FROM runs WHERE order_id=? AND receiver_id=? AND status='requested' ORDER BY id DESC LIMIT 1`)
    .get(g.chat.order_id, g.chat.receiver_id);
  if (!run) return ok(res, { run: null });
  const order = db.prepare(`SELECT remark,playground_id,gender_required,price_cents FROM orders WHERE id=?`).get(g.chat.order_id);
  const pg = db.prepare(`SELECT name FROM playgrounds WHERE id=?`).get(order.playground_id);
  ok(res, {
    run: { id: run.id, date: run.date, hours: JSON.parse(run.hours_json), status: run.status, reject_reason: run.reject_reason },
    order: { remark: order.remark, playground: pg ? pg.name : '', gender_required: order.gender_required, price_cents: order.price_cents },
  });
});

module.exports = router;
