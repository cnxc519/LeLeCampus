import QtQuick
import QtQuick.Controls
import LeLeDaiPao 1.0
import ".." as Root
import "../components"

// 首次进入：挂单/接单总流程 + 付钱收钱流程引导（注册后显示一次，可在"我的-使用指南"重新查看）
Item {
    id: page
    property var app: null

    Rectangle {
        anchors.fill: parent
        gradient: Root.Theme.pageGradient
    }

    property int step: 0
    property var slides: [
        {
            icon: "📋",
            title: "挂单方怎么用",
            caption: "把跑腿需求挂出来，等同学接单",
            lines: [
                "1. 在「挂单」页选择操场、委托内容",
                "2. 在周时间表上选出你需要的时段（可拖拽连选），设置挂单次数",
                "3. 发布后，同学们会看到并申请接单",
                "4. 收到申请后：确认（进入进行中）或拒绝（需填写原因）",
                "5. 按约定时间在操场集合，见面后把东西交给TA",
                "6. 确认「委托完成」，费用线下当面结算"
            ]
        },
        {
            icon: "🏃",
            title: "接单方怎么用",
            caption: "浏览挂单，接下顺路的一单",
            lines: [
                "1. 在「接单」页浏览挂单，可筛选操场和时间",
                "2. 选择具体日期申请接单（同一时间点最多同时接 5 单）",
                "3. 挂单方确认后，按约定时间赴约（9 点 = 8:55-9:00 集合，超过 9 点视为爽约）",
                "4. 完成代跑后，由挂单方确认完成，费用线下当面结算",
                "5. 到达集合点记得「打卡」，双方相认看对方头像照片"
            ]
        },
        {
            icon: "💰",
            title: "见面与结算",
            caption: "平台不碰钱，一切当面来",
            lines: [
                "· 平台不代收任何费用",
                "· 双方按约定时间在操场集合，委托完成后面当面结算（费用由双方自行约定）",
                "· 建议见面时核对对方头像照片，确认是本人",
                "· 雨天双方同意可终止订单，不产生任何费用",
                "· 爽约会被记入主页，请务必准时赴约"
            ]
        },
        {
            icon: "🎁",
            title: "邀请好友",
            caption: "和同学一起，互帮互助更安心",
            lines: [
                "· 注册时填写邀请码，或从「邀请」页分享你的邀请码",
                "· 邀请同学一起用，互帮互助更安心",
                "· 快把邀请码分享给同学，一起互帮互助吧！"
            ]
        }
    ]

    Column {
        anchors.fill: parent
        spacing: 0

        AppHeader {
            showBack: false
            title: "使用流程"
            gradientBg: true
            rightText: page.step === page.slides.length - 1 ? "" : "跳过"
            onRightClicked: page.finish()
        }

        Item {
            width: parent.width
            height: parent.height - 52 - 104
            clip: false

            Column {
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 16

                // 渐变徽章：图标 + 光晕
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 116; height: 116
                    radius: 58
                    color: "#1AFFFFFF"
                    Rectangle {
                        anchors.centerIn: parent
                        width: 100; height: 100
                        radius: 50
                        gradient: Root.Theme.brandGradient
                        Text {
                            anchors.centerIn: parent
                            text: page.slides[page.step].icon
                            font.pixelSize: 44
                        }
                        // 顶部高光
                        Rectangle {
                            width: 56; height: 56; radius: 28
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.leftMargin: 12
                            anchors.topMargin: 6
                            color: "#1FFFFFFF"
                        }
                    }
                }

                // 标题 + 一句话说明
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: page.slides[page.step].title
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        color: Root.Theme.text
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: page.slides[page.step].caption
                        font.pixelSize: 12
                        color: Root.Theme.textLight
                    }
                }

                // 要点卡片
                AppCard {
                    width: parent.width
                    height: tipCol.implicitHeight + 24
                    Column {
                        id: tipCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 10
                        Repeater {
                            model: page.slides[page.step].lines
                            delegate: Row {
                                width: parent.width
                                spacing: 8
                                property bool num: /^\d/.test(modelData)
                                Rectangle {
                                    width: 20; height: 20
                                    radius: 10
                                    visible: parent.num
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Root.Theme.primarySoft
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.charAt(0)
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Root.Theme.primaryDark
                                    }
                                }
                                Text {
                                    width: 18
                                    visible: !parent.num
                                    text: "·"
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                    color: Root.Theme.primary
                                }
                                Text {
                                    width: parent.width - (parent.num ? 28 : 26)
                                    text: modelData.slice(2)
                                    color: Root.Theme.textSub
                                    font.pixelSize: 13
                                    wrapMode: Text.Wrap
                                    lineHeight: 1.5
                                }
                            }
                        }
                    }
                }
            }
        }

        // 底部：进度点 + 下一步
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 92
            spacing: 16
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 7
                Repeater {
                    model: page.slides.length
                    delegate: Rectangle {
                        width: page.step === index ? 22 : 7
                        height: 7
                        radius: 3.5
                        color: page.step === index ? Root.Theme.primary : "#D9DEE2"
                        Behavior on width { NumberAnimation { duration: 160 } }
                    }
                }
            }
            AppButton {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.step === page.slides.length - 1 ? "开始使用" : "下一步"
                width: 220
                heightPx: 50
                onClicked: {
                    if (page.step < page.slides.length - 1) page.step++
                    else page.finish()
                }
            }
        }
    }

    function finish() {
        Session.setOnboardingDone(true)
        app.popPage()
        app.currentTab = "order"
    }
}
