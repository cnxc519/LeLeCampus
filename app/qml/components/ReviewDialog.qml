import QtQuick
import QtQuick.Controls
import ".." as Root
import "../js/api.js" as Api
import "../js/ui.js" as Ui

// 订单完成后的互评弹窗（星级 + 文字，展示在对方主页）
Item {
    id: root
    visible: false
    property int runId: 0
    property int score: 5
    property bool busy: false
    signal done()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
        visible: root.visible
    }

    function openDlg(runId) {
        root.runId = runId
        root.score = 5
        commentInput.text = ""
        root.visible = true
    }
    function closeDlg() { root.visible = false }

    Rectangle {
        anchors.centerIn: parent
        width: 310
        radius: 16
        color: "#FFFFFF"
        visible: root.visible

        Column {
            anchors.fill: parent
            padding: 20
            spacing: 12

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "评价对方"
                font.pixelSize: 17
                font.weight: Font.Bold
                color: Root.Theme.text
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "这次代跑体验怎么样？评价会展示在对方主页"
                font.pixelSize: 12
                color: Root.Theme.textSub
            }

            // 星级
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Repeater {
                    model: 5
                    delegate: Text {
                        text: index < root.score ? "★" : "☆"
                        font.pixelSize: 34
                        color: index < root.score ? "#FFB800" : "#D8DBDF"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.score = index + 1
                        }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ["", "很差", "较差", "一般", "满意", "非常满意"][root.score]
                color: Root.Theme.textSub
                font.pixelSize: 12
            }

            TextArea {
                id: commentInput
                width: parent.width - 40
                height: 76
                anchors.horizontalCenter: parent.horizontalCenter
                padding: 10
                placeholderText: "补充评价（选填，200 字以内）"
                placeholderTextColor: Root.Theme.textLight
                font.pixelSize: 13
                wrapMode: TextEdit.Wrap
                background: Rectangle {
                    radius: 10
                    color: "#F5F6F8"
                    border.color: "#D9DDE3"
                }
            }

            Row {
                width: parent.width - 40
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                AppButton {
                    width: (parent.width - 10) / 2
                    heightPx: 40
                    text: "取消"
                    variant: "ghost"
                    onClicked: root.closeDlg()
                }
                AppButton {
                    width: (parent.width - 10) / 2
                    heightPx: 40
                    text: root.busy ? "提交中..." : "提交评价"
                    busy: root.busy
                    onClicked: root.submit()
                }
            }
        }
    }

    function submit() {
        if (root.busy) return
        root.busy = true
        Api.post("/api/active/" + root.runId + "/review", { score: root.score, comment: commentInput.text.trim() }).then(function () {
            root.busy = false
            Ui.toast("评价成功，感谢反馈")
            root.closeDlg()
            root.done()
        }).catch(function (e) {
            root.busy = false
            Ui.toast(e.msg)
        })
    }
}
