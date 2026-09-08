// 乐乐代跑 服务端入口
const path = require('path');
const http = require('http');
const express = require('express');
const { cfg } = require('./config');
const { initWs } = require('./ws');
const { initSweeps } = require('./sweeps');
const { ok } = require('./util');

require('./db'); // 初始化数据库

const app = express();
app.disable('x-powered-by');
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  next();
});
app.use(express.json({ limit: '128kb' }));

// 静态资源：头像 / 书籍封面（APK 不允许公开直链下载，见下方 /dl/apk）
// 拦截必须放在 express.static 之前，否则静态服务会先命中并直接回包
app.use('/files/apk', (req, res) => res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', msg: '接口不存在' } }));
app.use('/files', express.static(path.join(__dirname, '..', 'uploads'), { maxAge: '1d' }));
// 签名下载入口：/dl/apk?e=<过期时间ms>&k=<hmac>（10 分钟内有效，由 /api/apk-dl-url 签发）
app.get('/dl/apk', (req, res) => {
  const e = parseInt(req.query.e, 10);
  const k = String(req.query.k || '');
  const crypto = require('crypto');
  const expect = crypto.createHmac('sha256', cfg.jwt_secret).update(`apk|${e}`).digest('hex');
  if (!Number.isFinite(e) || e < Date.now() || k !== expect) {
    return res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', msg: '下载链接已失效，请在 App 内重新获取' } });
  }
  res.setHeader('Content-Type', 'application/vnd.android.package-archive');
  res.setHeader('Content-Disposition', 'attachment; filename="lele-daipao.apk"');
  res.sendFile(path.join(__dirname, '..', 'uploads', 'apk', 'lele-daipao.apk'));
});
// 管理后台网页
app.use('/admin', express.static(path.join(__dirname, '..', 'admin')));

// 健康检查
app.get('/api/ping', (req, res) => ok(res, { time: Date.now(), tz: 'UTC+8', dev: cfg.dev_mode }));

// 路由
app.use('/api/auth', require('./routes/auth'));
app.use('/api/orders', require('./routes/orders'));
app.use('/api/active', require('./routes/active'));
app.use('/api/chats', require('./routes/chat'));
app.use('/api/book-chats', require('./routes/bookchats'));
app.use('/api/books', require('./routes/books'));
app.use('/api/invite', require('./routes/invite'));
app.use('/api', require('./routes/misc'));
app.use('/api/admin', require('./routes/admin'));

// 404 & 错误兜底
app.use((req, res) => res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', msg: '接口不存在' } }));
app.use((err, req, res, next) => {
  if (res.headersSent) return next(err);
  console.error('[error]', err.message);
  res.status(500).json({ ok: false, error: { code: 'SERVER_ERROR', msg: '服务器开小差了，请稍后重试' } });
});

const server = http.createServer(app);
// Node 18+ 默认 requestTimeout=300s：服务器带宽小时上传几百 MB 的 APK 会被中途掐断
// （管理后台表现为 TypeError: Failed to fetch）。关闭总超时，仅保留头部/保活超时。
server.requestTimeout = 0;
server.headersTimeout = 60 * 1000;
server.keepAliveTimeout = 75 * 1000;
initWs(server);
initSweeps();

server.listen(cfg.port, cfg.host, () => {
  console.log('==========================================');
  console.log(' 乐乐代跑服务端已启动');
  console.log(` 地址: http://${cfg.host}:${cfg.port}`);
  console.log(` 管理后台: http://服务器IP:${cfg.port}/admin`);
  console.log(` 开发模式: ${cfg.dev_mode ? '开（验证码会打印在控制台）' : '关'}`);
  if (!cfg.smtp || !cfg.smtp.host) console.log(' 提醒: 尚未配置 SMTP，验证码不会真正发送邮件，只会打印在控制台');
  if (cfg.jwt_secret.startsWith('请修改')) console.log(' 警告: jwt_secret 还是默认占位符，正式上线前请修改 config.json');
  console.log('==========================================');
});
