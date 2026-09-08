import QtQuick
import LeLeDaiPao 1.0
import QtQuick.Controls
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 进行中：已确认的跑单（含待我处理的接单申请）
Item {
    id: page
    property var app: null
    property var list: []
    property var pending: []
    property var _unsubs: null // Realtime 订阅注销函数列表

    Column {
        anchors.fill: parent

        AppHeader {
            title: "进行中"
            gradientBg: true
            rightText: "🔄"
            onRightClicked: page.load(true)
        }

        Item {
            width: parent.width
            height: parent.height - 52
        ListView {
            id: listView
            anchors.fill: parent
            clip: true
            spacing: 12
            topMargin: 10
            bottomMargin: 32
            leftMargin: 12
            rightMargin: 12
            boundsBehavior: Flickable.DragAndOvershootBounds

            header: PullToRefresh {
                id: pullRef
                onRefresh: function () { page.load(true) }
            }

            model: page.list.concat(page.pending)

            delegate: AppCard {
                id: activeCard
                property var run: modelData
                width: listView.width - 24
                height: cardCol.implicitHeight + 24
                tappable: modelData.status !== "requested"
                onClicked: app.pushPage("ActiveDetailPage.qml", { runId: modelData.id })

                Column {
                    id: cardCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 6
                        Text {
                            text: Util.relativeDate(modelData.date)
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Root.Theme.text
                        }
                        Text {
                            text: Util.hoursLabel(modelData.hours)
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: Root.Theme.text
                        }
                        Item { width: 4 }
                        TagBadge {
                            text: modelData.status === "requested" ? (modelData.role === "poster" ? "待我确认" : "待对方确认") : Util.runStatusCN(modelData.status)
                            fg: modelData.status === "requested" ? Root.Theme.warning : Root.Theme.blue
                            bg: modelData.status === "requested" ? Root.Theme.warningSoft : Root.Theme.blueSoft
                        }
                        Item { width: 6 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Util.yuan(modelData.price_cents) + "/次"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: Root.Theme.primary
                        }
                    }

                    Text {
                        width: parent.width
                        text: (modelData.playground || "") + " · " + modelData.remark
                        font.pixelSize: 12
                        color: Root.Theme.textSub
                        wrapMode: Text.Wrap
                        maximumLineCount: 1
                        elide: Text.ElideRight
                    }

                    Row {
                        width: parent.width
                        spacing: 8
                        Avatar {
                            size: 28
                            nickname: modelData.role === "poster" ? modelData.receiver.nickname : modelData.poster.nickname
                            photo: (modelData.role === "poster" ? modelData.receiver.avatar === 1 : modelData.poster.avatar === 1)
                            photoUrl: modelData.role === "poster"
                                ? (modelData.receiver.avatar === 1 ? Session.baseUrl + "/files/avatars/" + modelData.receiver.id + ".jpg" : "")
                                : (modelData.poster.avatar === 1 ? Session.baseUrl + "/files/avatars/" + modelData.poster.id + ".jpg" : "")
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (modelData.role === "poster" ? "接单方 " : "挂单方 ") + (modelData.role === "poster" ? modelData.receiver.nickname : modelData.poster.nickname)
                            font.pixelSize: 12
                            color: Root.Theme.textSub
                        }
                        Item { width: 4 }

                        // 待确认申请：操作按钮
                        Row {
                            visible: modelData.status === "requested" && modelData.role === "poster"
                            spacing: 8
                            Repeater {
                                model: [
                                    { l: "确认接单", a: "confirm", c: Root.Theme.primarySoft, tc: Root.Theme.primaryDark },
                                    { l: "拒绝", a: "reject", c: Root.Theme.dangerSoft, tc: Root.Theme.danger },
                                    { l: "私聊", a: "chat", c: "#EEF0F3", tc: Root.Theme.textSub }
                                ]
                                delegate: Rectangle {
                                    height: 28
                                    width: txt.implicitWidth + 16
                                    radius: 14
                                    color: modelData.c
                                    Text {
                                        id: txt
                                        anchors.centerIn: parent
                                        text: modelData.l
                                        font.pixelSize: 11
                                        color: modelData.tc
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: page.act(modelData.a, activeCard.run)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } // ListView

        EmptyState {
            anchors.centerIn: parent
            visible: page.list.length === 0 && page.pending.length === 0
            text: "暂无进行中的单"
            subText: "去「接单」页看看有没有合适的单吧"
        }
        } // 列表区
    }

    function act(action, run, card) {
        if (action === "confirm") {
            Api.post('/api/orders/requests/' + run.id + '/confirm').then(function () {
                Ui.toast('已确认，订单进入进行中')
                page.load(true)
            }).catch(function (e) { Ui.toast(e.msg) })
        } else if (action === "reject") {
            Ui.input({ title: "拒绝原因（必填）", hint: "请填写拒绝原因" }, function (reason) {
                if (!reason) { Ui.toast("拒绝需填写原因"); return }
                Api.post("/api/orders/requests/" + run.id + "/reject", { reason: reason }).then(function () {
                    Ui.toast("已拒绝")
                    page.load(true)
                }).catch(function (e) { Ui.toast(e.msg) })
            })
        } else if (action === "chat") {
            openChat(run)
        }
    }

    function openChat(run) {
        if (run.chat_id) { app.pushPage("ChatPage.qml", { chatId: run.chat_id }); return }
        Api.get("/api/chats").then(function (c) {
            var chat = c.list.find(function (x) { return x.order_id === run.order_id && x.other.id === (run.role === "poster" ? run.receiver.id : run.poster.id) })
            if (chat) app.pushPage("ChatPage.qml", { chatId: chat.id })
            else Ui.toast("会话尚未建立")
        }).catch(function (e) { Ui.toast(e.msg) })
    }

    function load(force) {
        Api.get("/api/active").then(function (d) {
            page.pending = d.list.filter(function (r) { return r.status === "requested" })
            page.list = d.list.filter(function (r) { return r.status !== "requested" })
            pullRef.finish()
        }).catch(function () {
            pullRef.finish()
        })
    }

    function refresh() { load(true) }

    Component.onCompleted: {
        load(true)
        // 登出时 Loader 卸载会销毁本页，handler 必须解除，否则重登后重复触发
        page._unsubs = [
            Realtime.on("run", function () { page.load(false) }),
            Realtime.on("chat", function () { page.load(false) }),
            Realtime.on("notif", function () { page.load(false) })
        ]
    }

    Component.onDestruction: {
        if (page._unsubs) for (var i = 0; i < page._unsubs.length; i++) page._unsubs[i]()
    }
}
