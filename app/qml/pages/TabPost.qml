import QtQuick
import LeLeDaiPao 1.0
import QtQuick.Controls
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 挂单：发布新挂单（操场/内容/周时间表/次数/性别要求）+ 我的挂单列表
Item {
    id: page
    property var app: null

    property var playgrounds: []
    property int playgroundId: 0
    property var myOrders: []

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 116
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width - 32
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            spacing: 14

            // ---------- 发布区 ----------
            AppCard {
                width: parent.width
                height: form.implicitHeight + 24
                Column {
                    id: form
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 12

                    Text {
                        text: "发布新挂单"
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        color: Root.Theme.text
                    }

                    // 操场
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: "操场（必选）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                        Flow {
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: page.playgrounds
                                delegate: Rectangle {
                                    height: 34
                                    width: txt.implicitWidth + 20
                                    radius: 17
                                    color: page.playgroundId === modelData.id ? Root.Theme.primary : "#F0F1F3"
                                    Text {
                                        id: txt
                                        anchors.centerIn: parent
                                        text: modelData.name
                                        font.pixelSize: 13
                                        color: page.playgroundId === modelData.id ? "#FFFFFF" : Root.Theme.textSub
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: page.playgroundId = modelData.id
                                    }
                                }
                            }
                        }
                        Text {
                            text: "集合说明：默认在操场常用门的右侧碰头；若操场有多个常用门，优先选择偏北的门，若仍相同则偏东。"
                            color: Root.Theme.warning
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            width: parent.width
                        }
                    }

                    // 委托内容
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: "委托内容（必填）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                        AppTextArea {
                            id: remarkInput
                            width: parent.width
                            height: 80
                            text: "乐跑2km"
                            hint: "例如：帮我去菜鸟驿站取快递，送到松园操场（告诉TA取件码）"
                        }
                    }

                    // 期望金额（每次报酬；平台不代收，线下当面结算）
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: "期望金额（每单报酬，必填）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                        Row {
                            width: parent.width
                            spacing: 10
                            Rectangle {
                                width: 52; height: 48
                                radius: Root.Theme.radiusBtn
                                color: Root.Theme.primarySoft
                                Text { anchors.centerIn: parent; text: "¥"; font.pixelSize: 18; font.weight: Font.Bold; color: Root.Theme.primaryDark }
                            }
                            AppInput {
                                id: priceInput
                                width: parent.width - 62
                                hint: "如 5.00（不低于 1.99 元）"
                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                onTextChanged: {
                                    var v = priceInput.text.replace(/[^0-9.]/g, '')
                                    if (v.split('.').length > 2) v = v.slice(0, v.length - 1)
                                    if (v !== priceInput.text) priceInput.text = v
                                }
                            }
                        }
                        Row {
                            spacing: 8
                            Repeater {
                                model: ["2", "3", "5", "8", "10"]
                                delegate: Rectangle {
                                    height: 28
                                    width: chipTxt.implicitWidth + 16
                                    radius: 14
                                    color: Root.Theme.primarySoft
                                    Text {
                                        id: chipTxt
                                        anchors.centerIn: parent
                                        text: "¥" + modelData
                                        font.pixelSize: 11
                                        color: Root.Theme.primaryDark
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: priceInput.text = modelData
                                    }
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "元/次"
                                color: Root.Theme.textLight
                                font.pixelSize: 11
                            }
                        }
                        Text {
                            width: parent.width
                            text: "金额仅作双方约定参考，平台不代收任何费用：见面完成委托后，由你当面付给对方。"
                            color: Root.Theme.warning
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                    }

                    // 时间选择
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: "选择时间段（点按选择 / 拖拽连选，已选 " + grid.count() + " 格）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                        NoticeBar {
                            width: parent.width
                            text: "时间说明：9 点格表示 8:55-9:00 集合，超过 9 点视为爽约。"
                        }
                        WeekGrid {
                            id: grid
                            width: parent.width
                            height: 200
                            clip: true
                            onChanged: {}
                        }
                        Text {
                            width: parent.width
                            text: "已选：" + (grid.count() > 0 ? Util.slotsSummary(grid.toSlots()) : "尚未选择")
                            color: grid.count() > 0 ? Root.Theme.primaryDark : Root.Theme.textLight
                            font.pixelSize: 12
                        }
                    }

                    // 挂单次数
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: "挂单次数（同一时间点只安排一人，各时间点可分别被接）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                        Row {
                            spacing: 12
                            Rectangle {
                                width: 36; height: 36
                                radius: 18
                                color: Root.Theme.primarySoft
                                Text { anchors.centerIn: parent; text: "−"; color: Root.Theme.primaryDark; font.pixelSize: 18 }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: page.runCount = Math.max(1, page.runCount - 1)
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: page.runCount + " 次"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                color: Root.Theme.text
                            }
                            Rectangle {
                                width: 36; height: 36
                                radius: 18
                                color: Root.Theme.primarySoft
                                Text { anchors.centerIn: parent; text: "+"; color: Root.Theme.primaryDark; font.pixelSize: 18 }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: page.runCount = Math.min(30, page.runCount + 1)
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "默认 5 次"
                                color: Root.Theme.textLight
                                font.pixelSize: 11
                            }
                        }
                    }

                    // 接单者性别要求
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: "接单者性别要求（选择后仅该性别用户可见并接单）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                        Row {
                            spacing: 8
                            Repeater {
                                model: [{ v: "none", l: "不限" }, { v: "male", l: "仅男" }, { v: "female", l: "仅女" }]
                                delegate: Rectangle {
                                    width: 78; height: 36
                                    radius: 10
                                    color: page.genderReq === modelData.v ? Root.Theme.primarySoft : "#F0F1F3"
                                    border.color: page.genderReq === modelData.v ? Root.Theme.primary : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.l
                                        font.pixelSize: 13
                                        color: page.genderReq === modelData.v ? Root.Theme.primaryDark : Root.Theme.textSub
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: page.genderReq = modelData.v
                                    }
                                }
                            }
                        }
                    }

                    AppButton {
                        width: parent.width
                        text: "发布挂单"
                        onClicked: page.publish()
                    }
                }
            }

            // ---------- 我的挂单 ----------
            Text {
                text: "我的挂单（" + page.myOrders.length + "）"
                font.pixelSize: 15
                font.weight: Font.Bold
                color: Root.Theme.text
            }

            Repeater {
                model: page.myOrders
                delegate: AppCard {
                    width: parent.width
                    height: myCol.implicitHeight + 20
                    Column {
                        id: myCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 6
                        Row {
                            width: parent.width
                            spacing: 6
                            Text {
                                text: modelData.playground.name
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: Root.Theme.text
                            }
                            TagBadge {
                                visible: modelData.gender_required !== "none"
                                text: modelData.gender_required === "male" ? "仅男" : "仅女"
                                fg: Root.Theme.danger
                                bg: Root.Theme.dangerSoft
                            }
                            Item { width: 4 }
                            TagBadge { text: "剩 " + modelData.remaining + " 次" }
                            Item { width: 6 }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Util.yuan(modelData.price_cents) + "/次"
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                color: Root.Theme.primary
                            }
                            Item { width: parent.width - 10; height: 1 }
                        }
                        Text {
                            width: parent.width
                            text: modelData.remark
                            font.pixelSize: 12
                            color: Root.Theme.textSub
                            wrapMode: Text.Wrap
                            maximumLineCount: 1
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: "时间：" + Util.slotsSummary(modelData.slots) + " · 可接 " + modelData.avail_count + " 格"
                            font.pixelSize: 12
                            color: Root.Theme.textSub
                        }
                        Row {
                            width: parent.width
                            spacing: 8
                            Rectangle {
                                height: 28; width: 72
                                radius: 14
                                color: Root.Theme.blueSoft
                                Text {
                                    anchors.centerIn: parent
                                    text: "查看详情"
                                    font.pixelSize: 12
                                    color: Root.Theme.blue
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: app.pushPage("OrderDetailPage.qml", { orderId: modelData.id })
                                }
                            }
                            Rectangle {
                                height: 28; width: 72
                                radius: 14
                                color: Root.Theme.dangerSoft
                                visible: modelData.remaining > 0
                                Text {
                                    anchors.centerIn: parent
                                    text: "取消挂单"
                                    font.pixelSize: 12
                                    color: Root.Theme.danger
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: page.cancelOrder(modelData)
                                }
                            }
                        }
                    }
                }
            }

            EmptyState {
                width: parent.width
                visible: page.myOrders.length === 0
                text: "还没有挂单"
                subText: "在上面发布你的第一个挂单吧"
            }
        }
    }

    property int runCount: 5
    property string genderReq: "none"

    function publish() {
        if (!page.playgroundId) { Ui.toast("请选择操场"); return }
        var remark = remarkInput.text.trim()
        if (!remark) { Ui.toast("请填写委托内容"); return }
        var priceCents = Util.yuanToCents(priceInput.text)
        if (isNaN(priceCents) || priceCents < 199) { Ui.toast("期望金额不能低于 1.99 元"); return }
        if (priceCents > 99999) { Ui.toast("金额过大（最多 999.99 元）"); return }
        var slots = grid.toSlots()
        if (slots.length === 0) { Ui.toast("请选择至少一个时间段"); return }

        Ui.confirm({
            title: "确认发布挂单？",
            text: "操场/内容如上，期望金额 ¥" + Util.fen2yuan(priceCents) + "/次，共 " + slots.length + " 个时段，挂单 " + page.runCount + " 次（同学按日期+时间点申请，你确认后生效）。费用线下当面结算，发布后同学即可申请接单。",
            okText: "确认发布"
        }, function (ok) {
            if (!ok) return
            Ui.loading(true, "发布中...")
            Api.post("/api/orders", {
                playground_id: page.playgroundId,
                remark: remark,
                price_cents: priceCents,
                slots: slots,
                run_count: page.runCount,
                gender_required: page.genderReq
            }).then(function () {
                Ui.loading(false)
                Ui.toast("发布成功！等待同学接单")
                grid.clear()
                remarkInput.text = ""
                priceInput.text = ""
                loadMy()
            }).catch(function (e) {
                Ui.loading(false)
                Ui.toast(e.msg)
            })
        })
    }

    function cancelOrder(o) {
        Ui.confirm({
            title: "取消该挂单？",
            text: "取消后所有待处理申请将关闭。已有确认中的跑单不可取消。",
            okText: "取消挂单",
            danger: true
        }, function (ok) {
            if (!ok) return
            Api.post("/api/orders/" + o.id + "/cancel").then(function () {
                Ui.toast("已取消")
                loadMy()
            }).catch(function (e) { Ui.toast(e.msg) })
        })
    }

    function loadMy() {
        Api.get("/api/orders/mine").then(function (d) {
            page.myOrders = d.list
        }).catch(function () {})
    }

    function refresh() { loadPlaygrounds(); loadMy() }

    function loadPlaygrounds() {
        Api.get("/api/schools").then(function (d) {
            if (d.list.length > 0) {
                page.playgrounds = d.list[0].playgrounds
                if (!page.playgroundId && page.playgrounds.length > 0) page.playgroundId = page.playgrounds[0].id
            }
        }).catch(function () {})
    }

    Component.onCompleted: {
        loadPlaygrounds()
        loadMy()
        Realtime.on("order", function () { page.loadMy() })
        Realtime.on("run", function () { page.loadMy() })
    }
}
