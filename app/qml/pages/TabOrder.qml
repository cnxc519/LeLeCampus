import QtQuick
import LeLeDaiPao 1.0
import QtQuick.Controls
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 接单：全部挂单列表（筛选条件保存在本地，直到用户修改）
Item {
    id: page
    property var app: null

    property var list: []
    property int listPage: 1
    property bool hasMore: false
    property bool loading: false
    property var playgrounds: []
    property int unread: 0
    property var _unsubs: null // Realtime 订阅注销函数列表

    // 筛选与排序（本地持久化，用户不改就一直生效；sort: smart 智能 / price_desc 金额从高到低 / price_asc 从低到高）
    property var filters: Session.filterJson.length > 0 ? JSON.parse(Session.filterJson) : { playground_id: 0, days: [], min_hour: 0, max_hour: 23, sort: "smart" }

    function saveFilters() {
        Session.setFilterJson(JSON.stringify(page.filters))
    }

    Component.onCompleted: {
        load(true)
        loadPlaygrounds()
        loadUnread()
        // 实时刷新（登出时 Loader 卸载会销毁本页，handler 必须解除，否则重登后重复触发）
        page._unsubs = [
            Realtime.on("notif", function () { page.loadUnread() }),
            Realtime.on("order", function () { page.load(true) }),
            Realtime.on("run", function () { page.load(true) })
        ]
        pageTimer.start()
    }

    Component.onDestruction: {
        if (page._unsubs) for (var i = 0; i < page._unsubs.length; i++) page._unsubs[i]()
    }
    Timer {
        id: pageTimer
        interval: 30000
        repeat: true
        onTriggered: { if (page.visible) page.load(false); page.loadUnread() }
    }

    function loadUnread() {
        Api.get("/api/notifications").then(function (d) { page.unread = d.unread }).catch(function () {})
    }

    function loadPlaygrounds() {
        Api.get("/api/schools").then(function (d) {
            if (d.list.length > 0) page.playgrounds = d.list[0].playgrounds
        }).catch(function () {})
    }

    function load(reset) {
        if (page.loading) return
        if (reset) { page.listPage = 1 }
        page.loading = true
        var q = "/api/orders?page=" + page.listPage
        if (page.filters.playground_id) q += "&playground_id=" + page.filters.playground_id
        if (page.filters.days && page.filters.days.length) q += "&days=" + page.filters.days.join(",")
        if (page.filters.min_hour > 0) q += "&min_hour=" + page.filters.min_hour
        if (page.filters.max_hour < 23) q += "&max_hour=" + page.filters.max_hour
        if (page.filters.sort) q += "&sort=" + page.filters.sort
        Api.get(q).then(function (d) {
            page.loading = false
            if (reset) page.list = []
            page.list = page.list.concat(d.list)
            page.hasMore = d.has_more
            pullRef.finish()
        }).catch(function (e) {
            page.loading = false
            pullRef.finish()
            if (reset) Ui.toast(e.msg)
        })
    }

    function loadMore() {
        if (!page.hasMore || page.loading) return
        page.listPage++
        load(false)
    }

    function hasTimeFilter() {
        return page.filters.days.length > 0 || page.filters.min_hour > 0 || page.filters.max_hour < 23
    }

    // ---------- 界面 ----------
    Rectangle {
        anchors.fill: parent
        gradient: Root.Theme.pageGradient
    }

    Column {
        id: headCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        // ---------- Hero 头图 ----------
        Item {
            width: parent.width
            height: 118
            Rectangle {
                anchors.fill: parent
                gradient: Root.Theme.brandGradient
                // 装饰光斑
                Rectangle {
                    width: 220; height: 220; radius: 110
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -70
                    anchors.topMargin: -110
                    color: "#14FFFFFF"
                }
                Rectangle {
                    width: 120; height: 120; radius: 60
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: 20
                    anchors.topMargin: -60
                    color: "#0DFFFFFF"
                }
                Rectangle {
                    width: 160; height: 160; radius: 80
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: -60
                    anchors.bottomMargin: -90
                    color: "#0AFFFFFF"
                }
            }

            // 标题文案
            Column {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                Text {
                    text: "接单广场"
                    font.pixelSize: 25
                    font.weight: Font.Bold
                    color: "#FFFFFF"
                }
                Text {
                    text: "帮同学跑一趟 · 顺手赚杯奶茶钱"
                    font.pixelSize: 12
                    color: "#E0FFFFFF"
                }
            }

            // 通知铃铛
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 38; height: 38
                radius: 19
                color: "#26FFFFFF"
                Text {
                    anchors.centerIn: parent
                    text: "🔔"
                    font.pixelSize: 16
                }
                Rectangle {
                    visible: page.unread > 0
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -4
                    anchors.rightMargin: -4
                    width: 17; height: 17
                    radius: 8.5
                    color: "#FF3B30"
                    border.color: "#FFFFFF"
                    border.width: 1.5
                    Text {
                        anchors.centerIn: parent
                        text: page.unread > 99 ? "99" : page.unread
                        color: "#FFFFFF"
                        font.pixelSize: 8
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: app.pushPage("NotificationsPage.qml", {})
                }
            }
        }

        // ---------- 筛选 + 排序 合一卡片 ----------
        AppCard {
            width: parent.width - 24
            anchors.horizontalCenter: parent.horizontalCenter
            height: 106
            Column {
                anchors.fill: parent
                anchors.margins: 11
                spacing: 7

                // 第一行：操场 chips（可横向滚动）+ 时间
                Row {
                    width: parent.width
                    spacing: 8
                    Rectangle {
                        width: 64; height: 32
                        radius: 16
                        color: page.hasTimeFilter() ? Root.Theme.primary : "#F1F3F5"
                        Text {
                            anchors.centerIn: parent
                            text: "⏱ 时间"
                            font.pixelSize: 11
                            font.weight: page.hasTimeFilter() ? Font.Medium : Font.Normal
                            color: page.hasTimeFilter() ? "#FFFFFF" : Root.Theme.textSub
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: timeSheet.open()
                        }
                    }
                    Flickable {
                        width: parent.width - 72
                        height: 32
                        contentWidth: chipsRow.width
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: chipsRow
                            spacing: 8
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: page.playgrounds
                                delegate: Rectangle {
                                    height: 32
                                    width: txt.implicitWidth + 20
                                    radius: 16
                                    color: page.filters.playground_id === modelData.id ? Root.Theme.primary : "#F1F3F5"
                                    Text {
                                        id: txt
                                        anchors.centerIn: parent
                                        text: modelData.name
                                        font.pixelSize: 12
                                        color: page.filters.playground_id === modelData.id ? "#FFFFFF" : Root.Theme.textSub
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            page.filters.playground_id = (page.filters.playground_id === modelData.id) ? 0 : modelData.id
                                            page.saveFilters()
                                            page.load(true)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Root.Theme.line
                }

                // 第二行：排序
                Row {
                    width: parent.width
                    height: 30
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "排序"
                        color: Root.Theme.textLight
                        font.pixelSize: 11
                    }
                    Repeater {
                        model: [
                            { v: "smart", l: "✨ 智能推荐" },
                            { v: "price_desc", l: "金额 高→低" },
                            { v: "price_asc", l: "金额 低→高" }
                        ]
                        delegate: Rectangle {
                            height: 30
                            anchors.verticalCenter: parent.verticalCenter
                            width: sortTxt.implicitWidth + 16
                            radius: 15
                            color: (page.filters.sort || "smart") === modelData.v ? Root.Theme.primarySoft : "transparent"
                            border.color: (page.filters.sort || "smart") === modelData.v ? Root.Theme.primaryLight : "transparent"
                            border.width: 1
                            Text {
                                id: sortTxt
                                anchors.centerIn: parent
                                text: modelData.l
                                font.pixelSize: 11
                                font.weight: (page.filters.sort || "smart") === modelData.v ? Font.Medium : Font.Normal
                                color: (page.filters.sort || "smart") === modelData.v ? Root.Theme.primaryDark : Root.Theme.textSub
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    page.filters.sort = modelData.v
                                    page.saveFilters()
                                    page.load(true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------- 列表区（占满剩余高度） ----------
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headCol.bottom
        anchors.bottom: parent.bottom

        ListView {
            id: listView
            anchors.fill: parent
            clip: true
            model: page.list
            spacing: 10
            topMargin: 4
            bottomMargin: 8
            leftMargin: 12
            rightMargin: 12
            boundsBehavior: Flickable.DragAndOvershootBounds

            header: PullToRefresh {
                id: pullRef
                onRefresh: function () { page.load(true); page.loadUnread() }
            }

            onAtYEndChanged: if (atYEnd) page.loadMore()

            delegate: AppCard {
                width: listView.width - 24
                height: cardCol.implicitHeight + 24
                tappable: true
                onClicked: app.pushPage("OrderDetailPage.qml", { orderId: modelData.id })

                Column {
                    id: cardCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 13
                    spacing: 8

                    // 标题行：操场 + 性别/时效标签
                    Row {
                        width: parent.width
                        spacing: 6
                        Text {
                            text: modelData.playground.name
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Root.Theme.text
                            width: Math.min(implicitWidth, parent.width - 210)
                            elide: Text.ElideRight
                        }
                        TagBadge {
                            visible: modelData.gender_required !== "none"
                            text: modelData.gender_required === "male" ? "👦 仅男" : "👧 仅女"
                            fg: Root.Theme.danger
                            bg: Root.Theme.dangerSoft
                        }
                        Item { width: 2 }
                        TagBadge {
                            visible: modelData.avail_today || modelData.avail_tomorrow
                            text: "今明可接"
                            fg: Root.Theme.primaryDark
                            bg: Root.Theme.primarySoft
                        }
                    }

                    Text {
                        width: parent.width
                        text: modelData.remark
                        font.pixelSize: 13
                        color: Root.Theme.text
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                    }

                    Text {
                        width: parent.width
                        text: "🕐 " + Util.slotsSummary(modelData.slots)
                        font.pixelSize: 11
                        color: Root.Theme.textSub
                    }

                    // 底部行：挂单人 + 可接余量 …… 右侧报酬渐变签
                    Item {
                        width: parent.width
                        height: 28
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Avatar {
                                size: 26
                                nickname: modelData.poster.nickname
                                photo: modelData.poster.avatar === 1
                                photoUrl: modelData.poster.avatar === 1 ? Session.baseUrl + "/files/avatars/" + modelData.poster.id + ".jpg" : ""
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.poster.nickname
                                font.pixelSize: 12
                                color: Root.Theme.textSub
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "· 可接 " + modelData.avail_count + " 格 · 剩 " + modelData.remaining + " 次"
                                font.pixelSize: 11
                                color: Root.Theme.primaryDark
                                font.weight: Font.Medium
                            }
                        }
                        // 报酬渐变签（线下当面结算）
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: 26
                            width: chipTxt.implicitWidth + 14
                            radius: 13
                            gradient: Root.Theme.brandGradient
                            Row {
                                id: chipTxt
                                anchors.centerIn: parent
                                spacing: 2
                                Text {
                                    text: Util.yuan(modelData.price_cents)
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                    color: "#FFFFFF"
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "/次"
                                    font.pixelSize: 9
                                    color: "#D9FFFFFF"
                                }
                            }
                        }
                    }
                }
            }

            // 底部加载提示
            footer: Column {
                width: listView.width - 24
                visible: page.list.length > 0
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: page.hasMore ? "上拉加载更多..." : "已加载全部"
                    color: Root.Theme.textLight
                    font.pixelSize: 11
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "报酬见面当面结 · 平台不碰钱"
                    color: Root.Theme.textLight
                    font.pixelSize: 9
                }
            }
        }

        EmptyState {
            anchors.centerIn: parent
            anchors.topMargin: -30
            visible: page.list.length === 0 && !page.loading
            text: page.hasTimeFilter() || page.filters.playground_id ? "没有符合条件的挂单" : "暂时没有可接的挂单"
            subText: "试试放宽筛选条件，或换个操场看看"
        }
    }

    // ---------- 时间筛选 ----------
    Sheet {
        id: timeSheet
        title: "筛选时间（可多选星期 + 时间范围）"
        enableDone: true
        contentH: 430
        onDoneClicked: { timeSheet.close(); page.saveFilters(); page.load(true) }

        Column {
            width: parent.width
            spacing: 14
            padding: 16

            Text { text: "星期（不选 = 不限）"; color: Root.Theme.textSub; font.pixelSize: 12 }
            Flow {
                width: parent.width
                spacing: 8
                Repeater {
                    model: ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
                    delegate: Rectangle {
                        width: 56; height: 32
                        radius: 16
                        color: page.filters.days.indexOf(index) >= 0 ? Root.Theme.primary : "#F0F1F3"
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 12
                            color: page.filters.days.indexOf(index) >= 0 ? "#FFFFFF" : Root.Theme.textSub
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                var idx = page.filters.days.indexOf(index)
                                if (idx >= 0) page.filters.days.splice(idx, 1)
                                else page.filters.days.push(index)
                                page.filters = JSON.parse(JSON.stringify(page.filters)) // 新引用触发界面刷新
                                page.saveFilters()
                            }
                        }
                    }
                }
            }

            Text { text: "最早时间（" + page.filters.min_hour + "点起）"; color: Root.Theme.textSub; font.pixelSize: 12 }
            Flickable {
                width: parent.width
                height: 34
                contentWidth: hourChips1.width
                clip: true
                Row {
                    id: hourChips1
                    spacing: 6
                    Repeater {
                        model: 16
                        delegate: Rectangle {
                            width: 44; height: 30
                            radius: 15
                            color: page.filters.min_hour === index + 8 ? Root.Theme.primary : "#F0F1F3"
                            Text {
                                anchors.centerIn: parent
                                text: (index + 8) + "点"
                                font.pixelSize: 11
                                color: page.filters.min_hour === index + 8 ? "#FFFFFF" : Root.Theme.textSub
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var h = index + 8
                                    page.filters.min_hour = Math.min(h, page.filters.max_hour)
                                    if (page.filters.min_hour > page.filters.max_hour) page.filters.max_hour = h
                                    page.saveFilters()
                                }
                            }
                        }
                    }
                }
            }

            Text { text: "最晚时间（" + (page.filters.max_hour === 23 ? "23点" : page.filters.max_hour + "点") + "截止）"; color: Root.Theme.textSub; font.pixelSize: 12 }
            Flickable {
                width: parent.width
                height: 34
                contentWidth: hourChips2.width
                clip: true
                Row {
                    id: hourChips2
                    spacing: 6
                    Repeater {
                        model: 16
                        delegate: Rectangle {
                            width: 44; height: 30
                            radius: 15
                            color: page.filters.max_hour === index + 8 ? Root.Theme.primary : "#F0F1F3"
                            Text {
                                anchors.centerIn: parent
                                text: (index + 8) + "点"
                                font.pixelSize: 11
                                color: page.filters.max_hour === index + 8 ? "#FFFFFF" : Root.Theme.textSub
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var h = index + 8
                                    page.filters.max_hour = Math.max(h, page.filters.min_hour)
                                    if (page.filters.max_hour < page.filters.min_hour) page.filters.min_hour = h
                                    page.saveFilters()
                                }
                            }
                        }
                    }
                }
            }

            AppButton {
                width: parent.width
                text: "重置时间筛选"
                variant: "ghost"
                onClicked: {
                    page.filters.days = []
                    page.filters.min_hour = 0
                    page.filters.max_hour = 23
                    page.saveFilters()
                }
            }
        }
    }
}
