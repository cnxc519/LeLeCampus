# 乐乐代跑 · Android 客户端构建指南

## 环境准备

1. **Qt 6.5+**（含 Android 支持）：
   - 下载 Qt 在线安装器：https://www.qt.io/download-open-source
   - 勾选组件：`Qt 6.8.x → Android`、`Qt 6.8.x → Qt Quick`、`Qt 6.8.x → Additional Libraries（Qt WebSockets / Qt Positioning 已含）`
2. **Android SDK / NDK / JDK**：Qt Creator 会引导安装（Tools → Options → Devices → Android），或手动安装 Android Studio 后用其 SDK。
3. **打开工程**：Qt Creator → 打开 `app/CMakeLists.txt`，选择 Android Kit（如 `Qt 6.8.2 Android`）。

## 构建 APK

- 菜单 **构建 → 构建项目 LeLeDaiPao**（或 Ctrl+B），选择 Android 目标。
- 产物路径：`app/build/LeLeDaiPao/build/Android/.../android-build/build/outputs/apk/debug/lele-daipao.apk`
- 测试安装：连接手机（开启 USB 调试）→ 运行按钮直接装到手机；或把 APK 拷到手机安装（需允许"安装未知来源应用"）。

## 配置要点

| 文件 | 说明 |
|---|---|
| `app/android/AndroidManifest.xml` | 包名 `com.lele.daipao`、应用名"乐乐代跑"、权限（网络/定位/安装）、FileProvider、`usesCleartextTraffic`（http 明文，上 HTTPS 后删除） |
| `app/android/res/xml/file_paths.xml` | 应用内更新安装 APK 的文件共享配置 |
| `app/src/main.cpp` | `APP_VERSION_CODE` 版本号（与服务端管理后台的 version_code 对应） |
| App 内"我的 → 服务器设置" | 默认 `http://47.91.25.15:8899`，测试时可改本机 IP |

**注意**：
- 如果 Qt Creator 提示缺 android 目录下的 gradle 文件，直接构建一次即可自动生成（本工程已提供 AndroidManifest.xml 作基础模板）。
- **应用内安装需要 androidx.core**：Qt 默认 Android 模板若不含，请在构建生成的 `android/build.gradle` 的 `dependencies` 中加入：
  ```gradle
  implementation 'androidx.core:core:1.13.1'
  ```
  若不加也不影响其他功能，仅"应用内更新"的自动安装不可用（可改用浏览器下载安装）。

## 更新方式说明

- App 内自动下载 APK 到应用目录 → 弹系统安装界面（首次需允许"安装未知应用"）
- 下载失败时提供"去浏览器下载"兜底
- 强制更新：版本低于最低可用版本时弹窗不可关闭，只能更新或退出

## 发布更新流程

1. 修改代码 → 构建 **Release** APK（`构建 → 构建 Release`）。
2. 登录管理后台（`http://47.91.25.15:8899/admin`）→ "版本更新" → 上传 APK。
3. 设置：
   - **当前版本号**：与 `main.cpp` 中 `APP_VERSION_CODE` 一致（如 101）
   - **最低可用版本号**：低于它的设备强制更新
   - **更新说明**：如"修复了 XXX"
   - **本次更新强制**：是/否
4. 保存后，所有 App 下次打开（或点击"检查更新"）即收到更新提示。

## 签名（正式发布建议）

Qt Creator 默认使用调试签名（debug.keystore），可安装使用。正式分发建议创建正式签名：
1. 工具 → 选项 → 设备 → Android → 签名（Create 一个 keystore，记住密码）
2. 构建时选择该签名；更换签名后旧包无法覆盖安装（需卸载重装）。

## 常见问题

- **提示找不到 Android SDK**：Qt Creator 选项里指定 SDK/NDK 路径（Android Studio 装过的可直接用）。
- **手机连不上**：开启开发者选项 → USB 调试；部分手机需在"USB 用途"选"文件传输"。
- **定位功能不可用**：Android 11+ 需要运行时授权；App 首次定位会弹权限申请，拒绝后到系统设置里开启。
- **无支付说明**：本产品为无支付模式——平台不碰钱（无充值/余额/提现/抽成），代跑费用与书市书款均由双方线下当面结算，客户端不含任何支付与提现代码。若未来要接入微信/支付宝，需要：营业执照 + 域名备案 + HTTPS + 商户号，从零搭建收款与打款流程（见 [docs/PRODUCT_PLAN.md](PRODUCT_PLAN.md) 的产品原则）。
