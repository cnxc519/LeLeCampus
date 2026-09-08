import QtQuick
import LeLeDaiPao 1.0
import QtQuick.Controls
import QtPositioning
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 跑单详情：状态、双方、打卡、操作（完成/爽约/雨天/申诉）
Item {
    id: page
    property var app: null
    property int runId: 0
    property var _unsubRun: null // Realtime 订阅注销函数
    property var detail: null // 注意：不能叫 data —— 那是 Item 内置默认属性（存子对象），遮蔽它会静默丢弃整棵 UI 树

    // 不透底：推入详情栈后浮在 Tab 页之上，根必须有不透明背景，否则下层 Tab 内容会透出来
    Rectangle {
        anchors.fill: parent
        color: Root.Theme.bg
    }

    Column {
        anchors.fill: parent

        AppHeader {
            showBack: true
            title: "跑单详情"
            onBackClicked: app.popPage()
        }

        Flickable {
            width: parent.width
            height: parent.height - 52
            contentHeight: col.implicitHeight + 30
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: parent.width - 32
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                // 基本信息
                AppCard {
                    width: parent.width
                    height: info.implicitHeight + 24
                    Column {
                        id: info
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 8

                        Row {
                            width: parent.width
                            spacing: 8
                            Text {
                                text: page.detail ? (Util.relativeDate(page.detail.date) + " " + Util.hoursLabel(page.detail.hours)) : ""
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: Root.Theme.text
                            }
                            TagBadge {
                                text: page.detail ? Util.runStatusCN(page.detail.status) : ""
                                fg: Root.Theme.blue
                                bg: Root.Theme.blueSoft
                            }
                        }
                        Text {
                            width: parent.width
                            text: page.detail ? (page.detail.playground + " · " + page.detail.remark) : ""
                            font.pixelSize: 13
                            color: Root.Theme.textSub
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            text: "本单报酬：" + Util.yuan(page.detail ? page.detail.price_cents : 0) + "/次"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Root.Theme.primary
                        }
                        Text {
                            width: parent.width
                            // meet_note 服务端已带「集合时间 xx:55-xx:00」前缀，页面不再重复拼接
                            text: page.detail ? page.detail.meet_note : ""
                            font.pixelSize: 12
                            color: Root.Theme.warning
                            wrapMode: Text.Wrap
                        }

                        Row {
                            width: parent.width
                            spacing: 8
                            Avatar {
                                size: 40
                                nickname: page.detail ? (page.detail.role === "poster" ? page.detail.receiver.nickname : page.detail.poster.nickname) : ""
                                photo: page.detail && ((page.detail.role === "poster" ? page.detail.receiver.avatar === 1 : page.detail.poster.avatar === 1))
                                photoUrl: page.detail
                                    ? (page.detail.role === "poster"
                                        ? (page.detail.receiver.avatar === 1 ? Session.baseUrl + "/files/avatars/" + page.detail.receiver.id + ".jpg" : "")
                                        : (page.detail.poster.avatar === 1 ? Session.baseUrl + "/files/avatars/" + page.detail.poster.id + ".jpg" : ""))
                                    : ""
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    text: page.detail ? ((page.detail.role === "poster" ? "接单方 " : "挂单方 ") + (page.detail.role === "poster" ? page.detail.receiver.nickname : page.detail.poster.nickname)) : ""
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    color: Root.Theme.text
                                }
                                Text {
                                    text: "照片用于相认，见面请核对"
                                    font.pixelSize: 11
                                    color: Root.Theme.textLight
                                }
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 64; height: 30
                                radius: 15
                                color: Root.Theme.primarySoft
                                Text {
                                    anchors.centerIn: parent
                                    text: "看主页"
                                    font.pixelSize: 12
                                    color: Root.Theme.primaryDark
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: app.pushPage("ProfilePage.qml", { userId: page.detail.role === "poster" ? page.detail.receiver.id : page.detail.poster.id })
                                }
                            }
                        }
                    }
                }

                // 状态提示
                NoticeBar {
                    width: parent.width
                    text: page.detail ? page.statusHint() : ""
                    fg: page.detail && page.detail.status === "confirmed" && page.detail.rain_state ? Root.Theme.warning : Root.Theme.blue
                    bg: page.detail && page.detail.status === "confirmed" && page.detail.rain_state ? Root.Theme.warningSoft : Root.Theme.blueSoft
                }

                // 雨天请求处理（对方发起的才需要我回应）
                Rectangle {
                    width: parent.width
                    visible: page.detail && page.detail.status === "confirmed" && page.canReplyRain()
                    height: 52
                    radius: 12
                    color: Root.Theme.warningSoft
                    Row {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.detail && page.detail.rain_state === "requested_by_poster" ? "对方请求雨天终止" : "对方请求雨天终止"
                            color: Root.Theme.warning
                            font.pixelSize: 13
                        }
                        Item { width: 8 }
                        Rectangle {
                            width: 76; height: 32
                            radius: 16
                            color: Root.Theme.primary
                            Text { anchors.centerIn: parent; text: "同意终止"; color: "#FFFFFF"; font.pixelSize: 12 }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: page.rainReply(true)
                            }
                        }
                        Rectangle {
                            width: 76; height: 32
                            radius: 16
                            color: "#FFFFFF"
                            border.color: Root.Theme.danger
                            Text { anchors.centerIn: parent; text: "不同意"; color: Root.Theme.danger; font.pixelSize: 12 }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: page.rainReply(false)
                            }
                        }
                    }
                }

                // 爽约反驳提示
                NoticeBar {
                    width: parent.width
                    visible: page.detail && page.detail.noshow_target === page.detail.role
                    text: page.detail ? ("对方认定你爽约。如不认可，可在 " + (page.detail.appeal_deadline ? Util.tsShort(page.detail.appeal_deadline) : "") + " 前反驳：订单终止、不计爽约；逾期将按爽约处理并记入主页。") : ""
                    fg: Root.Theme.danger
                    bg: Root.Theme.dangerSoft
                }

                // 打卡记录
                Column {
                    width: parent.width
                    spacing: 6
                    Text {
                        visible: page.detail && page.detail.checkins.length > 0
                        text: "到达打卡记录"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: Root.Theme.text
                    }
                    Repeater {
                        model: page.detail ? page.detail.checkins : []
                        delegate: Text {
                            width: parent.width
                            text: (modelData.user_id === Session.myId ? "我" : "对方") + " 于 " + Util.tsShort(modelData.created_at) + " 打卡（可作为爽约争议证据）"
                            font.pixelSize: 12
                            color: Root.Theme.textSub
                        }
                    }
                }

                // 完成后评价
                AppButton {
                    width: parent.width
                    text: "⭐ 评价对方（展示在对方主页）"
                    variant: "secondary"
                    visible: page.detail && page.detail.status === "completed"
                    onClicked: reviewDlg.openDlg(page.runId)
                }

                // 举报
                AppButton {
                    width: parent.width
                    text: "🚩 举报（违规行为提交平台审核）"
                    variant: "ghost"
                    visible: page.detail && (page.detail.status === "confirmed" || page.detail.status === "completed")
                    onClicked: page.report()
                }

                // 操作按钮
                Column {
                    width: parent.width
                    spacing: 10
                    visible: page.detail && page.detail.status === "confirmed"

                    AppButton {
                        width: parent.width
                        text: page.detail && page.detail.role === "poster" ? "✅ 确认委托完成" : "已到集合点打卡（相认凭证）"
                        onClicked: page.detail && page.detail.role === "poster" ? page.complete() : page.checkin()
                    }
                    AppButton {
                        width: parent.width
                        text: "📍 到达打卡"
                        variant: "ghost"
                        visible: page.detail && page.detail.role === "receiver"
                        onClicked: page.checkin()
                    }
                    AppButton {
                        width: parent.width
                        text: "🌧 雨天终止订单（需对方同意）"
                        variant: "ghost"
                        onClicked: page.rainInit()
                    }
                    AppButton {
                        width: parent.width
                        text: page.detail && page.detail.noshow_target === page.detail.role ? "🛡 反驳（订单终止，不计爽约）" : "⚠️ 对方爽约，我要认定"
                        variant: page.detail && page.detail.noshow_target === page.detail.role ? "ghost" : "danger"
                        onClicked: page.noshows()
                    }
                }

                AppButton {
                    width: parent.width
                    text: "💬 与对方聊天"
                    variant: "secondary"
                    onClicked: {
                        if (page.detail && page.detail.chat_id) app.pushPage("ChatPage.qml", { chatId: page.detail.chat_id })
                        else Ui.toast("会话尚未建立")
                    }
                }
            }
        }
    }

    ReviewDialog {
        id: reviewDlg
        anchors.fill: parent
        z: 100
        onDone: load()
    }

    function canReplyRain() {
        if (!page.detail || !page.detail.rain_state) return false
        return (page.detail.role === "poster" && page.detail.rain_state === "requested_by_receiver") ||
               (page.detail.role === "receiver" && page.detail.rain_state === "requested_by_poster")
    }

    function report() {
        Ui.input({ title: "举报原因（5-200 字）", hint: "例如：对方辱骂/威胁、要求线下交易等" }, function (reason) {
            if (!reason) return
            if (reason.length < 5) { Ui.toast("请填写至少 5 字的原因"); return }
            Api.post("/api/active/" + page.runId + "/report", { reason: reason }).then(function (d) {
                Ui.toast(d.msg || "举报已提交")
            }).catch(function (e) { Ui.toast(e.msg) })
        })
    }

    function statusHint() {
        var d = page.detail
        if (d.status === "completed") return "本单已完成，记得互相评价；如有问题请与对方协商"
        if (d.status === "rain_cancelled") return "雨天双方同意，订单已终止"
        if (d.status === "cancelled") return "和解终止：爽约认定被反驳，订单终止（不计爽约）"
        if (d.status === "poster_noshows") return "挂单方爽约已认定并记入主页"
        if (d.status === "receiver_noshows") return "接单方爽约已认定并记入主页"
        if (d.status === "requested") return "等待挂单方确认（确认后进入进行中，费用线下当面结算）"
        if (d.rain_state) return "雨天终止请求已发出，对方 6 小时内未回复将自动同意终止"
        if (d.noshow_at) return "爽约认定处理中，对方可在 12 小时内反驳（反驳则订单终止）"
        return "请按约定时间前往集合，到达后双方打卡相认。"
    }

    function complete() {
        Ui.confirm({
            title: "确认委托完成？",
            text: "确认后订单进入进行中，请按约定时间赴约。费用在见面完成后由双方线下当面结算。",
            okText: "确认完成"
        }, function (ok) {
            if (!ok) return
            Ui.loading(true, "结算中...")
            Api.post("/api/active/" + page.runId + "/complete").then(function () {
                Ui.loading(false)
                Ui.toast("已完成，结算成功")
                load()
            }).catch(function (e) { Ui.loading(false); Ui.toast(e.msg) })
        })
    }

    function rainReply(agree) {
        Api.post("/api/active/" + page.runId + "/rain", { agree: agree }).then(function (d) {
            Ui.toast(agree ? "已同意终止" : "已拒绝")
            load()
        }).catch(function (e) { Ui.toast(e.msg) })
    }

    function rainInit() {
        Ui.confirm({
            title: "发起雨天终止？",
            text: "将通知对方，双方同意后订单终止；对方 6 小时未回复默认同意。",
            okText: "发起"
        }, function (ok) {
            if (!ok) return
            Api.post("/api/active/" + page.runId + "/rain", { agree: false }).then(function (d) {
                Ui.toast(d.msg || "已发起雨天终止请求")
                load()
            }).catch(function (e) { Ui.toast(e.msg) })
        })
    }

    function noshows() {
        if (page.detail.noshow_target === page.detail.role) {
            // 反驳：立即终止，不计爽约
            Ui.confirm({
                title: "反驳爽约认定？",
                text: "反驳后订单终止，不计爽约、不判定责任。双方可在聊天中自行协商。",
                okText: "反驳并终止",
                danger: true
            }, function (ok) {
                if (!ok) return
                Api.post("/api/active/" + page.runId + "/appeal", {}).then(function (d) {
                    Ui.toast(d.msg || "已反驳，订单已终止")
                    load()
                }).catch(function (e) { Ui.toast(e.msg) })
            })
        } else {
            // 认定对方爽约
            if (!page.detail.claimable) {
                Ui.toast("集合时间后 15 分钟才能发起爽约认定（集合后 24 小时内有效）")
                return
            }
            Ui.confirm({
                title: "认定对方爽约？",
                text: "请确认对方确实未在集合时间出现。对方 12 小时内可申诉，逾期按爽约规则结算；如对方已打卡，请谨慎操作。",
                okText: "认定爽约",
                danger: true
            }, function (ok) {
                if (!ok) return
                var target = page.detail.role === "poster" ? "receiver" : "poster"
                Api.post("/api/active/" + page.runId + "/noshows", { target: target }).then(function (d) {
                    Ui.toast(d.msg || "已提交爽约认定")
                    load()
                }).catch(function (e) { Ui.toast(e.msg) })
            })
        }
    }

    // 打卡：获取当前位置后上报（信号是 onPositionChanged —— 没有 onUpdate，
    // 之前在 Component.onCompleted 里 posSrc.onUpdate.connect 会 TypeError 炸断 onCompleted）
    PositionSource {
        id: posSrc
        updateInterval: 1000
        active: false
        onPositionChanged: {
            if (!page.waitingPos) return
            page.waitingPos = false
            active = false
            posCheckTimer.stop()
            Ui.loading(false)
            var p = posSrc.position
            if (!p.latitudeValid) { Ui.toast("定位失败，请确认已授权定位权限"); return }
            Api.post("/api/active/" + page.runId + "/checkin", { lat: p.coordinate.latitude, lon: p.coordinate.longitude }).then(function () {
                Ui.toast("打卡成功！已通知对方")
                load()
            }).catch(function (e) { Ui.toast(e.msg) })
        }
    }
    property bool waitingPos: false

    Component.onCompleted: {
        // load 放最前：保证后续任何语句异常都不会阻断详情加载
        load()
        page._unsubRun = Realtime.on("run", function (m) { if (m.run_id === page.runId) page.load() })
    }

    Component.onDestruction: if (page._unsubRun) page._unsubRun()

    // 打卡：先申请定位权限（Android 6+ 动态权限，此前从未请求 → 永远超时），授权后再取位置
    property bool waitingPerm: false
    function checkin() {
        page.waitingPerm = true
        Permissions.requestLocation()
    }
    Connections {
        target: Permissions
        function onLocationResult(granted) {
            if (!page.waitingPerm) return
            page.waitingPerm = false
            if (granted) page.beginCheckin()
            else Ui.toast("未获得定位权限，请在系统设置中允许定位后重试")
        }
    }
    function beginCheckin() {
        Ui.loading(true, "获取定位中...")
        page.waitingPos = true
        posSrc.active = true
        posSrc.update()
        posCheckTimer.start() // 6 秒超时
    }
    Timer {
        id: posCheckTimer
        interval: 6000
        repeat: false
        onTriggered: {
            if (page.waitingPos) {
                page.waitingPos = false
                posSrc.active = false
                Ui.loading(false)
                Ui.toast("定位超时，请稍后重试")
            }
        }
    }

    function load() {
        Api.get("/api/active/" + page.runId).then(function (d) {
            page.detail = d
        }).catch(function (e) { Ui.toast(e.msg) })
    }
}
