// 纯函数工具集（无内部状态；注意：QML 脚本文件不支持跨文件 import，需要 api/ui 的请直接在页面里 import）
// ---------- 通用工具 ----------
var DAY_NAMES = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

function isEmail(s) { return /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(s || ''); }

function fen2yuan(fen) { return (fen / 100).toFixed(2); }
function yuan(fen) { return '¥' + fen2yuan(fen); }

// 输入框金额（元，如 "3.5"）-> 分（整数），非法返回 NaN
function yuanToCents(s) {
    if (s === null || s === undefined) return NaN;
    var n = parseFloat(String(s).trim());
    if (!isFinite(n) || n < 0) return NaN;
    return Math.round(n * 100);
}

// 书市新旧程度
function bookCondCN(c) {
    return { 1: '全新未使用', 2: '几乎全新', 3: '有笔记划线', 4: '使用痕迹较多' }[c] || '';
}

function weekdayName(day) { return DAY_NAMES[day] || ''; }

// 北京时间今天的 YYYY-MM-DD
function todayKey() {
    return new Date(Date.now() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}
function tomorrowKey() {
    return new Date(Date.now() + 8 * 3600 * 1000 + 86400000).toISOString().slice(0, 10);
}

// 'YYYY-MM-DD' -> '8月26日 周三'
// 注意：必须按 UTC 零点解析再用 UTC 取值；若按 +08:00 解析，北京零点=UTC 前一天 16 点，
// 用 UTC 取值会整体回退一天（曾导致"9月9日"显示成"9月8日 周二"+错误周几）
function dateCN(dateStr) {
    var d = new Date(dateStr + 'T00:00:00Z');
    return (d.getUTCMonth() + 1) + '月' + d.getUTCDate() + '日 ' + DAY_NAMES[d.getUTCDay()];
}

// 列表用日期标签：今天/明天补周几，其余日期 dateCN 自带周几（不要再拼一次，避免双周几）
function dateLabel(dateStr, weekday) {
    if (dateStr === todayKey()) return '今天 ' + weekdayName(weekday);
    if (dateStr === tomorrowKey()) return '明天 ' + weekdayName(weekday);
    return dateCN(dateStr);
}

// 今天/明天/日期
function relativeDate(dateStr) {
    if (dateStr === todayKey()) return '今天';
    if (dateStr === tomorrowKey()) return '明天';
    return dateCN(dateStr);
}

// 时间格说明：9 点 = 8:55-9:00 集合
function slotLabel(h) { return h + '点（' + (h - 1) + ':55 集合）'; }
function hoursLabel(hours) {
    return hours.map(function (h) { return h + ':00'; }).join('、');
}

// 性别
function genderCN(g) { return g === 'male' ? '男' : '女'; }
function genderReqCN(g) { return g === 'none' ? '不限' : g === 'male' ? '仅男' : '仅女'; }

// 跑单状态中文
function runStatusCN(s) {
    return {
        requested: '待挂单方确认',
        confirmed: '进行中',
        completed: '已完成',
        poster_noshows: '挂单方爽约',
        receiver_noshows: '接单方爽约',
        rain_cancelled: '雨天终止',
        rejected: '已拒绝'
    }[s] || s;
}

// 时间戳 -> HH:mm（北京时间）
function tsHHMM(ts) {
    if (!ts) return '';
    var d = new Date(ts + 8 * 3600 * 1000);
    return ('0' + d.getUTCHours()).slice(-2) + ':' + ('0' + d.getUTCMinutes()).slice(-2);
}

// 时间戳 -> MM-DD HH:mm
function tsShort(ts) {
    if (!ts) return '';
    var d = new Date(ts + 8 * 3600 * 1000);
    return ('0' + (d.getUTCMonth() + 1)).slice(-2) + '-' + ('0' + d.getUTCDate()).slice(-2) + ' ' + tsHHMM(ts);
}

// 默认头像文字：昵称首字符（字母取大写）
function avatarText(nickname) {
    if (!nickname) return '乐';
    var ch = nickname.charAt(0);
    return /[a-zA-Z]/.test(ch) ? ch.toUpperCase() : ch;
}

// 从挂单 slots 生成摘要，如 "周一 9点、周三 9点"
function slotsSummary(slots) {
    if (!slots || !slots.length) return '';
    var byDay = {};
    slots.forEach(function (s) {
        if (!byDay[s.day]) byDay[s.day] = [];
        byDay[s.day].push(s.hour);
    });
    var parts = [];
    Object.keys(byDay).sort(function (a, b) { return a - b; }).forEach(function (d) {
        var hours = byDay[d].sort(function (a, b) { return a - b; });
        parts.push(DAY_NAMES[+d] + ' ' + hours.join('、') + '点');
    });
    return parts.join('，');
}

// ---------- 坐标系转换：WGS-84（系统定位）→ GCJ-02（高德/火星坐标） ----------
// Android 定位给出的是 WGS-84 真坐标，而高德地图（含 uri.amap.com 链接）按 GCJ-02
// 解释坐标——不转换直接发，地图上会整体偏移几百米到一公里（"十万八千里"的主因）。
function _transformLat(x, y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
    ret += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
    ret += (20.0 * Math.sin(y * Math.PI) + 40.0 * Math.sin(y / 3.0 * Math.PI)) * 2.0 / 3.0;
    ret += (160.0 * Math.sin(y / 12.0 * Math.PI) + 320 * Math.sin(y * Math.PI / 30.0)) * 2.0 / 3.0;
    return ret;
}
function _transformLon(x, y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
    ret += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
    ret += (20.0 * Math.sin(x * Math.PI) + 40.0 * Math.sin(x / 3.0 * Math.PI)) * 2.0 / 3.0;
    ret += (150.0 * Math.sin(x / 12.0 * Math.PI) + 300.0 * Math.sin(x / 30.0 * Math.PI)) * 2.0 / 3.0;
    return ret;
}
// 返回 {lat:..., lon:...}；中国境外原样返回（GCJ 只在国内有意义）
function wgs2gcj(lat, lon) {
    if (lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271) return { lat: lat, lon: lon };
    var a = 6378245.0, ee = 0.00669342162296594323;
    var dLat = _transformLat(lon - 105.0, lat - 35.0);
    var dLon = _transformLon(lon - 105.0, lat - 35.0);
    var radLat = lat / 180.0 * Math.PI;
    var magic = Math.sin(radLat);
    magic = 1 - ee * magic * magic;
    var sqrtMagic = Math.sqrt(magic);
    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * Math.PI);
    dLon = (dLon * 180.0) / (a / sqrtMagic * Math.cos(radLat) * Math.PI);
    return { lat: lat + dLat, lon: lon + dLon };
}
// 定位精度是否可接受：拿不到精度值时视为可接受（不同平台/后端表现不一，不要卡死用户）
function accuracyOk(acc) {
    return (acc === undefined || acc === null || isNaN(acc) || acc <= 150);
}
