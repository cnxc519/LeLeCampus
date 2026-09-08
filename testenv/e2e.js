// 端到端全流程测试（隔离测试服务器 8898，不碰生产库）
// 流程：注册A/B -> A挂单 -> B接单 -> 双向聊天 -> A确认 -> 进行中 -> 完成 -> 买书聊天 -> 通知
const BASE = 'http://127.0.0.1:8898';

async function api(method, path, token, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: Object.assign({ 'Content-Type': 'application/json' }, token ? { Authorization: 'Bearer ' + token } : {}),
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await res.json().catch(() => ({}));
  if (!j.ok) throw new Error(`${method} ${path} -> ${res.status} ${j.error && j.error.msg || 'no error msg'}`);
  return j.data;
}

let pass = 0, failCnt = 0;
function check(name, cond, extra) {
  if (cond) { pass++; console.log('  PASS ' + name); }
  else { failCnt++; console.log('  FAIL ' + name + (extra ? ' | ' + JSON.stringify(extra).slice(0, 200) : '')); }
}

// 每次运行用随机邮箱，保证脚本可重复执行（注册接口唯一性约束）
const RUN = Date.now().toString(36);
const EMAIL_A = 'a_' + RUN + '@test.com';
const EMAIL_B = 'b_' + RUN + '@test.com';

