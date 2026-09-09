import QtQuick
import QtQuick.Controls
import LeLeDaiPao 1.0
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 挂单详情：完整信息 + 可接日期列表 + 接单申请
Item {
    id: page
    property var app: null
    property int orderId: 0
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
            title: "挂单详情"
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
                    height: infoCol.implicitHeight + 24
                    Column {
                        id: infoCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 8

                        Row {
                            width: parent.width
                            spacing: 6
                            Text {
                                text: page.detail ? page.detail.playground.name : ""
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: Root.Theme.text
                            }
                            TagBadge {
                                visible: page.detail && page.detail.gender_required !== "none"
                                text: page.detail && page.detail.gender_required === "male" ? "仅男" : "仅女"
                                fg: Root.Theme.danger
                                bg: Root.Theme.dangerSoft
                            }
                        }
                        Text {
                            width: parent.width
                            text: "委托内容：" + (page.detail ? page.detail.remark : "")
                            font.pixelSize: 14
                            color: Root.Theme.text
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            text: "期望报酬：" + Util.yuan(page.detail ? page.detail.price_cents : 0) + "/次"
                            font.pixelSize: 15
                            font.weight: Font.Bold
                            color: Root.Theme.primary
                        }
                        Text {
                            width: parent.width
                            text: "时间：" + (page.detail ? Util.slotsSummary(page.detail.slots) : "")
                            font.pixelSize: 13
                            color: Root.Theme.textSub
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            text: "挂单次数：" + (page.detail ? page.detail.run_count : "") + " 次（剩余 " + (page.detail ? page.detail.remaining : "") + " 次；每天最多安排一单，一天仅可选一个时间点）"
                            font.pixelSize: 13
                            color: Root.Theme.textSub
                            wrapMode: Text.Wrap
                        }
                        Row {
                            width: parent.width
                            spacing: 8
                            Avatar {
                                size: 40
                                nickname: page.detail ? page.detail.poster.nickname : ""
                                photo: page.detail && page.detail.poster.avatar === 1
                                photoUrl: page.detail && page.detail.poster.avatar === 1 ? Session.baseUrl + "/files/avatars/" + page.detail.poster.id + ".jpg" : ""
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    text: page.detail ? page.detail.poster.nickname : ""
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    color: Root.Theme.text
                                }
                                Text {
                                    text: page.detail ? (Util.genderCN(page.detail.poster.gender) + " · 完成 " + page.detail.poster.completed_count + " 单") : ""
                                    font.pixelSize: 11
                                    color: Root.Theme.textSub
                                }
                            }
                            Item { width: 4 }
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
                                    onClicked: app.pushPage("ProfilePage.qml", { userId: page.detail.poster.id })
                                }
                            }
                        }
                    }
                }

                // 集合说明
                NoticeBar {
                    width: parent.width
                    text: "集合说明：默认在操场常用门的右侧碰头。若操场有多个常用门，优先选择偏北的门；若仍相同，优先偏东。具体位置请与对方确认。"
                }

                // 可接日期
                Text {
                    text: "可选日期（选时间点后申请接单）"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: Root.Theme.text
                }

                Repeater {
                    model: page.detail ? page.detail.available_dates : []
                    delegate: AppCard {
                        id: dateCard
                        // 每个日期一张卡：日期标签 + 该日可接时间点多选 + 申请按钮
                        property var dayInfo: modelData
                        property var takenHours: page.myHoursOn(modelData.date)
                        property string selKey: "sel_" + modelData.date
                        width: parent.width
                        height: dateCol.implicitHeight + 24
                        Column {
                            id: dateCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 14
                            spacing: 8
                            Row {
                                width: parent.width
                                spacing: 6
                                Text {
                                    text: Util.dateLabel(modelData.date, modelData.weekday)
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    color: Root.Theme.text
                                }
                                Item { width: 2 }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: dateCard.takenHours.length > 0
                                    text: "我已接 " + dateCard.takenHours.join("、") + " 点"
                                    font.pixelSize: 11
                                    color: Root.Theme.primary
                                    font.weight: Font.Medium
                                }
                            }
                            Text {
                                width: parent.width
                                text: "选择你能到场的一个时间点（当天 " + modelData.hours.length + " 个可选，仅选 1 个）"
                                font.pixelSize: 11
                                color: Root.Theme.textSub
                            }
                            // 时间点单选 chips（Flow 自动换行，避免长列表把按钮挤出屏幕）：
                            // 一天仅可选一个时间点，点其他 chip 会切换选中
                            Flow {
                                width: parent.width
                                spacing: 8
                                Repeater {
                                    model: modelData.hours
                                    delegate: Rectangle {
                                        property int hourVal: modelData
                                        property bool mine: dateCard.takenHours.indexOf(hourVal) >= 0
                                        property bool picked: (page.sel[dateCard.selKey] || []).indexOf(hourVal) >= 0
                                        width: Math.max(66, chipCol.implicitWidth + 20); height: 32
                                        radius: 16
                                        color: mine ? "#E9EBEE" : (picked ? Root.Theme.primary : Root.Theme.primarySoft)
                                        border.color: picked ? Root.Theme.primary : Root.Theme.primaryLight
                                        border.width: 1
                                        Column {
                                            id: chipCol
                                            anchors.centerIn: parent
                                            spacing: 0
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: mine ? hourVal + ":00 已接" : hourVal + ":00"
                                                font.pixelSize: 12
                                                font.weight: picked ? Font.Medium : Font.Normal
                                                color: mine ? Root.Theme.textLight : (picked ? "#FFFFFF" : Root.Theme.primaryDark)
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                visible: !mine
                                                text: (hourVal - 1) + ":55 集合"
                                                font.pixelSize: 9
                                                color: picked ? Qt.rgba(1, 1, 1, 0.85) : Root.Theme.textLight
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: !mine
                                            onClicked: page.pickHour(dateCard.selKey, hourVal)
                                        }
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                text: "集合规则：提前 5 分钟到（如 18 点 = 17:55-18:00 集合），超过整点视为爽约"
                                font.pixelSize: 10
                                color: Root.Theme.textLight
                                wrapMode: Text.Wrap
                            }
                            Rectangle {
                                width: 132; height: 34
                                radius: 17
                                color: page.selCount(dateCard.selKey) > 0 ? Root.Theme.primary : "#F0F1F3"
                                Text {
                                    anchors.centerIn: parent
                                    text: page.selCount(dateCard.selKey) > 0 ? "接这单（" + page.sel[dateCard.selKey][0] + ":00）" : "接这单（先选时间）"
                                    font.pixelSize: 12
                                    color: page.selCount(dateCard.selKey) > 0 ? "#FFFFFF" : Root.Theme.textLight
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: page.take(dateCard.dayInfo, dateCard.selKey)
                                }
                            }
                        }
                    }
                }

                NoticeBar {
                    width: parent.width
                    text: "接单须知：每天最多接一单、一天仅可选一个时间点；某天任一时间点被接，当天其余时间点全部关闭，没人接则自动顺延到后续日期；挂单方确认后生效；费用线下当面结算。"
                    fg: Root.Theme.blue
                    bg: Root.Theme.blueSoft
                }
            }
        }
    }

    // 每个日期已选的时间点：{ "sel_2026-09-08": [20] }（单选，一天仅一个）
    property var sel: ({})

    function pickHour(key, hour) {
        var cur = (page.sel[key] || []).slice()
        // 单选：再点同一个取消，点别的直接切换
        var nextSel = (cur.indexOf(hour) >= 0) ? [] : [hour]
        var next = {}
        for (var k in page.sel) next[k] = page.sel[k]
        next[key] = nextSel
        page.sel = next
    }

    function selCount(key) {
        return (page.sel[key] || []).length
    }

    // 我在该日期已占用的时间点（requested/confirmed 才算，rejected 已释放）
    function myHoursOn(date) {
        if (!page.detail || !page.detail.my_runs) return []
        var out = []
        page.detail.my_runs.forEach(function (r) {
            if (r.date !== date || r.status === 'rejected') return
            JSON.parse(r.hours_json).forEach(function (h) { if (out.indexOf(h) < 0) out.push(h) })
        })
        return out.sort(function (a, b) { return a - b })
    }

    function take(dateInfo, selKey) {
        var hours = page.sel[selKey] || []
        if (!hours.length) { Ui.toast("请先选择要接的时间点"); return }
        if (page.busy) return
        page.busy = true
        Ui.loading(true, "提交中...")
        Api.post("/api/orders/" + page.orderId + "/take", { date: dateInfo.date, hours: hours }).then(function (d) {
            page.busy = false
            Ui.loading(false)
            var next = {}
            for (var k in page.sel) if (k !== selKey) next[k] = page.sel[k]
            page.sel = next
            Ui.toast("申请已提交，等待挂单方确认")
            load()
        }).catch(function (e) {
            page.busy = false
            Ui.loading(false)
            Ui.toast(e.msg)
        })
    }
    property bool busy: false

    function load() {
        Api.get("/api/orders/" + page.orderId).then(function (d) {
            page.detail = d
        }).catch(function (e) {
            Ui.toast(e.msg)
        })
    }

    Component.onCompleted: load()
}
