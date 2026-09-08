import QtQuick
import LeLeDaiPao 1.0
import QtQuick.Controls
import QtPositioning
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 私聊：挂单方 <-> 接单方。支持文字与位置（不支持图片，服务器带不动）；订单结束后记录自动清除
Item {
    id: page
    property var app: null
    property int chatId: 0
    property var messages: []
    property var other: null
    property var request: null
    property bool closed: false
    property string orderTitle: ""
    property var _unsubChat: null // Realtime 订阅注销函数，页面销毁时调用防泄漏

    // 不透底：推入详情栈后浮在 Tab 页之上，根必须有不透明背景，否则下层页面内容会透出来
    Rectangle {
        anchors.fill: parent
        color: Root.Theme.bg
    }

    Column {
        anchors.fill: parent

        AppHeader {
            showBack: true
            title: page.other ? page.other.nickname : "聊天"
            onBackClicked: app.popPage()
        }

        // 接单申请卡片（挂单方视角：确认/拒绝/私聊已打开即为此处）
        Rectangle {
            id: reqCard
            width: parent.width
            visible: page.request && page.request.run && page.request.run.status === "requested"
            height: 78
            color: Root.Theme.primarySoft
            clip: true
            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6
                Text {
                    text: page.request ? (page.request.order.playground + " · " + Util.relativeDate(page.request.run.date) + " " + Util.hoursLabel(page.request.run.hours) + " · 报酬 " + Util.yuan(page.request.order.price_cents) + "/次") : ""
                    font.pixelSize: 13
                    color: Root.Theme.text
                }
                Text {
                    text: "TA 想接这单，同意后进入进行中（费用线下当面结算）"
                    font.pixelSize: 11
                    color: Root.Theme.textSub
                }
                Row {
                    spacing: 8
                    Rectangle {
                        width: 76; height: 28
                        radius: 14
                        color: Root.Theme.primary
                        Text { anchors.centerIn: parent; text: "同意接单"; color: "#FFFFFF"; font.pixelSize: 11 }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Api.post('/api/orders/requests/' + page.request.run.id + '/confirm').then(function () {
                                           Ui.toast('已确认，订单进入进行中')
                                           page.loadRequest()
                                       }).catch(function (e) { Ui.toast(e.msg) })
                        }
                    }
                    Rectangle {
                        width: 60; height: 28
                        radius: 14
                        color: Root.Theme.dangerSoft
                        Text { anchors.centerIn: parent; text: "拒绝"; color: Root.Theme.danger; font.pixelSize: 11 }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Ui.input({ title: "拒绝原因（必填）", hint: "请填写拒绝原因" }, function (reason) {
                                    if (!reason) { Ui.toast("拒绝需填写原因"); return }
                                    Api.post("/api/orders/requests/" + page.request.run.id + "/reject", { reason: reason }).then(function () {
                                        Ui.toast("已拒绝")
                                        page.loadRequest()
                                    }).catch(function (e) { Ui.toast(e.msg) })
                                })
                            }
                        }
                    }
                }
            }
        }

        // 消息列表（高度 = 总高 - 头部52 - 申请卡(可见时78) - 底部输入栏56，少减 56 会把输入栏顶出屏幕）
        Item {
            width: parent.width
            height: parent.height - 52 - (reqCard.visible ? 78 : 0) - 56
            clip: true

            ListView {
                id: listView
                anchors.fill: parent
                spacing: 8
                topMargin: 10
                leftMargin: 12
                rightMargin: 12
                boundsBehavior: Flickable.StopAtBounds
                model: page.messages

                // 用户上翻查看历史时暂停粘底，拖动结束若仍在底部则恢复
                property bool stick: true
                onDragEnded: stick = atYEnd
                onCountChanged: page.scrollToEnd()
                onContentHeightChanged: page.scrollToEnd()

                // 注意：不能用 Loader+Component 按 modelData 选模板 —— Component 实例化后
                // 拿不到 delegate 作用域的 modelData（ReferenceError，气泡渲染成空壳）。
                // 单 delegate 内放两套布局，按消息类型切 visible（Positioner 会跳过隐藏项）
                delegate: Column {
                    width: listView.width - 24
                    spacing: 2

                    // 系统消息（sender_id=0）：居中灰字
                    Text {
                        visible: modelData.type === "system" || modelData.sender_id === 0
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.text
                        color: Root.Theme.textLight
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        lineHeight: 1.4
                    }

                    // 普通消息气泡：我的靠右（绿色），对方的靠左（白色）
                    Row {
                        id: bubbleRow
                        visible: !(modelData.type === "system" || modelData.sender_id === 0)
                        width: parent.width
                        layoutDirection: modelData.sender_id === Session.myId ? Qt.RightToLeft : Qt.LeftToRight
                        spacing: 8

                        Rectangle {
                            // 位置消息的坐标行比正文宽：气泡按两者较宽者取值，
                            // 否则自己(右侧)的气泡贴屏幕边时打开地图链接会被裁出屏幕外
                            width: modelData.type === "location"
                                   ? Math.max(bubbleText.implicitWidth + 24, locFlow.implicitWidth + 16)
                                   : Math.min(bubbleText.implicitWidth + 24, bubbleRow.width - 60)
                            height: bubbleCol.implicitHeight + 16
                            radius: 12
                            color: modelData.sender_id === Session.myId ? Root.Theme.primary : "#FFFFFF"
                            border.color: Root.Theme.line
                            border.width: modelData.sender_id === Session.myId ? 0 : 1
                            Column {
                                id: bubbleCol
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4
                                Text {
                                    id: bubbleText
                                    width: parent.width
                                    text: modelData.type === "location" ? ("📍 " + (modelData.text || "位置")) : modelData.text
                                    color: modelData.sender_id === Session.myId ? "#FFFFFF" : Root.Theme.text
                                    font.pixelSize: 14
                                    wrapMode: Text.Wrap
                                }
                                Flow {
                                    id: locFlow
                                    width: parent.width
                                    visible: modelData.type === "location"
                                    spacing: 6
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "坐标可在地图查看 ·"
                                        color: modelData.sender_id === Session.myId ? Qt.rgba(1,1,1,0.85) : Root.Theme.textSub
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "打开地图"
                                        color: modelData.sender_id === Session.myId ? "#FFFFFF" : Root.Theme.blue
                                        font.pixelSize: 12
                                        font.underline: true
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                var url = "https://uri.amap.com/marker?position=" + modelData.lon + "," + modelData.lat + "&name=集合点"
                                                Qt.openUrlExternally(url)
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: Util.tsHHMM(modelData.created_at)
                                    color: modelData.sender_id === Session.myId ? Qt.rgba(1,1,1,0.7) : Root.Theme.textLight
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }
                }
            } // ListView

        EmptyState {
            anchors.centerIn: parent
            visible: page.messages.length === 0 && !page.closed
            text: "开始聊点什么吧"
            subText: "可发送文字和位置；图片暂不支持。订单结束后记录自动清除。"
        }
        } // 消息区

        // 输入区
        Rectangle {
            id: inputBar
            width: parent.width
            height: 56
            color: "#FFFFFF"
            border.color: Root.Theme.line
            border.width: 1

            Row {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                Rectangle {
                    width: 42; height: 42
                    radius: 21
                    color: Root.Theme.primarySoft
                    Text { anchors.centerIn: parent; text: "📍"; font.pixelSize: 18 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: locationSheet.visible = true
                    }
                }
                TextField {
                    id: msgInput
                    width: parent.width - 42 - 56 - 24
                    height: 42
                    padding: 10
                    font.pixelSize: 14
                    placeholderText: "输入消息..."
                    placeholderTextColor: Root.Theme.textLight
                    background: Rectangle {
                        radius: 21
                        color: "#F5F6F8"
                    }
                    Keys.onReturnPressed: page.send()
                }
                AppButton {
                    width: 56
                    heightPx: 42
                    text: "发送"
                    onClicked: page.send()
                }
            }
        }
    }

    // 位置发送面板（自绘弹层：Qt Popup 在部分真机上 open() 无反应，弃用 Sheet）
    Rectangle {
        id: locationSheet
        anchors.fill: parent
        visible: false
        z: 300
        color: Qt.rgba(0, 0, 0, 0.35)
        MouseArea { anchors.fill: parent } // 拦截穿透点击
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(340, parent.width - 48)
            height: locCol.implicitHeight + 44
            radius: 16
            color: "#FFFFFF"
            Column {
                id: locCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 12
                Text {
                    text: "发送位置"
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    color: Root.Theme.text
                }
                AppButton {
                    width: parent.width
                    text: "发送我的当前位置"
                    onClicked: { locationSheet.visible = false; page.sendLocation() }
                }
                Text {
                    width: parent.width
                    text: "位置信息用于碰头找对方，请描述准确。"
                    color: Root.Theme.textLight
                    font.pixelSize: 11
                }
            }
        }
    }

    function renderMsg(m) {
        if (m.type === "system" || m.sender_id === 0) return m.text
        if (m.type === "location") return "📍 位置：" + (m.text || "")
        return m.text
    }

    // 滚动到底部：delegates 异步实例化，model 刚赋值时 contentHeight 还是 0，
    // 直接 positionViewAtEnd 会停在列表顶部（聊天记录"打开不在底部"的根因），
    // 必须等布局完成后再滚（onCountChanged/onContentHeightChanged + callLater 双保险）
    function scrollToEnd() {
        if (!listView.stick) return
        Qt.callLater(function () { listView.positionViewAtEnd() })
    }

    function send() {
        var t = msgInput.text.trim()
        if (!t) return
        msgInput.text = ""
        listView.stick = true
        Api.post("/api/chats/" + page.chatId + "/messages", { type: "text", text: t }).then(function (d) {
            page.messages.push(d.m)
            page.messages = page.messages.slice()
            page.scrollToEnd()
        }).catch(function (e) { Ui.toast(e.msg) })
    }

    // 定位发送（信号是 onPositionChanged —— 没有 onUpdate 这个信号，
    // 之前在 Component.onCompleted 里 posSrc.onUpdate.connect 会 TypeError，
    // 把 onCompleted 从中间炸断：load() 和 Realtime 订阅全都不执行）
    PositionSource {
        id: posSrc
        updateInterval: 1000
        active: false
        onPositionChanged: {
            if (!page.waitingPos) return
            page.waitingPos = false
            active = false
            posTimer.stop()
            Ui.loading(false)
            var p = posSrc.position
            if (!p.latitudeValid) { Ui.toast("定位失败，请确认定位权限"); return }
            Api.post("/api/chats/" + page.chatId + "/messages", {
                type: "location", text: "我的位置", lat: p.coordinate.latitude, lon: p.coordinate.longitude
            }).then(function () { page.load() }).catch(function (e) { Ui.toast(e.msg) })
        }
    }
    property bool waitingPos: false
    // 发位置：先申请定位权限（Android 6+ 动态权限），授权后再取位置
    property bool waitingPerm: false
    function sendLocation() {
        page.waitingPerm = true
        Permissions.requestLocation()
    }
    Connections {
        target: Permissions
        function onLocationResult(granted) {
            if (!page.waitingPerm) return
            page.waitingPerm = false
            if (granted) page.beginSendLocation()
            else Ui.toast("未获得定位权限，请在系统设置中允许定位后重试")
        }
    }
    function beginSendLocation() {
        Ui.loading(true, "获取定位中...")
        page.waitingPos = true
        posSrc.active = true
        posSrc.update()
        posTimer.start()
    }
    Timer {
        id: posTimer
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

    Component.onCompleted: {
        // load 放最前：保证后续任何语句异常都不会阻断聊天记录加载
        load()
        // 记录注销函数：页面销毁时解除订阅，否则每推入一次就多一份 handler，
        // 同一条实时消息会被重复 push N 次（还会跨页面实例重复触发）
        page._unsubChat = Realtime.on("chat", function (m) {
            if (m.chat_id === page.chatId) {
                page.messages.push(m.m)
                page.messages = page.messages.slice()
                page.scrollToEnd()
                Api.post("/api/chats/" + page.chatId + "/read")
            }
        })
    }

    Component.onDestruction: if (page._unsubChat) page._unsubChat()

    function loadRequest() {
        Api.get("/api/chats/" + page.chatId + "/request").then(function (d) {
            page.request = d
        }).catch(function () {})
    }

    function load() {
        // 消息记录：GET /api/chats/{id}/messages（此前误调不存在的 /api/chats/{id}，
        // 服务器 404 -> 记录永远为空，只有 WS 实时消息能显示）
        listView.stick = true // 打开会话总是定位到最新一条
        Api.get("/api/chats/" + page.chatId + "/messages").then(function (d) {
            page.messages = d.list
            page.closed = d.closed
            page.scrollToEnd()
            Api.post("/api/chats/" + page.chatId + "/read")
        }).catch(function (e) { Ui.toast(e.msg) })
        loadRequest()
        // 对方信息
        Api.get("/api/chats").then(function (c) {
            var chat = c.list.find(function (x) { return x.id === page.chatId })
            if (chat) { page.other = chat.other; page.orderTitle = chat.remark }
        }).catch(function () {})
    }
}
