# 乐乐代跑 · 服务端部署指南

## 环境要求
- Node.js ≥ 22.5（建议 24 LTS）。服务器（47.91.25.15）未装 Node 时按下方步骤安装。
- 无任何编译依赖（数据库用 Node 内置 node:sqlite），1 核 1G 即可跑。

## 一、本机开发（已配置好，可直接跑）

```bash
cd server
npm install
node src/index.js        # 或 npm start（端口 8899）
```

- 开发模式（config.json `dev_mode: true`）：验证码直接打印在控制台，并随接口返回（`dev_code`），方便联调。
- 冒烟测试（跑完自动清空测试数据）：
  - `node scripts/smoke.js`：注册登录/挂单（含期望报酬）/接单/确认/完成/评价/聊天/管理端
  - `node scripts/smoke2.js`：状态机（雨天终止/爽约认定与反驳/完成/次数耗尽）
  - `node scripts/smoke3.js`：评价/公告/举报/学校管理
  - `node scripts/smoke4.js`：期望报酬边界与金额排序、书市全流程（发布/浏览/私聊/已读/状态/举报/封面图/管理端书市管理）

## 二、一键部署（推荐，本地电脑执行）

```bash
cd server
bash deploy.sh
```

脚本自动完成：上传代码 → 安装 Node 24（如未装）→ npm install → PM2 启动并设开机自启 → 放行 8899 端口。
执行过程会提示输入服务器 SSH 密码（阿里云 root 密码）。

**注意**：阿里云安全组还需在网页控制台放行 TCP 8899 端口（脚本只处理服务器内部防火墙）。

## 三、手动部署到服务器（47.91.25.15）

```bash
# 1. 上传代码
scp -r server/ root@47.91.25.15:/opt/lele/

# 2. SSH 登录服务器后安装 Node 24（以 Ubuntu/Debian 为例）
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get install -y nodejs

# 3. 安装依赖并启动
cd /opt/lele/server
npm install --omit=dev
npm install -g pm2
pm2 start src/index.js --name lele
pm2 save && pm2 startup

# 4. 放行端口
# 阿里云安全组放行 8899 端口（TCP）；服务器上如有防火墙：
#   ufw allow 8899/tcp  或  iptables -A INPUT -p tcp --dport 8899 -j ACCEPT
```

启动后访问：
- 接口：`http://47.91.25.15:8899/api/ping`（应返回 ok）
- 管理后台：`http://47.91.25.15:8899/admin`（默认账号 `admin` / `leleadmin888`，**上线务必修改**）

## 四、上线前必做配置（config.json）

| 配置 | 说明 |
|---|---|
| `dev_mode` | 改为 `false`（否则验证码会随接口返回） |
| `jwt_secret` | 改成一串随机长字符串：`openssl rand -hex 32` |
| `smtp` | 已内置 QQ 邮箱配置；换邮箱时改这里 |
| `admin.password` | 修改管理后台密码 |

## 四·补、验证码邮件配置（已内置 QQ 邮箱）

config.json 已配置：`smtp.qq.com:587`（STARTTLS），user/pass 为 QQ 邮箱 SMTP 授权码。
如要换邮箱：填 host/port（465 用 `secure: true`，587 用 `secure: false`）、user、pass（授权码）后重启服务。

## 五、管理后台使用

- **学校管理**：添加新学校（App 注册时学校只可选择）。
- **操场管理**：添加/改名/删除操场（删除前需无进行中挂单）。已预置武汉大学 6 个操场。
- **公告管理**：发布公告后，App 接单页顶部横幅 + "公告中心"展示；可下线/删除。
- **规则设置**：流程参数（接单并发上限/爽约反驳窗口/雨天默认同意时限/挂单次数等）在线可改，立即生效。
- **用户管理**：搜索用户、封禁（被封无法登录与操作）。
- **举报处理**：App 内代跑违规举报在此审核结案；情节严重的封禁用户。
- **书市书籍**：书市在售/下架/已售出书籍列表，可按状态筛选、按书名或卖家昵称搜索，展示成色与"被举报中"标记；可下架 / 重新上架 / 标记已售出。
- **书市举报**：买家对书籍的举报在此审核结案（填处理说明），结案后书籍列表的举报标记自动消失。
- **版本更新**：上传 APK（自动放到 `/files/apk/lele-daipao.apk`），设置版本号/最低版本/说明/是否强制；App 内自动下载安装，低于最低版本强制更新。

> 本版本为无支付模式：平台不代收任何费用，费用由双方线下当面结算，无充值/余额/提现/抽成相关功能。书市同样只做联系中转，不代收书款、不做担保（详情与会话内均已提示线下当面验书付款）。

## 六、数据与备份

- 数据文件：`server/data.db`（单文件）。
- 一键备份（保留 14 天）：`bash backup.sh`；定时自动备份：服务器上 `crontab -e` 添加
  ```
  0 4 * * * /bin/bash /opt/lele/server/backup.sh
  ```
- 头像目录：`server/uploads/avatars/`；书市封面：`server/uploads/books/`（每本一张，按书籍 ID 命名 `books/<id>.jpg`）；APK：`server/uploads/apk/`。

## 七、常见问题

- **验证码收不到**：确认 SMTP 已配置且 config 修改后重启；dev_mode 下看控制台打印。
- **App 连不上服务器**：App 内"我的-服务器设置"检查地址是否为 `http://47.91.25.15:8899`；确认阿里云安全组已放行 8899 端口。
- **需要 HTTPS**：当前是 `http://IP:端口`（明文传输，验证码/口令有被窃听风险）。正式运营建议绑定域名 + 备案 + 免费证书（如 Let's Encrypt / 阿里云免费证书），然后在 `app` 的 nginx/反代层开启 HTTPS，并把 App 默认地址改为 `https://域名`；同时移除 AndroidManifest 中的 `usesCleartextTraffic`。

## 八、安全说明（已内置）

- 验证码：6 位、10 分钟有效、单次使用、60 秒发送间隔、每邮箱每天 10 次、登录尝试限流
- SQL：全部参数化查询；规则状态流转全部走事务
- 上传：仅 JPG/PNG、大小上限可配（默认 200KB）、按用户 ID 命名
- 封禁：被封用户无法登录与操作；接单方被封后其待确认申请无法被确认（建议挂单方拒绝）
- 明文 HTTP 阶段请勿使用与重要账号相同的邮箱密码等敏感信息
