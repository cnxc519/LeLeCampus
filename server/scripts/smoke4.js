// 第四组冒烟（无支付版）：期望报酬边界与金额排序 / 书市全流程（发布-搜索-联系-私聊-已读-状态-举报）+ 管理端书市管理
const BASE = 'http://127.0.0.1:8899';
const TS = Date.now();
let pass = 0, fail = 0;
const check = (name, cond, extra) => { if (cond) { pass++; console.log(`  ✅ ${name}`); } else { fail++; console.log(`  ❌ ${name}`, JSON.stringify(extra)); } };
async function api(method, path, body, token) {
  const r = await fetch(BASE + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
  const j = await r.json().catch(() => ({}));
  return { ...j, _code: r.status };
}
async function codeOf(email, purpose) {
  const r = await api('POST', '/api/auth/send-code', { email, purpose });
  return r.data.dev_code;
}
async function regUser(email, nick, gender) {
  const c = await codeOf(email, 'register');
  const r = await api('POST', '/api/auth/register', { email, code: c, nickname: nick, school_id: 1, gender });
  return r.data.token;
}
const SLOT = () => [{ day: Math.floor(Math.random() * 7), hour: 9 + Math.floor(Math.random() * 5) }];

(async () => {
  console.log('== 1. 代跑期望报酬边界 ==');
  const pa = await regUser('p1_' + TS + '@t.com', '价格测试甲', 'female');
  const mkOrder = async (token, price_cents) => {
    const r = await api('POST', '/api/orders', { playground_id: 1, remark: '报酬边界测试', price_cents, slots: SLOT(), run_count: 1, gender_required: 'none' }, token);
    return r.ok ? r.data.id : r;
  };
  check('低于 1.99 被拒', (await mkOrder(pa, 198)).ok === false);
  check('刚好 1.99 通过', typeof (await mkOrder(pa, 199)) === 'number');
  check('不填金额被拒（必填）', (await mkOrder(pa, undefined)).ok === false);
  check('非法金额被拒', (await mkOrder(pa, 'abc')).ok === false);
  check('999.99 通过', typeof (await mkOrder(pa, 99999)) === 'number');
  check('超过 999.99 被拒', (await mkOrder(pa, 100000)).ok === false);

  console.log('== 2. 接单列表金额排序 ==');
  const pb = await regUser('p2_' + TS + '@t.com', '价格测试乙', 'male');
  const pc = await regUser('p3_' + TS + '@t.com', '价格测试丙', 'female');
  const ids = {};
  ids.low = await mkOrder(pa, 300);
  ids.mid = await mkOrder(pb, 500);
  ids.high = await mkOrder(pc, 800);
  const pv = await regUser('v1_' + TS + '@t.com', '排序观察者', 'male');
  const prices = async (sort) => {
    const r = await api('GET', '/api/orders?sort=' + sort, null, pv);
    return r.data.list.filter((o) => [ids.low, ids.mid, ids.high].includes(o.id)).map((o) => o.price_cents);
  };
  const desc = await prices('price_desc');
  check('金额高→低', JSON.stringify(desc) === JSON.stringify([800, 500, 300]), desc);
  const asc = await prices('price_asc');
  check('金额低→高', JSON.stringify(asc) === JSON.stringify([300, 500, 800]), asc);
  check('详情含期望报酬', (await api('GET', '/api/orders/' + ids.mid, null, pv)).data.price_cents === 500);
  // 清理上面 5 个测试挂单，避免影响后续章节的列表断言
  const { db, tx } = require('../src/db');
  tx(() => { db.prepare(`DELETE FROM orders WHERE id IN (?,?,?)`).run(ids.low, ids.mid, ids.high); });

  console.log('== 3. 书市发布与价格边界 ==');
  const seller = await regUser('s1_' + TS + '@t.com', '卖书人', 'female');
  const buyer = await regUser('b1_' + TS + '@t.com', '买书人', 'male');
  const postBook = async (token, body) => (await api('POST', '/api/books', body, token));
  check('书价 0 被拒', !(await postBook(seller, { title: '零元书', price_cents: 0, cond: 1 })).ok);
  check('书价超过 999.99 被拒', !(await postBook(seller, { title: '天价书', price_cents: 100000 })).ok);
  check('书名超长被拒', !(await postBook(seller, { title: '超'.repeat(41), price_cents: 100 })).ok);
  const bk1 = await postBook(seller, { title: '高等数学（第七版）', course: '高等数学', cond: 2, price_cents: 2500, note: '有少量笔记，无缺页' });
  const bk2 = await postBook(seller, { title: '大学英语综合教程', cond: 4, price_cents: 800, note: '' });
  check('发布成功', bk1.ok && bk2.ok, bk1);
  const id1 = bk1.data.id, id2 = bk2.data.id;
  check('1 分钱书价可通过', (await postBook(seller, { title: '一分钱书', price_cents: 1 })).ok);

  console.log('== 4. 浏览与详情 ==');
  const browse = async (token, q, sort) => {
    const r = await api('GET', '/api/books?q=' + encodeURIComponent(q || '') + (sort ? '&sort=' + sort : ''), null, token);
    return r.data.list;
  };
  const bl = await browse(buyer, '高等');
  check('买家搜到书（含成色中文）', bl.some((b) => b.id === id1 && b.cond_cn === '几乎全新' && b.price_cents === 2500), bl);
  const mine1 = await browse(seller, '', '');
  check('浏览列表不含自己的书', !mine1.some((b) => b.id === id1 || b.id === id2), mine1);
  const myBooks = await api('GET', '/api/books/mine', null, seller);
  check('我的书含 3 本（含 1 分钱边界书）且无未读', myBooks.data.list.length === 3 && myBooks.data.list.every((b) => b.unread_chats === 0), myBooks.data);
  const det = await api('GET', '/api/books/' + id1, null, buyer);
  check('详情含卖家与学校信息', det.data.is_seller === false && det.data.seller.nickname === '卖书人' && !!det.data.seller.school, det.data);
  check('详情初始无会话', det.data.my_thread === null, det.data.my_thread);
  // 封面图上传（1x1 PNG）
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
  const fd = new FormData();
  fd.append('file', new Blob([png], { type: 'image/png' }), 'cover.png');
  const up = await fetch(BASE + '/api/books/' + id2 + '/photo', { method: 'POST', headers: { Authorization: 'Bearer ' + seller }, body: fd });
  const upj = await up.json();
  check('卖家上传封面', upj.ok, upj);
  const fimg = await fetch(BASE + '/files/books/' + id2 + '.jpg');
  check('封面静态可访问', fimg.status === 200 && (await fimg.arrayBuffer()).byteLength === png.length);
  const minePhoto = await api('GET', '/api/books/mine', null, seller);
  check('我的书含封面标记', minePhoto.data.list.find((b) => b.id === id2).photo === 1, minePhoto.data.list);
  const fdup = await fetch(BASE + '/api/books/' + id2 + '/photo', { method: 'POST', headers: { Authorization: 'Bearer ' + buyer }, body: fd });
  check('非卖家不能传封面', (await fdup.json()).ok === false);

  console.log('== 5. 联系卖家与私聊 ==');
  const ct = await api('POST', '/api/books/' + id1 + '/contact', {}, buyer);
  check('联系卖家创建会话', ct.ok && typeof ct.data.chat_id === 'number', ct);
  const chatId = ct.data.chat_id;
  const det2 = await api('GET', '/api/books/' + id1, null, buyer);
  check('详情记住我的会话', det2.data.my_thread && det2.data.my_thread.chat_id === chatId, det2.data.my_thread);
  const self = await api('POST', '/api/books/' + id1 + '/contact', {}, seller);
  check('不能联系自己', !self.ok, self);
  const msgs0 = await api('GET', '/api/book-chats/' + chatId + '/messages', null, buyer);
  check('会话含系统提示语', msgs0.data.list.length === 1 && msgs0.data.list[0].sender_id === 0 && msgs0.data.list[0].type === 'system', msgs0.data);
  const m1 = await api('POST', '/api/book-chats/' + chatId + '/messages', { type: 'text', text: '同学你好，25 块能出吗' }, buyer);
  check('买家发文字', m1.ok && m1.data.m.type === 'text', m1);
  const uc = await api('GET', '/api/book-chats/unread-count', null, seller);
  check('卖家未读总数 1', uc.data.unread === 1, uc.data);
  const sellerChats = await api('GET', '/api/book-chats', null, seller);
  const sc = sellerChats.data.list.find((c) => c.id === chatId);
  check('卖家会话列表（书上下文+对方）', sc && sc.role === 'seller' && sc.book.title.indexOf('高等') === 0 && sc.other.nickname === '买书人' && sc.unread === 1, sc);
  const rd = await api('POST', '/api/book-chats/' + chatId + '/read', {}, seller);
  check('标记已读', rd.ok && (await api('GET', '/api/book-chats/unread-count', null, seller)).data.unread === 0);
  const m2 = await api('POST', '/api/book-chats/' + chatId + '/messages', { type: 'location', text: '紫菘操场旗杆下', lat: 30.51, lon: 114.40 }, seller);
  check('卖家发位置', m2.ok && m2.data.m.type === 'location', m2);
  const buyerUnread = await api('GET', '/api/book-chats/unread-count', null, buyer);
  check('买家未读总数 1（卖家消息）', buyerUnread.data.unread === 1, buyerUnread.data);
  const bcmsgs = await api('GET', '/api/book-chats/' + chatId + '/messages', null, seller);
  check('消息记录完整', bcmsgs.data.list.length === 3 && bcmsgs.data.list[1].text.indexOf('25') > -1, bcmsgs.data);
  const buyerNotifs = await api('GET', '/api/notifications', null, seller);
  const ntypes = buyerNotifs.data.list.map((n) => n.type);
  check('卖家收到 book_contact/book_msg 通知', ntypes.includes('book_contact') && ntypes.includes('book_msg'), ntypes);

  console.log('== 6. 上下架与售出 ==');
  const off = await api('POST', '/api/books/' + id1 + '/status', { status: 'off' }, seller);
  check('下架成功', off.ok, off);
  check('下架后买家不可见', !(await browse(buyer, '高等')).some((b) => b.id === id1));
  const detOff = await api('GET', '/api/books/' + id1, null, buyer);
  check('下架后详情拒绝', detOff._code === 404, detOff);
  await api('POST', '/api/books/' + id1 + '/status', { status: 'on' }, seller);
  check('重新上架后可见', (await browse(buyer, '高等')).some((b) => b.id === id1));
  const sold = await api('POST', '/api/books/' + id1 + '/status', { status: 'sold' }, seller);
  check('标记已售出', sold.ok && sold.data.status === 'sold', sold);
  const thirdParty = await regUser('b2_' + TS + '@t.com', '路人乙', 'male');
  const ct2 = await api('POST', '/api/books/' + id1 + '/contact', {}, thirdParty);
  check('售出后不能联系', !ct2.ok, ct2);
  const myAfter = await api('GET', '/api/books/mine', null, seller);
  check('我的书显示已售出', myAfter.data.list.find((b) => b.id === id1).status === 'sold', myAfter.data.list);

  console.log('== 7. 举报与管理端 ==');
  const rpShort = await api('POST', '/api/books/' + id2 + '/report', { reason: '短' }, buyer);
  check('举报原因过短被拒', !rpShort.ok, rpShort);
  const rp = await api('POST', '/api/books/' + id2 + '/report', { reason: '这本书有大量缺页，与描述严重不符' }, buyer);
  check('举报成功', rp.ok, rp);
  const dup = await api('POST', '/api/books/' + id2 + '/report', { reason: '再次举报该问题' }, buyer);
  check('重复举报被拒', !dup.ok, dup);
  const adminLogin = await api('POST', '/api/admin/login', { username: 'admin', password: 'leleadmin888' });
  const at = adminLogin.data.token;
  const ab = await api('GET', '/api/admin/books?status=on', null, at);
  check('管理端书单含成色中文与举报标记', ab.data.list.some((b) => b.id === id2 && b.cond_cn === '使用痕迹较多' && b.open_reports === 1), ab.data.list && ab.data.list[0]);
  const abq = await api('GET', '/api/admin/books?q=' + encodeURIComponent('卖书人'), null, at);
  check('管理端按卖家昵称搜索', abq.data.list.some((b) => b.id === id2), abq.data);
  const br = await api('GET', '/api/admin/book-reports', null, at);
  check('管理端看到书市举报', br.data.list.some((x) => x.book_id === id2 && x.status === 'open' && x.seller_name === '卖书人'), br.data);
  const rpId = br.data.list.find((x) => x.book_id === id2).id;
  const rsv = await api('POST', '/api/admin/book-reports/' + rpId + '/resolve', { note: '已核实，警告卖家' }, at);
  check('书市举报结案', rsv.ok, rsv);
  const ab2 = await api('GET', '/api/admin/books?status=on', null, at);
  check('结案后举报标记清零', ab2.data.list.find((b) => b.id === id2).open_reports === 0, ab2.data.list);
  const adSt = await api('POST', '/api/admin/books/' + id2 + '/status', { status: 'off' }, at);
  check('管理端下架书籍', adSt.ok && adSt.data.status === 'off', adSt);
  const dash = await api('GET', '/api/admin/dashboard', null, at);
  check('概览含书市统计', typeof dash.data.books_on === 'number' && typeof dash.data.open_book_reports === 'number', dash.data);

  // 清理
  tx(() => {
    for (const t of ['users', 'orders', 'runs', 'chats', 'chat_messages', 'notifications', 'email_codes', 'checkins', 'reviews', 'notices', 'reports', 'books', 'book_chats', 'book_messages', 'book_reports']) {
      if (t === 'users') db.prepare(`DELETE FROM users WHERE email LIKE '%@t.com'`).run();
      else db.prepare(`DELETE FROM ${t}`).run();
    }
  });
  db.close();
  console.log(`\n结果: ${pass} 通过, ${fail} 失败`);
  process.exit(fail ? 1 : 0);
})().catch((e) => {
  try { const { db } = require('../src/db'); db.close(); } catch (x) {}
  console.error(e); process.exit(1);
});
