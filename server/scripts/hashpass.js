// 生成管理后台密码的 bcrypt 哈希（备用，当前版本 config 直接存明文密码）
const bcrypt = require('bcryptjs');
const pwd = process.argv[2];
if (!pwd) { console.error('用法: npm run hashpass -- 你的密码'); process.exit(1); }
console.log(bcrypt.hashSync(pwd, 10));
