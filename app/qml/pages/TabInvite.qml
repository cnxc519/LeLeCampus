import QtQuick
import QtQuick.Controls
import LeLeDaiPao 1.0
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 邀请：邀请码 + 已邀请好友（纯互助推荐，无经济奖励）
Item {
    id: page
    property var app: null
    property var detail: null // 注意：不能叫 data —— 那是 Item 内置默认属性（存子对象），遮蔽它会静默丢弃整棵 UI 树

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

            // 邀请码卡片
            AppCard {
                width: parent.width
                height: 190
                color: Root.Theme.primary
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "我的邀请码"
                        color: Qt.rgba(1, 1, 1, 0.8)
                        font.pixelSize: 13
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: page.detail ? page.detail.invite_code : "--------"
                        color: "#FFFFFF"
                        font.pixelSize: 32
                        font.weight: Font.Bold
                        font.letterSpacing: 4
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 120; height: 36
                        radius: 18
                        color: "#FFFFFF"
                        Text {
                            anchors.centerIn: parent
                            text: "📋 复制邀请码"
                            color: Root.Theme.primaryDark
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Clipboard.text = page.detail.invite_code
                                Ui.toast("邀请码已复制，快分享给同学吧！")
                            }
                        }
                    }
                }
            }

            // 已邀请人数
            AppCard {
                width: parent.width
                height: 76
                Column {
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        text: page.detail ? String(page.detail.invited_count) : "0"
                        color: Root.Theme.blue
                        font.pixelSize: 22
                        font.weight: Font.Bold
                    }
                    Text {
                        text: "已邀请的同学"
                        color: Root.Theme.textSub
                        font.pixelSize: 12
                    }
                }
            }

            // 说明
            AppCard {
                width: parent.width
                height: rules.implicitHeight + 24
                Column {
                    id: rules
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 8
                    Text {
                        text: "🎁 邀请说明"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        color: Root.Theme.text
                    }
                    Text {
                        width: parent.width
                        text: "· 把邀请码发给同学，TA 注册时填写后即为好友关系"
                        color: Root.Theme.textSub
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                        lineHeight: 1.5
                    }
                    Text {
                        width: parent.width
                        text: "· 和朋友一起用乐乐代跑，互相帮忙更安心～"
                        color: Root.Theme.textSub
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                        lineHeight: 1.5
                    }
                }
            }

            // 好友列表
            Text {
                text: "我邀请的同学"
                font.pixelSize: 15
                font.weight: Font.Bold
                color: Root.Theme.text
            }
            Repeater {
                model: page.detail ? page.detail.friends : []
                delegate: AppCard {
                    width: parent.width
                    height: 56
                    Row {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10
                        Avatar {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 36
                            nickname: modelData.nickname
                            photo: modelData.avatar === 1
                            photoUrl: modelData.avatar === 1 ? Session.baseUrl + "/files/avatars/" + modelData.id + ".jpg" : ""
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text {
                                text: modelData.nickname
                                font.pixelSize: 13
                                color: Root.Theme.text
                            }
                            Text {
                                text: Util.tsShort(modelData.created_at) + " 加入"
                                font.pixelSize: 11
                                color: Root.Theme.textLight
                            }
                        }
                    }
                }
            }
            EmptyState {
                width: parent.width
                visible: page.detail && page.detail.friends.length === 0
                text: "还没有邀请同学"
                subText: "把邀请码分享给室友，一起互帮互助吧"
            }
        }
    }

    function refresh() { load() }

    function load() {
        Api.get("/api/invite").then(function (d) {
            page.detail = d
        }).catch(function () {})
    }

    Component.onCompleted: load()
}
