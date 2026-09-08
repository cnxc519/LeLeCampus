import QtQuick
import LeLeDaiPao 1.0
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 消息通知（铃铛入口）：接单申请（确认/拒绝/私聊）、雨天请求、爽约认定等带操作的通知
Item {
    id: page
    property var app: null
    property var list: []

    // 不透底：推入详情栈后浮在 Tab 页之上，根必须有不透明背景，否则下层页面内容会透出来
    Rectangle {
        anchors.fill: parent
        color: Root.Theme.bg
    }

    Column {
        anchors.fill: parent

        AppHeader {
            showBack: true
            title: "消息通知"
            onBackClicked: app.popPage()
        }

        Item {
            width: parent.width
            height: parent.height - 52
            ListView {
                id: listView
                anchors.fill: parent
                clip: true
                model: page.list
                spacing: 10
                topMargin: 10
                bottomMargin: 16
                leftMargin: 12
                rightMargin: 12

                delegate: AppCard {
                    width: listView.width - 24
                    height: col.implicitHeight + 24
                    Column {
                        id: col
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8
                        property var outerN: modelData

                        Text {
                            width: parent.width
                            text: modelData.title
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: Root.Theme.text
                            wrapMode: Text.Wrap
                        }
                        Text {
                            text: Util.tsShort(modelData.created_at)
                            font.pixelSize: 11
                            color: Root.Theme.textLight
                        }
                        Text {
                            width: parent.width
                            text: modelData.body
                            font.pixelSize: 12
                            color: Root.Theme.textSub
                            wrapMode: Text.Wrap
                            lineHeight: 1.45
                        }

                        // 操作区
                        Row {
                            width: parent.width
                            visible: page.actionsFor(modelData).length > 0
                            spacing: 8
                            Repeater {
                                model: page.actionsFor(modelData)
                                delegate: Rectangle {
                                    height: 32
                                    width: txt.implicitWidth + 20
                                    radius: 16
                                    color: modelData.kind === "danger" ? Root.Theme.dangerSoft : Root.Theme.primarySoft
                                    Text {
                                        id: txt
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.pixelSize: 12
                                        color: modelData.kind === "danger" ? Root.Theme.danger : Root.Theme.primaryDark
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        // 必须用 id 限定引用 col.outerN：裸写 outerN 在嵌套 Repeater
                                        // delegate 里无法解析（ReferenceError），点击会静默失效
                                        onClicked: page.doAction(modelData.action, col.outerN)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: page.list.length === 0
                text: "暂无消息"
            }
        }
    }

    function actionsFor(n) {
        if (n.type === "take_request") return [{ label: "同意接单", action: "confirm", kind: "primary" }, { label: "拒绝", action: "reject", kind: "danger" }, { label: "私聊", action: "chat", kind: "ghost" }]
        if (n.type === "rain_request") return [{ label: "同意终止", action: "rain_agree", kind: "primary" }, { label: "拒绝", action: "rain_decline", kind: "danger" }]
        if (n.type === "noshows_claimed") return [{ label: "反驳（终止订单）", action: "appeal", kind: "primary" }]
        if (n.type === "book_contact" || n.type === "book_msg") return [{ label: "去回复", action: "book_chat", kind: "primary" }]
        return []
    }

    function runIdOf(n) {
        var d = n.data_json ? JSON.parse(n.data_json) : {}
        return d.run_id || 0
    }

    function doAction(action, n) {
        // REST 返回 data_json（字符串），实时推送是 data（对象），两者都兼容
        var raw = n.data_json || n.data
        var d = raw ? (typeof raw === "string" ? JSON.parse(raw) : raw) : {}
        var runId = d.run_id || 0
        if (action === "confirm") {
            Api.post('/api/orders/requests/' + runId + '/confirm').then(function () {
                Ui.toast('已确认，订单进入进行中')
                Api.post("/api/notifications/read", { id: n.id })
                load()
            }).catch(function (e) { Ui.toast(e.msg) })
        } else if (action === "reject") {
            Ui.input({ title: "拒绝原因（必填）", hint: "请填写拒绝原因" }, function (reason) {
                if (!reason) { Ui.toast("拒绝需填写原因"); return }
                Api.post("/api/orders/requests/" + runId + "/reject", { reason: reason }).then(function () {
                    Ui.toast("已拒绝该申请")
                    Api.post("/api/notifications/read", { id: n.id })
                    load()
                }).catch(function (e) { Ui.toast(e.msg) })
            })
        } else if (action === "chat") {
            // 找与对方的会话
            Api.get("/api/chats").then(function (c) {
                var chat = c.list.find(function (x) { return x.order_id === d.order_id && x.other.id === d.receiver_id })
                if (chat) app.pushPage("ChatPage.qml", { chatId: chat.id })
                else Ui.toast("会话尚未建立")
            }).catch(function (e) { Ui.toast(e.msg) })
        } else if (action === "rain_agree" || action === "rain_decline") {
            Ui.confirm({
                title: action === "rain_agree" ? "同意雨天终止？" : "拒绝雨天终止？",
                text: action === "rain_agree" ? "双方同意后订单终止（无线上费用，对方 6 小时未回复将自动同意）。" : "拒绝后订单按原计划进行，将通知对方。",
                okText: action === "rain_agree" ? "同意" : "拒绝",
                danger: action === "rain_decline"
            }, function (ok) {
                if (!ok) return
                Api.post("/api/active/" + runId + "/rain", { agree: action === "rain_agree" }).then(function () {
                    Ui.toast(action === "rain_agree" ? "已同意，订单终止" : "已拒绝")
                    Api.post("/api/notifications/read", { id: n.id })
                    load()
                }).catch(function (e) { Ui.toast(e.msg) })
            })
        } else if (action === "appeal") {
            Ui.confirm({
                title: "反驳爽约认定？",
                text: "反驳后订单终止，不计爽约、不判定责任，双方自行协商。",
                okText: "反驳并终止",
                danger: true
            }, function (ok) {
                if (!ok) return
                Api.post("/api/active/" + runId + "/appeal", {}).then(function () {
                    Ui.toast("已反驳，订单已终止")
                    Api.post("/api/notifications/read", { id: n.id })
                    load()
                }).catch(function (e) { Ui.toast(e.msg) })
            })
        } else if (action === "book_chat") {
            var d2 = n.data_json ? JSON.parse(n.data_json) : {}
            if (!d2.chat_id) { Ui.toast("会话不存在"); return }
            app.pushPage("BookChatPage.qml", { chatId: d2.chat_id })
            Api.post("/api/notifications/read", { id: n.id })
            load()
        }
    }

    function load() {
        Api.get("/api/notifications").then(function (d) {
            page.list = d.list
        }).catch(function (e) { Ui.toast(e.msg) })
    }

    property var _unsubNotif: null

    Component.onCompleted: {
        load()
        // 打开通知页即全部标为已读（红点清零），无需逐条点操作按钮
        Api.post("/api/notifications/read", {})
        // 页面停留时收到新通知即时刷新（登出/销毁必须注销，防止重复触发）
        page._unsubNotif = Realtime.on("notif", function () { page.load() })
    }

    Component.onDestruction: if (page._unsubNotif) page._unsubNotif()
}
