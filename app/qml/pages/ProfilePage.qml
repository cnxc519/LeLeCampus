import QtQuick
import LeLeDaiPao 1.0
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 用户主页（查看挂单者/接单者信息）：代跑数据 + 二手书市数据
Item {
    id: page
    property var app: null
    property int userId: 0
    property var user: null

    // 不透底：推入详情栈后浮在 Tab 页之上，根必须有不透明背景，否则下层页面内容会透出来
    Rectangle {
        anchors.fill: parent
        color: Root.Theme.bg
    }

    Column {
        anchors.fill: parent

        AppHeader {
            showBack: true
            title: "个人主页"
            onBackClicked: app.popPage()
        }

        // 内容较长（资料 + 书市 + 评价），必须可滚动；此前固定居中布局已溢出
        Flickable {
            width: parent.width
            height: parent.height - 52
            contentHeight: col.implicitHeight + 30
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 48
                y: 8
                spacing: 14

                Avatar {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: 84
                    nickname: page.user ? page.user.nickname : ""
                    photo: page.user && page.user.avatar === 1
                    photoUrl: page.user && page.user.avatar === 1 ? Session.baseUrl + "/files/avatars/" + page.user.id + ".jpg" : ""
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: page.user ? page.user.nickname : ""
                    font.pixelSize: 18
                    font.weight: Font.Bold
                    color: Root.Theme.text
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: page.user && page.user.photo !== undefined && page.user.avatar === 1
                    text: "照片用于双方相认，见面请核对本人"
                    font.pixelSize: 11
                    color: Root.Theme.warning
                }

                AppCard {
                    width: parent.width
                    height: stats.implicitHeight + 24
                    Grid {
                        id: stats
                        anchors.fill: parent
                        anchors.margins: 14
                        columns: 3
                        columnSpacing: 8
                        rowSpacing: 12
                        property int itemW: (parent.width - 16) / 3
                        Repeater {
                            model: [
                                { v: page.user ? String(page.user.completed_count) : "0", l: "完成代跑" },
                                { v: page.user ? String(page.user.no_show_count) : "0", l: "接单爽约" },
                                { v: page.user ? String(page.user.no_show_count_poster) : "0", l: "挂单爽约" }
                            ]
                            delegate: Column {
                                width: stats.itemW
                                spacing: 4
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.v
                                    font.pixelSize: 18
                                    font.weight: Font.Bold
                                    color: Root.Theme.text
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.l
                                    font.pixelSize: 11
                                    color: Root.Theme.textSub
                                }
                            }
                        }
                    }
                }

                AppCard {
                    width: parent.width
                    height: 50
                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        Text {
                            text: "性别"
                            font.pixelSize: 13
                            color: Root.Theme.textSub
                        }
                        Text {
                            anchors.right: parent.right
                            text: page.user ? Util.genderCN(page.user.gender) : ""
                            font.pixelSize: 13
                            color: Root.Theme.text
                        }
                    }
                }
                AppCard {
                    width: parent.width
                    height: 50
                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        Text {
                            text: "学校"
                            font.pixelSize: 13
                            color: Root.Theme.textSub
                        }
                        Text {
                            anchors.right: parent.right
                            text: page.user ? page.user.school : ""
                            font.pixelSize: 13
                            color: Root.Theme.text
                        }
                    }
                }
                AppCard {
                    width: parent.width
                    height: 50
                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        Text {
                            text: "注册时间"
                            font.pixelSize: 13
                            color: Root.Theme.textSub
                        }
                        Text {
                            anchors.right: parent.right
                            text: page.user ? page.user.created_at.slice(0, 10) : ""
                            font.pixelSize: 13
                            color: Root.Theme.text
                        }
                    }
                }

                // ---------- 二手书市 ----------
                Column {
                    width: parent.width
                    spacing: 10
                    visible: page.user && (page.user.books_on > 0 || page.user.books_sold > 0)

                    Row {
                        width: parent.width
                        spacing: 8
                        Text {
                            text: "TA 的二手书市"
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: Root.Theme.text
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.user ? ("在售 " + page.user.books_on + " 本 · 已售出 " + page.user.books_sold + " 本") : ""
                            font.pixelSize: 11
                            color: Root.Theme.primary
                            font.weight: Font.Medium
                        }
                    }

                    Repeater {
                        model: page.user ? page.user.books : []
                        delegate: AppCard {
                            width: parent.width
                            height: 62
                            tappable: modelData.status === "on"
                            onClicked: app.pushPage("BookDetailPage.qml", { bookId: modelData.id })

                            Row {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10
                                // 封面小图（无图用图标占位）
                                Rectangle {
                                    id: bookCover
                                    width: 34; height: 42
                                    radius: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: modelData.photo ? "transparent" : Root.Theme.primarySoft
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        visible: modelData.photo === 1
                                        source: Session.baseUrl + "/files/books/" + modelData.id + ".jpg"
                                        fillMode: Image.PreserveAspectCrop
                                    }
                                    Text { anchors.centerIn: parent; visible: modelData.photo !== 1; text: "📖"; font.pixelSize: 15 }
                                }
                                Column {
                                    // Row 内子项禁止 right/fill 等锚定（会使 Row 整体放弃布局、全部叠回原点），
                                    // 价格靠自然流式排到最右，这里只给书名留出扣除价格后的宽度
                                    width: parent.width - bookCover.width - 20 - priceTxt.implicitWidth
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    Text {
                                        width: parent.width
                                        text: "《" + modelData.title + "》"
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        color: Root.Theme.text
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: modelData.cond ? Util.bookCondCN(modelData.cond) : "在售中"
                                        font.pixelSize: 11
                                        color: Root.Theme.textSub
                                    }
                                }
                                Text {
                                    id: priceTxt
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Util.yuan(modelData.price_cents)
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                    color: Root.Theme.primary
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: page.user && page.user.books_on > 0 && page.user.books.length === 0
                        text: "在售书籍较多，去书市逛逛吧"
                        font.pixelSize: 11
                        color: Root.Theme.textLight
                    }
                }

                // 评价
                Text {
                    text: "对方评价"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: Root.Theme.text
                }
                AppCard {
                    width: parent.width
                    height: 56
                    visible: page.user && page.user.review_count > 0
                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (page.user ? (page.user.review_avg || 0).toFixed(1) : "0") + " ★"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: "#FFB800"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: page.user ? ("好评 " + page.user.review_good + " / " + page.user.review_count + " 条评价") : ""
                            font.pixelSize: 12
                            color: Root.Theme.textSub
                        }
                    }
                }
                Repeater {
                    model: page.user ? page.user.reviews : []
                    delegate: AppCard {
                        width: parent.width
                        height: revCol.implicitHeight + 20
                        Column {
                            id: revCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            spacing: 4
                            Row {
                                width: parent.width
                                Text {
                                    text: Array(modelData.score).fill("★").join("")
                                    color: "#FFB800"
                                    font.pixelSize: 13
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: Util.tsShort(modelData.created_at)
                                    font.pixelSize: 11
                                    color: Root.Theme.textLight
                                }
                            }
                            Text {
                                width: parent.width
                                visible: modelData.comment.length > 0
                                text: modelData.comment
                                font.pixelSize: 12
                                color: Root.Theme.textSub
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }

                Item { width: 1; height: 6 }
            }
        }
    }

    function load() {
        Api.get("/api/users/" + page.userId + "/profile").then(function (d) {
            page.user = d.user
        }).catch(function (e) { Ui.toast(e.msg) })
    }

    Component.onCompleted: load()
}
