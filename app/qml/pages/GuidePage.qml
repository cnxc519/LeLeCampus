import QtQuick
import ".." as Root
import "../components"

// 使用指南（"我的"页可随时查看）
Item {
    id: page
    property var app: null

    // 不透底：GuidePage 推入详情栈后浮在 Tab 页之上，根必须有不透明背景，
    // 否则卡片之间的缝隙会把下层页面的文字透出来
    Rectangle {
        anchors.fill: parent
        color: Root.Theme.bg
    }

    component SectionCard: Rectangle {
        property string icon: ""
        property string title: ""
        property var lines: []
        width: parent.width
        radius: 14
        color: "#FFFFFF"
        height: content.implicitHeight + 28
        Column {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 8
            Text {
                text: icon + " " + title
                font.pixelSize: 15
                font.weight: Font.Bold
                color: Root.Theme.text
            }
            Column {
                width: parent.width
                spacing: 6
                Repeater {
                    model: lines
                    delegate: Text {
                        width: parent.width
                        text: modelData
                        color: Root.Theme.textSub
                        font.pixelSize: 13
                        wrapMode: Text.Wrap
                        lineHeight: 1.5
                    }
                }
            }
        }
    }

    Column {
        anchors.fill: parent

        AppHeader {
            showBack: true
            title: "使用指南"
            onBackClicked: app.popPage()
        }

        Flickable {
            width: parent.width
            height: parent.height - 52
            contentHeight: col.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                width: parent.width - 32
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                SectionCard { icon: "📋"; title: "挂单方流程"; lines: [
                    "1. 「挂单」页选择操场与委托内容（集合点：默认操场常用门右侧，多个常用门优先偏北、再偏东）",
                    "2. 周时间表选择所需时段（可拖拽连选；9 点 = 8:55-9:00 集合，超过 9 点视为爽约）",
                    "3. 设置挂单次数（系统保证各次安排在不同日期）",
                    "4. 收到接单申请后：确认 / 拒绝（须填原因）/ 私聊",
                    "5. 按约定时间集合，双方凭头像照片相认",
                    "6. 点「委托完成」确认订单完成；雨天可双方同意终止订单"
                ] }
                SectionCard { icon: "🏃"; title: "接单方流程"; lines: [
                    "1. 「接单」页浏览挂单（可按操场/时间筛选，性别不符的挂单自动隐藏）",
                    "2. 选日期申请接单（同一时间点最多同时接 5 单）",
                    "3. 挂单方确认后按时赴约，到达后记得「打卡」",
                    "4. 完成代跑：挂单方确认完成，费用线下当面结算",
                    "5. 若对方爽约：集合后 15 分钟可发起认定，对方 12 小时内未反驳即生效"
                ] }
                SectionCard { icon: "💰"; title: "金额约定与结算"; lines: [
                    "· 平台不代收任何费用，无充值、无支付、无提现",
                    "· 挂单时填写「期望金额」（每单报酬，不低于 1.99 元），列表可按金额排序",
                    "· 期望金额仅作双方参考：完成委托后线下当面结算，具体可自行协商",
                    "· 雨天双方同意可终止订单，不产生任何费用",
                    "· 挂单方爽约/接单方爽约：次数记入主页展示，不涉及金钱",
                    "· 请按时赴约，准时是最大的信任"
                ] }
                SectionCard { icon: "📚"; title: "书市（另一种模式）"; lines: [
                    "· 底部「模式切换条」可随时在 代跑互助 / 二手书市 之间切换",
                    "· 卖书：切到书市后点「卖书」，填书名/课程/价格，可加封面，卖出后点「标记已售出」",
                    "· 买书：在「书市」搜索书名或课程，点进详情联系卖家，「消息」页继续聊",
                    "· 书市同样不碰钱：价格面议，见面当面验书付款"
                ] }
                SectionCard { icon: "🎁"; title: "邀请好友"; lines: [
                    "· 邀请码在「邀请」页或注册时填写",
                    "· 邀请同学一起用，互帮互助更安心",
                    "· 快把邀请码分享给同学吧"
                ] }
                SectionCard { icon: "🔒"; title: "交易安全"; lines: [
                    "· 到达集合点建议双方打卡，作为爽约争议证据",
                    "· 被认定爽约可在 12 小时内反驳：订单终止、不计爽约（双方自行协商）",
                    "· 聊天支持发送位置，不支持图片；订单结束后聊天记录自动清除",
                    "· 请勿在聊天中透露密码等敏感信息"
                ] }

                // 明确的退出按钮：看完指南一键返回（顶部 ‹ 同样可返回）
                AppButton {
                    text: "‹ 返回"
                    variant: "secondary"
                    heightPx: 46
                    onClicked: app.popPage()
                }
            }
        }
    }
}