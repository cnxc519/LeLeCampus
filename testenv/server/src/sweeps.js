// 后台定时任务：自动过期/自动认定/订单收尾（每 60 秒跑一遍）
const { db, getSettings } = require('./db');
const { pushToUser } = require('./ws');
const { nowTs } = require('./util');

function notify(userId, type, title, body, data) {
  const r = db.prepare(`INSERT INTO notifications(user_id,type,title,body,data_json,created_at) VALUES(?,?,?,?,?,?)`)
    .run(userId, type, title, body, JSON.stringify(data || {}), nowTs());
  pushToUser(userId, { t: 'notif', n: { id: r.lastInsertRowid, type, title, body, data } });
}

function closeChatIfDone(chatId) {
  const chat = db.prepare(`SELECT * FROM chats WHERE id=?`).get(chatId);
  if (!chat || chat.closed) return;
  const order = db.prepare(`SELECT status FROM orders WHERE id=?`).get(chat.order_id);
  const active = db.prepare(`SELECT COUNT(*) c FROM runs WHERE order_id=? AND receiver_id=? AND status IN ('requested','confirmed')`)
    .get(chat.order_id, chat.receiver_id).c;
  if (order.status !== 'active' || active === 0) {
    db.prepare(`UPDATE chats SET closed=1 WHERE id=?`).run(chatId);
    db.prepare(`DELETE FROM chat_messages WHERE chat_id=?`).run(chatId); // 私聊为临时性质，订单结束后记录消失
  }
}

function finishOrderIfDone(orderId) {
  const order = db.prepare(`SELECT * FROM orders WHERE id=?`).get(orderId);
  if (!order || order.status !== 'active') return;
  const terminal = db.prepare(`SELECT COUNT(*) c FROM runs WHERE order_id=? AND status IN ('completed','poster_noshows','receiver_noshows')`).get(orderId).c;
  if (order.run_count - terminal <= 0) {
    db.prepare(`UPDATE orders SET status='finished' WHERE id=?`).run(orderId);
    // 挂单已结束，关闭并删除相关私聊记录
    for (const c of db.prepare(`SELECT id FROM chats WHERE order_id=?`).all(orderId)) closeChatIfDone(c.id);
    pushToUser(order.poster_id, { t: 'order', order_id: orderId, status: 'finished' });
  }
}

function sweep() {
  const s = getSettings();
  const now = nowTs();

  // 1. 接单申请超时未处理 -> 自动关闭（以通知时间为准，避免额外加时间字段）
  const expMs = s.request_expire_hours * 3600e3;
  const reqs = db.prepare(`SELECT r.id rid, r.order_id oid, r.receiver_id rid2, o.poster_id pid
      FROM runs r JOIN orders o ON o.id=r.order_id
      WHERE r.status='requested'`).all();
  for (const rq of reqs) {
    const last = db.prepare(`SELECT created_at FROM notifications WHERE user_id=? AND type='take_request' AND data_json LIKE ? ORDER BY id DESC LIMIT 1`)
      .get(rq.pid, `%"run_id":${rq.rid}%`);
    const t = last ? last.created_at : 0;
    if (t && now - t > expMs) {
      db.prepare(`UPDATE runs SET status='rejected', reject_reason='挂单方超时未处理，申请已自动关闭' WHERE id=? AND status='requested'`).run(rq.rid);
      notify(rq.rid2, 'request_rejected', '接单申请已关闭', '挂单方超时未处理，申请已自动关闭', { run_id: rq.rid });
      closeChatIfDone(db.prepare(`SELECT id FROM chats WHERE order_id=? AND receiver_id=?`).get(rq.oid, rq.rid2)?.id);
    }
  }

  // 2. 雨天终止请求对方未回复 -> 默认同意终止（下雨默认终止订单）
  const rainExp = s.rain_response_hours * 3600e3;
  for (const run of db.prepare(`SELECT * FROM runs WHERE status='confirmed' AND rain_state IS NOT NULL AND rain_at IS NOT NULL`).all()) {
    if (now - run.rain_at > rainExp) {
      db.prepare(`UPDATE runs SET status='rain_cancelled', completed_at=? WHERE id=?`).run(new Date().toISOString(), run.id);
      const order = db.prepare(`SELECT poster_id FROM orders WHERE id=?`).get(run.order_id);
      notify(order.poster_id, 'rain_cancelled', '雨天订单已终止', '对方未及时回复，按默认规则同意终止；该次次数已返还，会自动顺延到后续日期', { run_id: run.id });
      notify(run.receiver_id, 'rain_cancelled', '雨天订单已终止', '雨天终止请求已生效；该次次数已返还，会自动顺延到后续日期', { run_id: run.id });
      pushToUser(run.receiver_id, { t: 'run', run_id: run.id, status: 'rain_cancelled' });
    }
  }

  // 3. 爽约反驳窗口到期且未反驳 -> 自动认定为爽约（记次数，主页展示）
  const appealMs = s.appeal_hours * 3600e3;
  for (const run of db.prepare(`SELECT * FROM runs WHERE status='confirmed' AND noshow_at IS NOT NULL AND noshow_target IS NOT NULL`).all()) {
    if (now - run.noshow_at > appealMs) {
      if (run.noshow_target === 'poster') {
        db.prepare(`UPDATE runs SET status='poster_noshows', completed_at=? WHERE id=?`).run(new Date().toISOString(), run.id);
        db.prepare(`UPDATE users SET no_show_count_poster=no_show_count_poster+1 WHERE id=?`)
          .run(db.prepare(`SELECT poster_id FROM orders WHERE id=?`).get(run.order_id).poster_id);
      } else {
        db.prepare(`UPDATE runs SET status='receiver_noshows', completed_at=? WHERE id=?`).run(new Date().toISOString(), run.id);
        db.prepare(`UPDATE users SET no_show_count=no_show_count+1 WHERE id=?`).run(run.receiver_id);
      }
      const order = db.prepare(`SELECT poster_id FROM orders WHERE id=?`).get(run.order_id);
      const targetName = run.noshow_target === 'poster' ? '挂单方' : '接单方';
      notify(order.poster_id, 'noshows_settled', `对方爽约已认定`, `${targetName}爽约成立，已记入主页`, { run_id: run.id });
      notify(run.receiver_id, 'noshows_settled', `对方爽约已认定`, `${targetName}爽约成立，已记入主页`, { run_id: run.id });
      pushToUser(run.receiver_id, { t: 'run', run_id: run.id, status: run.noshow_target === 'poster' ? 'poster_noshows' : 'receiver_noshows' });
    }
  }

  // 4. 订单收尾：挂单次数耗尽 -> 订单结束不显示
  for (const o of db.prepare(`SELECT id FROM orders WHERE status='active'`).all()) finishOrderIfDone(o.id);
}

function initSweeps() {
  sweep();
  setInterval(sweep, 60 * 1000);
}

module.exports = { initSweeps, sweep, finishOrderIfDone, closeChatIfDone, notify };
