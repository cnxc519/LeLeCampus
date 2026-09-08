// 共享业务逻辑：周时间表 -> 可用日期、容量校验、跑单/订单组装
const { db, getSettings } = require('./db');
const { todayKey, dateKeyToEpoch, epochToDateKey, weekdayOfKey, chinaHour, nowTs } = require('./util');

const TERMINAL = ['completed', 'poster_noshows', 'receiver_noshows']; // 消耗挂单次数的终态
const ACTIVE_ST = ['requested', 'confirmed']; // 占用日期的状态

// 校验并规范化时间表：[{day:0..6, hour:8..23}] -> 排序去重后的数组
function normalizeSlots(slots) {
  if (!Array.isArray(slots) || slots.length === 0) return null;
  const set = new Set();
  for (const s of slots) {
    const day = parseInt(s.day, 10), hour = parseInt(s.hour, 10);
    if (Number.isNaN(day) || day < 0 || day > 6) return null;
    if (Number.isNaN(hour) || hour < 8 || hour > 23) return null;
    set.add(`${day}:${hour}`);
  }
  const out = [];
  for (const k of set) {
    const [d, h] = k.split(':').map(Number);
    out.push({ day: d, hour: h });
  }
  out.sort((a, b) => a.day - b.day || a.hour - b.hour);
  return out;
}

// 挂单剩余次数 = run_count - 已占用的单数
// 占用 = 非关闭态的跑单：待确认申请/进行中立即占用（接了就减，防止"接了今天的但挂着的次数没减"）；
// 被拒绝（rejected）、雨天终止、和解终止的自动返还，返还的次数由顺延机制补到后续日期
function remainingCount(orderId) {
  const order = db.prepare(`SELECT run_count FROM orders WHERE id=?`).get(orderId);
  const used = db.prepare(`SELECT COUNT(*) c FROM runs WHERE order_id=? AND status NOT IN ('rejected','rain_cancelled','cancelled')`).get(orderId).c;
  return order.run_count - used;
}

// 该挂单已被占用（有非 rejected 跑单）的日期集合 —— 每天最多一单：
// 某天任何一个时间点被接，当天全部时间点都不可再接；没人接则自动顺延后续日期
function bookedHoursByDate(orderId) {
  const rows = db.prepare(`SELECT date, hours_json FROM runs WHERE order_id=? AND status!='rejected'`).all(orderId);
  const m = new Map();
  for (const r of rows) {
    if (!m.has(r.date)) m.set(r.date, new Set());
    for (const h of JSON.parse(r.hours_json)) m.get(r.date).add(h);
  }
  return m;
}

// 该挂单当前可接的日期列表：[{date, weekday, hours}]
// hours 为该日期仍可接的时间点（= 挂单人在该星期勾选的全部时间点）；
// 已被接的日期整日消失，没被接的自动顺延，直到列满剩余次数个日期
function availableDates(order) {
  const remaining = remainingCount(order.id);
  if (remaining <= 0) return [];
  const byDay = new Map();
  for (const s of JSON.parse(order.slots_json)) {
    if (!byDay.has(s.day)) byDay.set(s.day, []);
    byDay.get(s.day).push(s.hour);
  }
  for (const v of byDay.values()) v.sort((a, b) => a - b);
  const booked = bookedHoursByDate(order.id);
  const out = [];
  const start = dateKeyToEpoch(todayKey());
  const hNow = chinaHour();
  // 窗口按剩余次数自适应放大：保证"某天没被接就自动顺移到后续日期，次数用尽才结束"
  const windowDays = Math.max(90, remaining * 10 + 14);
  for (let i = 0; i < windowDays && out.length < remaining; i++) {
    const key = epochToDateKey(start + i * 86400000);
    const wd = weekdayOfKey(key);
    let hours = byDay.get(wd);
    if (!hours) continue;
    if (booked.has(key)) continue; // 当天已被接（整日占用）
    if (i === 0) hours = hours.filter((h) => h > hNow); // 今天只留还没到的时间
    if (hours.length === 0) continue;
    out.push({ date: key, weekday: wd, hours });
  }
  return out;
}

// 接单方同一时间点（同日期同小时）并发上限校验
function capacityOk(receiverId, date, hours, maxConcurrent) {
  const rows = db.prepare(`SELECT hours_json FROM runs WHERE receiver_id=? AND date=? AND status IN ('requested','confirmed')`)
    .all(receiverId, date);
  let conflict = 0;
  for (const r of rows) {
    const theirs = JSON.parse(r.hours_json);
    if (hours.some((h) => theirs.includes(h))) conflict++;
  }
  return conflict < maxConcurrent;
}