(async () => {
  console.log('== 1. 公开接口 ==');
  const schools = await api('GET', '/api/schools');
  check('schools 非空', schools.list.length > 0);
  const schoolId = schools.list[0].id;
  const pgId = schools.list[0].playgrounds[0].id;

  console.log('== 2. 注册两个用户 ==');
  const regA = async (email) => {
    await api('POST', '/api/auth/send-code', null, { email, purpose: 'register' });
    // dev_mode 下验证码随接口返回；再取一次会限频，直接从 send-code 响应拿
    return api('POST', '/api/auth/send-code', null, { email, purpose: 'register' }).catch(() => null);
  };
  // send-code 60 秒限频：脚本直接查库拿验证码不行（跨进程），改用 dev_code 返回
  const c1 = await api('POST', '/api/auth/send-code', null, { email: EMAIL_A, purpose: 'register' });
  const codeA = c1.dev_code;
  check('dev_mode 返回验证码', !!codeA, c1);
  const A = (await api('POST', '/api/auth/register', null, { email: EMAIL_A, code: codeA, nickname: '甲', school_id: schoolId, gender: 'male' }));
  check('A 注册成功', !!A.token);

  // B 注册带 A 的邀请码
  const meA0 = await api('GET', '/api/auth/me', A.token);
  const c2 = await api('POST', '/api/auth/send-code', null, { email: EMAIL_B, purpose: 'register' });
  const B = await api('POST', '/api/auth/register', null, { email: EMAIL_B, code: c2.dev_code, nickname: '乙', school_id: schoolId, gender: 'female', invite_code: meA0.invite_code ? undefined : undefined });
  check('B 注册成功', !!B.token);

  console.log('== 3. A 挂单 ==');
  // 明天的时间格：day 由星期决定，直接给全周 8-23 全格，保证明天可用
  const slots = [];
  for (let d = 0; d < 7; d++) for (let h = 8; h <= 23; h++) slots.push({ day: d, hour: h });
  const ord = await api('POST', '/api/orders', A.token, { playground_id: pgId, remark: '帮我取个快递', price_cents: 300, slots, run_count: 3, gender_required: 'none' });
  check('挂单成功', !!ord.id, ord);

  console.log('== 4. B 浏览接单列表 + 详情 ==');
  const list = await api('GET', '/api/orders?page=1', B.token);
  check('列表含 A 的挂单', list.list.some(o => o.id === ord.id), { total: list.total });
  const detail = await api('GET', '/api/orders/' + ord.id, B.token);
  check('详情 available_dates 非空', detail.available_dates.length > 0);
  check('详情含 poster.is_mine=false', detail.is_mine === false);

  console.log('== 5. B 接单 ==');
  const target = detail.available_dates[0];
  const take = await api('POST', '/api/orders/' + ord.id + '/take', B.token, { date: target.date, hours: target.hours });
  check('接单申请成功 run_id/chat_id', !!take.run_id && !!take.chat_id, take);

  console.log('== 6. 聊天（此前 ChatPage 调用了不存在的 GET /api/chats/:id） ==');
  // 会话列表双方可见
  const chatsA = await api('GET', '/api/chats', A.token);
  check('A 会话列表含该会话', chatsA.list.some(c => c.id === take.chat_id));
  // 关键回归：消息记录接口（客户端修复后调用 /messages）
  const sysMsgs = await api('GET', '/api/chats/' + take.chat_id + '/messages', A.token);
  check('聊天记录含系统消息', sysMsgs.list.length > 0 && sysMsgs.list[0].type === 'system');
  // 双向发消息
  const m1 = await api('POST', '/api/chats/' + take.chat_id + '/messages', B.token, { type: 'text', text: '你好，明天见' });
  const m2 = await api('POST', '/api/chats/' + take.chat_id + '/messages', A.token, { type: 'text', text: '好的，8点55集合' });
  const m3 = await api('POST', '/api/chats/' + take.chat_id + '/messages', A.token, { type: 'location', text: '操场北门', lat: 30.5, lon: 114.4 });
  const msgsA = await api('GET', '/api/chats/' + take.chat_id + '/messages', A.token);
  check('记录含双向消息+位置', msgsA.list.length >= 4 && msgsA.list.some(m => m.type === 'location'), { n: msgsA.list.length });
  const msgsB = await api('GET', '/api/chats/' + take.chat_id + '/messages', B.token);
  check('B 拉记录同样可见', msgsB.list.length >= 4);
  // request 接口（聊天页顶部申请卡）
  const req = await api('GET', '/api/chats/' + take.chat_id + '/request', A.token);
  check('申请卡数据 status=requested', req.run && req.run.status === 'requested');

  console.log('== 7. A 确认接单 -> 进行中 ==');
  await api('POST', '/api/orders/requests/' + take.run_id + '/confirm', A.token, {});
  const req2 = await api('GET', '/api/chats/' + take.chat_id + '/request', A.token);
  check('确认后申请卡消失', !req2.run || req2.run.status !== 'requested');
  const activeA = await api('GET', '/api/active', A.token);
  check('A 进行中列表有 confirmed 单', activeA.list.some(r => r.id === take.run_id && r.status === 'confirmed' && r.role === 'poster'));
  const activeB = await api('GET', '/api/active', B.token);
  check('B 进行中列表 role=receiver', activeB.list.some(r => r.id === take.run_id && r.role === 'receiver'));

  console.log('== 8. 打卡 + 完成 ==');
  await api('POST', '/api/active/' + take.run_id + '/checkin', B.token, { lat: 30.5, lon: 114.4 });
  const ad = await api('GET', '/api/active/' + take.run_id, B.token);
  check('打卡记录可见', ad.checkins.length === 1);
  await api('POST', '/api/active/' + take.run_id + '/complete', A.token, {});
  const ad2 = await api('GET', '/api/active/' + take.run_id, A.token);
  check('完成后状态 completed', ad2.status === 'completed');

  console.log('== 9. 书市：A 出书 B 买书 ==');
  const book = await api('POST', '/api/books', A.token, { title: '高等数学(第七版)上册', course: '高等数学', cond: 3, price_cents: 1500, note: '有少量笔记' });
  check('出书成功', !!book.id);
  const blist = await api('GET', '/api/books?page=1', B.token);
  check('B 书市列表可见', blist.list.some(b => b.id === book.id));
  const bd = await api('GET', '/api/books/' + book.id, B.token);
  check('书详情 is_seller=false', bd.is_seller === false);
  const contact = await api('POST', '/api/books/' + book.id + '/contact', B.token, {});
  check('联系卖家返回 chat_id', !!contact.chat_id);
  const bm1 = await api('POST', '/api/book-chats/' + contact.chat_id + '/messages', B.token, { type: 'text', text: '同学，书还在吗？18 卖不卖' });
  const bm2 = await api('POST', '/api/book-chats/' + contact.chat_id + '/messages', A.token, { type: 'text', text: '在的，20 拿走' });
  const bmsgs = await api('GET', '/api/book-chats/' + contact.chat_id + '/messages', B.token);
  check('书市聊天记录双向可见', bmsgs.list.length >= 3, { n: bmsgs.list.length });
  const bchatsA = await api('GET', '/api/book-chats', A.token);
  check('A 书市消息列表可见', bchatsA.list.some(c => c.id === contact.chat_id));
  const unread = await api('GET', '/api/book-chats/unread-count', A.token);
  check('A 未读角标 > 0', unread.unread > 0, unread);

  console.log('== 10. 通知中心 ==');
  const notifB = await api('GET', '/api/notifications', B.token);
  check('B 收到通知(申请被确认/完成等)', notifB.list.length > 0, { n: notifB.list.length });
  check('B 通知含 request_confirmed', notifB.list.some(n => n.type === 'request_confirmed'));
  // take_request 发给挂单方 A（B 是接单方）
  const notifA = await api('GET', '/api/notifications', A.token);
  check('A 通知含 take_request', notifA.list.some(n => n.type === 'take_request'));
  await api('POST', '/api/notifications/read', B.token, { id: notifB.list[0].id });

  console.log('== 11. 评价 + 历史 ==');
  await api('POST', '/api/active/' + take.run_id + '/review', A.token, { score: 5, comment: '跑得快！' });
  await api('POST', '/api/active/' + take.run_id + '/review', B.token, { score: 5, comment: '爽快' });
  const profA = await api('GET', '/api/users/' + A.user.id + '/profile', B.token);
  check('A 主页评价数=1', profA.user.review_count === 1, profA.user.review_count);
  const histB = await api('GET', '/api/me/history?role=receiver', B.token);
  check('B 接单记录非空', histB.list.length > 0);

  console.log('== 12. 重复拉取幂等（无新消息时记录数稳定） ==');
  const again1 = await api('GET', '/api/chats/' + take.chat_id + '/messages', A.token);
  const again2 = await api('GET', '/api/chats/' + take.chat_id + '/messages', A.token);
  check('重复拉取记录数稳定', again1.list.length === again2.list.length && again1.list.length >= msgsA.list.length);

  console.log('');
  console.log('RESULT: pass=' + pass + ' fail=' + failCnt);
  process.exit(failCnt > 0 ? 1 : 0);
})().catch((e) => { console.error('FATAL', e.message); process.exit(2); });
