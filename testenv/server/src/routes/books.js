// 书市：发布二手书 / 浏览搜索 / 详情 / 联系买家卖家 / 举报（平台不代收钱，线下当面交易）
const path = require('path');
const fs = require('fs');
const express = require('express');
const multer = require('multer');
const { db, getSettings } = require('../db');
const { requireUser } = require('../auth');
const { ok, fail, nowTs, clampInt } = require('../util');
const { userPublic } = require('../business');
const { pushToUser } = require('../ws');

const router = express.Router();
router.use(requireUser);

const BOOK_STATUS = ['on', 'off', 'sold'];
const COND_CN = { 1: '全新未使用', 2: '几乎全新', 3: '有笔记划线', 4: '使用痕迹较多' };

function notify(userId, type, title, body, data) {
  const r = db.prepare(`INSERT INTO notifications(user_id,type,title,body,data_json,created_at) VALUES(?,?,?,?,?,?)`)
    .run(userId, type, title, body, JSON.stringify(data || {}), nowTs());
  pushToUser(userId, { t: 'notif', n: { id: r.lastInsertRowid, type, title, body, data } });
}

function bookCard(b) {
  const seller = db.prepare(`SELECT id,nickname,gender,avatar,school_id FROM users WHERE id=?`).get(b.seller_id);
  const school = db.prepare(`SELECT name FROM schools WHERE id=?`).get(seller ? seller.school_id : 0);
  return {
    id: b.id, title: b.title, course: b.course, cond: b.cond, cond_cn: b.cond ? COND_CN[b.cond] || '' : '',
    price_cents: b.price_cents, note: b.note, photo: b.photo, location: b.location || '',
    status: b.status, created_at: b.created_at,
    school: school ? school.name : '',
    seller: seller ? { id: seller.id, nickname: seller.nickname, gender: seller.gender, avatar: seller.avatar } : null,
  };
}

// 图片上传人校验：仅本人
function getOwnBookOrFail(req, res) {
  const b = db.prepare(`SELECT * FROM books WHERE id=?`).get(parseInt(req.params.id, 10));
  if (!b) { fail(res, '书籍不存在', 404, 'NOT_FOUND'); return null; }
  if (b.seller_id !== req.user.id) { fail(res, '只能操作自己发布的书籍', 403, 'FORBIDDEN'); return null; }
  return b;
}

// 模糊搜索：包含 或 子序列命中（"线代"命中"线性代数"、"高数"命中"高等数学"，
// "大物"命中"大学物理"——教材名/课程名的常见缩写都能搜到）
function fuzzyHit(needle, hay) {
  hay = String(hay || '').toLowerCase();
  if (!needle) return true;
  if (hay.indexOf(needle) >= 0) return true;
  let i = 0;
  for (let k = 0; k < hay.length && i < needle.length; k++) {
    if (hay[k] === needle[i]) i++;
  }
  return i >= needle.length;
}

// ---------- 发布 ----------
router.post('/', (req, res) => {
  const me = req.user;
  const title = String(req.body.title || '').trim();
  const course = String(req.body.course || '').trim();
  const note = String(req.body.note || '').trim();
  const location = String(req.body.location || '').trim();
  if (title.length < 1 || title.length > 40) return fail(res, '书名需为 1-40 字');
  if (location.length < 2 || location.length > 30) return fail(res, '请填写交易地点（2-30 字，方便买家当面取书）');
  if (course.length > 30) return fail(res, '课程名最多 30 字');
  if (note.length > 300) return fail(res, '补充说明最多 300 字');
  const price = Math.round(parseFloat(req.body.price_cents));
  if (!Number.isFinite(price) || price < 1 || price > 99999) return fail(res, '价格需在 0.01-999.99 元之间');
  let cond = parseInt(req.body.cond, 10);
  if (cond && !(cond >= 1 && cond <= 4)) cond = null;
  if (!cond) cond = null;

  const r = db.prepare(`INSERT INTO books(seller_id,title,course,cond,price_cents,note,location,created_at) VALUES(?,?,?,?,?,?,?,?)`)
    .run(me.id, title, course || null, cond, price, note || null, location || null, new Date().toISOString());
  ok(res, { id: r.lastInsertRowid });
});

