import QtQuick
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 历史记录：挂单记录(role=poster) / 接单记录(role=receiver)
Item {
    id: page
    property var app: null
    property string role: "poster"
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
            title: page.role === "poster" ? "挂单记录" : "接单记录"
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
            spacing: 8
            topMargin: 10
            leftMargin: 12
            rightMargin: 12
            bottomMargin: 12
            delegate: AppCard {
                width: listView.width - 24
                height: col.implicitHeight + 20
                Column {
                    id: col
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 6
                    Row {
                        width: parent.width
                        spacing: 6
                        Text {
                            text: Util.relativeDate(modelData.date) + " " + Util.hoursLabel(modelData.hours)
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: Root.Theme.text
                        }
                        Item { width: 4 }
                        TagBadge {
                            text: Util.runStatusCN(modelData.status)
                            fg: modelData.status === "completed" ? Root.Theme.primaryDark : (modelData.status.indexOf("noshows") >= 0 ? Root.Theme.danger : Root.Theme.textSub)
                            bg: modelData.status === "completed" ? Root.Theme.primarySoft : (modelData.status.indexOf("noshows") >= 0 ? Root.Theme.dangerSoft : "#EEF0F3")
                        }
                    }
                    Text {
                        width: parent.width
                        text: (modelData.playground || "") + " · " + modelData.remark
                        font.pixelSize: 12
                        color: Root.Theme.textSub
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        width: parent.width
                        visible: modelData.status === "rejected" && modelData.reject_reason
                        text: "拒绝原因：" + modelData.reject_reason
                        font.pixelSize: 11
                        color: Root.Theme.warning
                    }
                    Text {
                        width: parent.width
                        text: (page.role === "poster" ? "接单方：" : "挂单方：") + modelData.other.nickname
                        font.pixelSize: 11
                        color: Root.Theme.textLight
                    }
                    // 完成订单可评价对方
                    Rectangle {
                        width: 92; height: 30
                        radius: 15
                        color: Root.Theme.primarySoft
                        visible: modelData.status === "completed"
                        Text {
                            anchors.centerIn: parent
                            text: "⭐ 评价对方"
                            font.pixelSize: 12
                            color: Root.Theme.primaryDark
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: reviewDlg.openDlg(modelData.id)
                        }
                    }
                }
            }
        } // ListView

        EmptyState {
            anchors.centerIn: parent
            visible: page.list.length === 0
            text: page.role === "poster" ? "还没有挂单记录" : "还没有接单记录"
        }
        } // 列表区
    }

    function load() {
        Api.get("/api/me/history?role=" + page.role).then(function (d) {
            page.list = d.list
        }).catch(function (e) { Ui.toast(e.msg) })
    }

    ReviewDialog {
        id: reviewDlg
        anchors.fill: parent
        z: 100
        onDone: load()
    }

    Component.onCompleted: load()
}
