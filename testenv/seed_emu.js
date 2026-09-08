// 给模拟器当前登录用户(uid 63 阿丁)造一个已确认订单 + 带位置消息的会话
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync('E:/LeLeDaiPao/testenv/server/data.db');
const pg = db.prepare('SELECT id FROM playgrounds LIMIT 1').get();
const now = new Date().toISOString();
const o = db.prepare('INSERT INTO orders(poster_id,school_id,playground_id,remark,price_cents,gender_required,run_count,slots_json,status,created_at) VALUES(?,?,?,?,?,?,?,?,?,?)')
  .run(62, 1, pg.id, '模拟器验证订单', 300, 'none', 3, JSON.stringify([{ day: 1, hour: 18 }, { day: 2, hour: 19 }]), 'active', now);
const ord = o.lastInsertRowid;
const r = db.prepare('INSERT INTO runs(order_id,date,weekday,hours_json,receiver_id,status) VALUES(?,?,?,?,?,?)')
  .run(ord, '2026-09-08', 2, JSON.stringify([18, 19]), 62, 'confirmed');
const c = db.prepare('INSERT INTO chats(order_id,receiver_id,last_at) VALUES(?,?,?)').run(ord, 62, Date.now());
const chat = c.lastInsertRowid;
const ins = db.prepare('INSERT INTO chat_messages(chat_id,sender_id,type,text,lat,lon,created_at) VALUES(?,?,?,?,?,?,?)');
ins.run(chat, 0, 'system', '挂单方已确认接单，请按约定时间集合', null, null, Date.now() - 600000);
ins.run(chat, 62, 'location', '教室', 30.5, 114.35, Date.now() - 300000);
ins.run(chat, 62, 'location', '我的位置', 30.52, 114.37, Date.now() - 200000);
ins.run(chat, 62, 'text', '你好吗', null, null, Date.now() - 100000);
console.log('order=' + ord + ' run=' + r.lastInsertRowid + ' chat=' + chat);
