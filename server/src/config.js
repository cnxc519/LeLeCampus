// 加载 config.json 并读取/写入数据库中的可调设置（管理后台可改）
const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');

const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'config.json'), 'utf8'));

// 管理密码：启动时哈希一次，登录时比对
cfg.adminHash = bcrypt.hashSync(String(cfg.admin.password || 'admin888'), 10);

// 数据库可调设置（无支付版本，仅保留流程参数）
const DEFAULTS = {
  receiver_max_concurrent: 5,  // 接单方同一时间点最多同时在跑的单数
  appeal_hours: 12,            // 爽约反驳窗口（小时）
  rain_response_hours: 6,      // 雨天终止对方默认同意时限（小时）
  request_expire_hours: 48,    // 接单申请未处理自动关闭（小时）
  avatar_max_kb: 200,          // 头像最大 KB
  run_count_default: 5,        // 挂单次数默认值
  run_count_max: 30,           // 挂单次数上限
};

module.exports = { cfg, DEFAULTS };
