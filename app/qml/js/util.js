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