// ---------- 浏览列表（在售；仅本校，支持模糊搜索） ----------
router.get('/', (req, res) => {
  const me = req.user;
  const page = clampInt(req.query.page, 1, 1000, 1);
  const size = 20;
  const fQ = String(req.query.q || '').trim().toLowerCase().replace(/\s+/g, '');
  const sort = ['latest', 'price_asc', 'price_desc'].includes(req.query.sort) ? req.query.sort : 'latest';

  // 数据按学校隔离：只能看到本校同学的在售书
  const rows = db.prepare(`SELECT b.* FROM books b JOIN users u ON u.id=b.seller_id
      WHERE b.status='on' AND b.seller_id!=? AND u.school_id=?
        AND NOT EXISTS(SELECT 1 FROM users u2 WHERE u2.id=b.seller_id AND u2.banned=1)
      ORDER BY b.id DESC`)
    .all(me.id, me.school_id);

  let list = rows;
  if (fQ) list = list.filter((b) => fuzzyHit(fQ, b.title) || fuzzyHit(fQ, b.course) || fuzzyHit(fQ, b.note));
  if (sort === 'price_asc') list.sort((a, b) => a.price_cents - b.price_cents || b.id - a.id);
  else if (sort === 'price_desc') list.sort((a, b) => b.price_cents - a.price_cents || b.id - a.id);

  const total = list.length;
  const slice = list.slice((page - 1) * size, page * size);
  ok(res, { list: slice.map(bookCard), total, has_more: page * size < total });
});

// ---------- 我的书（全部状态，管理用） ----------
router.get('/mine', (req, res) => {
  const rows = db.prepare(`SELECT * FROM books WHERE seller_id=? ORDER BY id DESC LIMIT 100`).all(req.user.id);
  const list = rows.map((b) => {
    const card = bookCard(b);
    const unread = db.prepare(`SELECT COALESCE(SUM(unread_seller),0) n FROM book_chats WHERE book_id=? AND seller_id=?`).get(b.id, req.user.id).n;
    card.unread_chats = unread;
    return card;
  });
  ok(res, { list });
});

// ---------- 详情 ----------
router.get('/:id', (req, res) => {
  const me = req.user;
  const b = db.prepare(`SELECT * FROM books WHERE id=?`).get(parseInt(req.params.id, 10));
  if (!b) return fail(res, '书籍不存在', 404, 'NOT_FOUND');
  const isSeller = b.seller_id === me.id;
  if (!isSeller && b.status !== 'on') return fail(res, '该书籍已下架或售出', 404, 'NOT_FOUND');
  const seller = db.prepare(`SELECT * FROM users WHERE id=?`).get(b.seller_id);
  // 数据按学校隔离：只能查看本校同学的书（已有的跨校会话买家不受影响，可继续交易）
  const myThread = isSeller ? null : db.prepare(`SELECT id, unread_buyer FROM book_chats WHERE book_id=? AND buyer_id=?`).get(b.id, me.id);
  if (!isSeller && seller.school_id !== me.school_id && !myThread) {
    return fail(res, '只能查看本校同学发布的书籍', 403, 'FORBIDDEN');
  }
  const school = db.prepare(`SELECT name FROM schools WHERE id=?`).get(seller.school_id);
  ok(res, {
    ...bookCard(b),
    seller: {
      id: seller.id, nickname: seller.nickname, gender: seller.gender, avatar: seller.avatar,
      school: school ? school.name : '', created_at: seller.created_at,
      completed_count: seller.completed_count, no_show_count: seller.no_show_count, no_show_count_poster: seller.no_show_count_poster,
    },
    is_seller: isSeller,
    my_thread: myThread ? { chat_id: myThread.id, unread: myThread.unread_buyer } : null,
  });
});

// ---------- 封面图上传（可选一张 ≤200KB；上传/更换） ----------
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '..', '..', 'uploads', 'books');
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => cb(null, `${req.params.id}.jpg`),
});
const upload = multer({
  storage,
  limits: { fileSize: 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const okType = file.mimetype === 'image/jpeg' || file.mimetype === 'image/png';
    cb(okType ? null : new Error('仅支持 JPG/PNG 图片'), okType);
  },
});