// 订单列表项
function orderCard(o) {
  const poster = db.prepare(`SELECT id,nickname,gender,avatar,school_id FROM users WHERE id=?`).get(o.poster_id);
  const pg = db.prepare(`SELECT id,name FROM playgrounds WHERE id=?`).get(o.playground_id);
  const slots = JSON.parse(o.slots_json);
  const avail = availableDates(o);
  const slotCount = avail.reduce((n, a) => n + a.hours.length, 0);
  const today = todayKey();
  const tomorrow = epochToDateKey(dateKeyToEpoch(today) + 86400000);
  return {
    id: o.id, remark: o.remark, gender_required: o.gender_required,
    price_cents: o.price_cents, // 期望报酬（分/次），线下当面结算
    run_count: o.run_count, remaining: remainingCount(o.id),
    slots, avail_count: slotCount,
    avail_today: avail.some((a) => a.date === today),
    avail_tomorrow: avail.some((a) => a.date === tomorrow),
    created_at: o.created_at,
    playground: pg || { id: 0, name: '未知操场' },
    poster: poster ? { id: poster.id, nickname: poster.nickname, gender: poster.gender, avatar: poster.avatar } : null,
  };
}

// 跑单详情组装
function runCard(run) {
  const order = db.prepare(`SELECT * FROM orders WHERE id=?`).get(run.order_id);
  const poster = db.prepare(`SELECT id,nickname,gender,avatar FROM users WHERE id=?`).get(order.poster_id);
  const receiver = db.prepare(`SELECT id,nickname,gender,avatar FROM users WHERE id=?`).get(run.receiver_id);
  const pg = db.prepare(`SELECT name FROM playgrounds WHERE id=?`).get(order.playground_id);
  const hours = JSON.parse(run.hours_json);
  return {
    id: run.id, date: run.date, weekday: run.weekday, hours,
    status: run.status, rain_state: run.rain_state,
    noshow_target: run.noshow_target, noshow_claimed_by: run.noshow_claimed_by,
    reject_reason: run.reject_reason, completed_at: run.completed_at,
    remark: order.remark, playground: pg ? pg.name : '',
    order_id: order.id, gender_required: order.gender_required,
    price_cents: order.price_cents, // 本次报酬（分），线下当面结算
    poster, receiver,
    meet_hour: Math.min(...hours),
    // 集合时间提示：9 点 = 8:55-9:00 集合，超过 9 点视为爽约
    meet_note: `集合时间 ${String(Math.min(...hours) - 1).padStart(2, '0')}:55-${String(Math.min(...hours)).padStart(2, '0')}:00，超过 ${Math.min(...hours)}:00 视为爽约`,
    checkins: db.prepare(`SELECT user_id, lat, lon, created_at FROM checkins WHERE run_id=? ORDER BY id`).all(run.id),
  };
}

// 获取或创建私聊会话（挂单方 <-> 接单方，一单一聊）
function ensureChat(orderId, receiverId) {
  let chat = db.prepare(`SELECT * FROM chats WHERE order_id=? AND receiver_id=?`).get(orderId, receiverId);
  if (!chat) {
    const r = db.prepare(`INSERT INTO chats(order_id, receiver_id, last_at) VALUES(?,?,?)`).run(orderId, receiverId, nowTs());
    chat = db.prepare(`SELECT * FROM chats WHERE id=?`).get(r.lastInsertRowid);
  } else if (chat.closed) {
    db.prepare(`UPDATE chats SET closed=0 WHERE id=?`).run(chat.id);
    chat = db.prepare(`SELECT * FROM chats WHERE id=?`).get(chat.id);
  }
  return chat;
}

function userPublic(u) {
  const school = db.prepare(`SELECT name FROM schools WHERE id=?`).get(u.school_id);
  return {
    id: u.id, nickname: u.nickname, gender: u.gender, avatar: u.avatar,
    school: school ? school.name : '', created_at: u.created_at,
    completed_count: u.completed_count, no_show_count: u.no_show_count, no_show_count_poster: u.no_show_count_poster,
  };
}

module.exports = { normalizeSlots, remainingCount, bookedHoursByDate, availableDates, capacityOk, orderCard, runCard, ensureChat, userPublic, TERMINAL, ACTIVE_ST };