router.post('/:id/photo', (req, res) => {
  const b = getOwnBookOrFail(req, res);
  if (!b) return;
  upload.single('file')(req, res, (err) => {
    if (err) return fail(res, err.message === '仅支持 JPG/PNG 图片' ? err.message : '图片上传失败，大小请勿超过限制');
    if (!req.file) return fail(res, '请选择图片');
    const s = getSettings();
    const sizeKb = fs.statSync(req.file.path).size / 1024;
    if (sizeKb > s.avatar_max_kb) {
      fs.unlinkSync(req.file.path);
      return fail(res, `图片超过 ${s.avatar_max_kb}KB 限制，请重新选择（应用会自动压缩）`);
    }
    db.prepare(`UPDATE books SET photo=1 WHERE id=?`).run(b.id);
    ok(res, { url: `/files/books/${b.id}.jpg?t=${Date.now()}` });
  });
});

// ---------- 联系卖家（买家首次点“联系”时创建会话） ----------
router.post('/:id/contact', (req, res) => {
  const me = req.user;
  const b = db.prepare(`SELECT * FROM books WHERE id=?`).get(parseInt(req.params.id, 10));
  if (!b) return fail(res, '书籍不存在', 404, 'NOT_FOUND');
  if (b.seller_id === me.id) return fail(res, '不能联系自己');
  if (b.status !== 'on') return fail(res, '该书籍不在售（可能已下架或售出）');
  const seller = db.prepare(`SELECT banned,school_id FROM users WHERE id=?`).get(b.seller_id);
  if (!seller || seller.banned) return fail(res, '卖家账号异常，暂无法联系');
  // 数据按学校隔离：只能联系本校卖家（线下当面交易，跨校见不了面）
  if (seller.school_id !== me.school_id) return fail(res, '只能联系本校同学发布的书籍');

  let chat = db.prepare(`SELECT * FROM book_chats WHERE book_id=? AND buyer_id=?`).get(b.id, me.id);
  if (!chat) {
    const r = db.prepare(`INSERT INTO book_chats(book_id,seller_id,buyer_id,last_at) VALUES(?,?,?,?)`)
      .run(b.id, b.seller_id, me.id, nowTs());
    chat = db.prepare(`SELECT * FROM book_chats WHERE id=?`).get(r.lastInsertRowid);
    db.prepare(`INSERT INTO book_messages(chat_id,sender_id,type,text,created_at) VALUES(?,0,'system',?,?)`)
      .run(chat.id, `买家 ${me.nickname} 想买《${b.title}》，请与 TA 沟通价格与交易地点（平台不代收钱，见面当面交易）`, nowTs());
    notify(b.seller_id, 'book_contact', `有人想买《${b.title}》`, `${me.nickname} 想买你发布的《${b.title}》（${(b.price_cents / 100).toFixed(2)} 元），去「书市-消息」回复 TA`,
      { book_id: b.id, chat_id: chat.id });
    pushToUser(b.seller_id, { t: 'bchat', chat_id: chat.id });
    pushToUser(me.id, { t: 'bchat', chat_id: chat.id });
  }
  ok(res, { chat_id: chat.id });
});

// ---------- 举报某本书 ----------
router.post('/:id/report', (req, res) => {
  const me = req.user;
  const b = db.prepare(`SELECT * FROM books WHERE id=?`).get(parseInt(req.params.id, 10));
  if (!b) return fail(res, '书籍不存在', 404, 'NOT_FOUND');
  if (b.seller_id === me.id) return fail(res, '不能举报自己的书籍');
  const dup = db.prepare(`SELECT id FROM book_reports WHERE book_id=? AND reporter_id=? AND status='open'`).get(b.id, me.id);
  if (dup) return fail(res, '你已举报过该书籍，等待处理');
  const reason = String(req.body.reason || '').trim();
  if (reason.length < 5 || reason.length > 200) return fail(res, '请填写举报原因（5-200 字）');
  db.prepare(`INSERT INTO book_reports(book_id,reporter_id,reason,created_at) VALUES(?,?,?,?)`)
    .run(b.id, me.id, reason, nowTs());
  ok(res, { ok: true, msg: '举报已提交，平台将审核处理' });
});

// ---------- 状态管理：sold 已售出 / on 重新上架 / off 下架 ----------
router.post('/:id/status', (req, res) => {
  const b = getOwnBookOrFail(req, res);
  if (!b) return;
  const st = req.body.status;
  if (!BOOK_STATUS.includes(st)) return fail(res, '状态不正确');
  db.prepare(`UPDATE books SET status=? WHERE id=?`).run(st, b.id);
  ok(res, { id: b.id, status: st });
});

module.exports = router;
