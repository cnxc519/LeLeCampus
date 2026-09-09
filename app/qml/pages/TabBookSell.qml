import QtQuick
import LeLeDaiPao 1.0
import QtQuick.Controls
import QtQuick.Dialogs
import ".." as Root
import "../js/util.js" as Util
import "../js/api.js" as Api
import "../js/ui.js" as Ui
import "../components"

// 书市模式·卖书：发布闲置书（书名/课程/成色/价格/封面）+ 我的书管理（上下架/标记已售）
Item {
    id: page
    property var app: null
    property var myBooks: []
    property var _unsubs: null // Realtime 订阅注销函数列表

    Flickable {
        id: sellFlick
        anchors.fill: parent
        contentHeight: col.implicitHeight + 140
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds

        Column {
            id: col
            width: parent.width - 32
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            spacing: 14

            // 顶部下拉刷新（本页是表单+列表混合页，借助 Flickable 顶部下拉触发）
            PullToRefresh {
                id: pullRef
                lv: sellFlick // 显式指定：此处自动推导（parent.parent）解析不到 Flickable
                width: col.width
                onRefresh: function () { page.loadMine() }
            }

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
                        text: "发布闲置书"
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        color: Root.Theme.text
                    }

                    // 书名
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: "书名（必填，1-40 字）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                        AppInput { id: titleInput; hint: "例如：高等数学（第七版）下册 同济版" }
                    }

                    // 新旧程度
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: "新旧程度（选填）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                        Flow {
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: [{ v: 0, l: "不选" }, { v: 1, l: "全新未使用" }, { v: 2, l: "几乎全新" }, { v: 3, l: "有笔记划线" }, { v: 4, l: "使用痕迹较多" }]
                                delegate: Rectangle {
                                    height: 32
                                    width: txt.implicitWidth + 14
                                    radius: 16
                                    color: page.cond === modelData.v ? Root.Theme.primary : "#F0F1F3"
                                    Text {
                                        id: txt
                                        anchors.centerIn: parent
                                        text: modelData.l
                                        font.pixelSize: 11
                                        color: page.cond === modelData.v ? "#FFFFFF" : Root.Theme.textSub
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: page.cond = modelData.v
                                    }
                                }
                            }
                        }
                    }

                    // 价格
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: "期望价格（必填）"; color: Root.Theme.textSub; font.pixelSize: 12 }
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
                                hint: "如 15（0.01-999.99 元，见面一手交钱一手交书）"
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
                                model: ["5", "10", "15", "20", "30"]
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
                                text: "元"
                                color: Root.Theme.textLight
                                font.pixelSize: 11
                            }
                        }
                    }

                    // 交易地点（必填：线下交书面交用）
                    Column {
                        width: parent.width
                        spacing: 8
                        Text { text: "交易地点（必填）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                        AppInput {
                            id: locationInput
                            width: parent.width
                            hint: "当面交书的地点，例如：工学部松园操场北门"
                        }
                    }

                    // ---------- 选填折叠区（课程/说明/封面默认收起，发布页更清爽） ----------
                    Rectangle {
                        width: parent.width
                        height: 36
                        radius: 10
                        color: "#F5F7F8"
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            spacing: 6
                            Text {
                                text: page.extraOpen ? "收起选填项 ▲" : "展开填写选填（课程 · 说明 · 封面照片）▼"
                                font.pixelSize: 12
                                color: Root.Theme.textSub
                            }
                            Text {
                                visible: page.photoFile !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: "· 已选封面"
                                font.pixelSize: 12
                                color: Root.Theme.primary
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: page.extraOpen = !page.extraOpen }
                    }

                    Column {
                        width: parent.width
                        visible: page.extraOpen
                        spacing: 12

                        // 课程名（选修该课的可直接搜到）
                        Column {
                            width: parent.width
                            spacing: 8
                            Text { text: "对应课程（选填）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                            AppInput { id: courseInput; hint: "例如：大学英语 / 电路分析基础" }
                        }

                        // 补充说明
                        Column {
                            width: parent.width
                            spacing: 8
                            Text { text: "补充说明（选填，≤300 字）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                            AppTextArea {
                                id: noteInput
                                width: parent.width
                                height: 70
                                hint: "例如：原价 60+，重点笔记齐全，无缺页；南门宿舍可面交"
                            }
                        }

                        // 封面图
                        Column {
                            width: parent.width
                            spacing: 8
                            Text { text: "封面照片（选填，一张；建议拍清书名）"; color: Root.Theme.textSub; font.pixelSize: 12 }
                            Row {
                                width: parent.width
                                spacing: 10
                                Rectangle {
                                    width: 84; height: 104
                                    radius: 10
                                    color: photoFile ? "transparent" : "#F0F1F3"
                                    border.color: Root.Theme.line
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        visible: page.photoFile
                                        source: page.photoFile
                                        fillMode: Image.PreserveAspectCrop
                                    }
                                    Column {
                                        anchors.centerIn: parent
                                        visible: !page.photoFile
                                        spacing: 4
                                        Text { text: "📷"; font.pixelSize: 22 }
                                        Text { text: "加封面"; color: Root.Theme.textLight; font.pixelSize: 10 }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: page.pickPhoto(null)
                                    }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Text { text: page.photoFile ? "已选择封面，发布时一并上传" : "选一张封面，书市里更醒目"; color: Root.Theme.textSub; font.pixelSize: 11; wrapMode: Text.Wrap; width: parent.width }
                                    Rectangle {
                                        width: 72; height: 28
                                        radius: 14
                                        color: page.photoFile ? Root.Theme.dangerSoft : "#EEF0F3"
                                        visible: page.photoFile
                                        Text { anchors.centerIn: parent; text: "移除"; color: page.photoFile ? Root.Theme.danger : Root.Theme.textLight; font.pixelSize: 11 }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: page.photoFile = ""
                                        }
                                    }
                                }
                            }
                        }
                    }

                    AppButton {
                        width: parent.width
                        text: "发布到书市"
                        busy: page.publishing
                        busyText: "发布中..."
                        onClicked: page.publish()
                    }
                }
            }

            // ---------- 我的书 ----------
            Text {
                text: "我的书（" + page.myBooks.length + "）"
                font.pixelSize: 15
                font.weight: Font.Bold
                color: Root.Theme.text
            }

            NoticeBar {
                width: parent.width
                text: "书卖出后请点「标记已售出」下架；售出/下架后买家无法再看到和联系。交易请当面进行，平台不参与。"
            }

            Repeater {
                model: page.myBooks
                delegate: AppCard {
                    width: parent.width
                    height: mineCol.implicitHeight + 22
                    Column {
                        id: mineCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 11
                        spacing: 8

                        Row {
                            width: parent.width
                            spacing: 10
                            // 封面（点击可更换）
                            Rectangle {
                                width: 46; height: 58
                                radius: 8
                                color: modelData.photo ? "transparent" : Root.Theme.primarySoft
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    visible: modelData.photo
                                    source: Session.baseUrl + "/files/books/" + modelData.id + ".jpg"
                                    fillMode: Image.PreserveAspectCrop
                                }
                                Text { anchors.centerIn: parent; visible: !modelData.photo; text: "📖"; font.pixelSize: 20 }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: page.pickPhoto(modelData.id)
                                }
                            }
                            Column {
                                width: parent.width - 56 - 10
                                spacing: 4
                                Row {
                                    width: parent.width
                                    spacing: 6
                                    Text {
                                        // Row 内子项禁止 right 等锚定，价格靠剩余宽度自然排到最右
                                        width: parent.width - 6 - priceTxt.implicitWidth
                                        text: modelData.title
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                        color: Root.Theme.text
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        id: priceTxt
                                        text: Util.yuan(modelData.price_cents)
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        color: Root.Theme.primary
                                    }
                                }
                                Row {
                                    width: parent.width
                                    spacing: 6
                                    TagBadge {
                                        text: modelData.status === "on" ? "在售" : modelData.status === "off" ? "已下架" : "已售出"
                                        fg: modelData.status === "on" ? Root.Theme.primaryDark : Root.Theme.textLight
                                        bg: modelData.status === "on" ? Root.Theme.primarySoft : "#EEF0F3"
                                    }
                                    TagBadge {
                                        visible: !!modelData.cond_cn
                                        text: modelData.cond_cn
                                        fg: Root.Theme.textSub
                                    }
                                    TagBadge {
                                        visible: modelData.unread_chats > 0
                                        text: "💬 " + modelData.unread_chats + " 条未读"
                                        fg: Root.Theme.danger
                                        bg: Root.Theme.dangerSoft
                                    }
                                    Text {
                                        width: parent.width - 250
                                        visible: !!modelData.location
                                        text: "📍 " + modelData.location
                                        font.pixelSize: 11
                                        color: Root.Theme.textSub
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 8
                            Rectangle {
                                height: 28
                                width: 84
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
                                    onClicked: app.pushPage("BookDetailPage.qml", { bookId: modelData.id })
                                }
                            }
                            Rectangle {
                                height: 28
                                width: 84
                                radius: 14
                                color: Root.Theme.dangerSoft
                                visible: modelData.status === "on"
                                Text {
                                    anchors.centerIn: parent
                                    text: "标记已售出"
                                    font.pixelSize: 12
                                    color: Root.Theme.danger
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: page.setStatus(modelData, "sold")
                                }
                            }
                            Rectangle {
                                height: 28
                                width: 84
                                radius: 14
                                color: "#EEF0F3"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.status === "off" ? "重新上架" : "暂时下架"
                                    font.pixelSize: 12
                                    color: Root.Theme.textSub
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: page.setStatus(modelData, modelData.status === "off" ? "on" : "off")
                                }
                            }
                        }
                    }
                }
            }

            EmptyState {
                width: parent.width
                visible: page.myBooks.length === 0
                text: "还没有发布书"
                subText: "在上面填写书名、课程和价格发布第一本吧"
            }
        }
    }

    property int cond: 0
    property string photoFile: ""
    property bool extraOpen: false // 发布表单的选填折叠区（课程/说明/封面）默认收起

    // 上传目标：null=发布中的新书；否则为已有书的 id（更换封面）
    function pickPhoto(bookId) {
        Ui.confirm({
            title: "选择封面照片",
            text: "建议拍清书名与封面。仅支持一张，自动压缩到 200KB 以内。",
            okText: "选择照片"
        }, function (ok) {
            if (!ok) return
            page.pendingUploadBook = bookId
            photoDlg.open()
        })
    }
    property var pendingUploadBook: null

    FileDialog {
        id: photoDlg
        fileMode: FileDialog.OpenFile
        nameFilters: ["图片 (*.jpg *.jpeg *.png)"]
        onAccepted: {
            var outUrl = ImageUtil.compress(photoDlg.selectedFile, 600, 200)
            if (!outUrl) { Ui.toast("图片处理失败，请换一张"); return }
            if (page.pendingUploadBook) {
                page.uploadPhoto(page.pendingUploadBook, outUrl)
            } else {
                page.photoFile = outUrl
            }
        }
    }

    function uploadPhoto(bookId, fileUrl) {
        Ui.loading(true, "上传中...")
        var fd = new FormData()
        fd.append("file", fileUrl)
        Api.request("/api/books/" + bookId + "/photo", { method: "POST", form: fd, timeoutMs: 60000 }).then(function () {
            Ui.loading(false)
            Ui.toast("封面已上传")
            loadMine()
        }).catch(function (e) {
            Ui.loading(false)
            Ui.toast(e.msg)
        })
    }

    property bool publishing: false

    function publish() {
        if (page.publishing) return
        var title = titleInput.text.trim()
        if (!title) { Ui.toast("请填写书名"); return }
        var location = locationInput.text.trim()
        if (!location) { Ui.toast("请填写交易地点（线下交书用）"); return }
        var priceCents = Util.yuanToCents(priceInput.text)
        if (isNaN(priceCents) || priceCents < 1) { Ui.toast("价格需在 0.01-999.99 元之间"); return }
        if (priceCents > 99999) { Ui.toast("价格需在 0.01-999.99 元之间"); return }

        Ui.confirm({
            title: "确认发布到书市？",
            text: "《" + title + "》 定价 " + Util.yuan(priceCents) + "。平台仅提供信息展示与联系，不参与交易：请与买家当面验书、当面付款。",
            okText: "确认发布"
        }, function (ok) {
            if (!ok) return
            Ui.loading(true, "发布中...")
            Api.post("/api/books", {
                title: title,
                course: courseInput.text.trim(),
                cond: page.cond || undefined,
                price_cents: priceCents,
                note: noteInput.text.trim(),
                location: location
            }).then(function (d) {
                var bookId = d.id
                var after = function () {
                    page.publishing = false
                    Ui.loading(false)
                    Ui.toast("发布成功！")
                    titleInput.text = ""
                    courseInput.text = ""
                    noteInput.text = ""
                    locationInput.text = ""
                    priceInput.text = ""
                    page.cond = 0
                    page.photoFile = ""
                    loadMine()
                }
                if (page.photoFile) {
                    var fd = new FormData()
                    fd.append("file", page.photoFile)
                    Api.request("/api/books/" + bookId + "/photo", { method: "POST", form: fd, timeoutMs: 60000 }).then(function () {
                        after()
                    }).catch(function (e) {
                        after()
                        Ui.toast("发布成功，但封面上传失败：" + (e && e.msg ? e.msg : "网络异常") + "（可在列表点封面重试）")
                    })
                } else {
                    after()
                }
            }).catch(function (e) {
                Ui.loading(false)
                Ui.toast(e.msg)
            })
        })
    }

    function setStatus(b, st) {
        var sold = (st === "sold")
        Ui.confirm({
            title: sold ? "标记已售出？" : "暂时下架？",
            text: sold
                ? "标记后本书所有信息将从平台删除，且无法再与买家取得联系；建议确认图书已当面交接后再操作。是否确认标记已售出？"
                : "暂时下架后买家将无法再看到这本书，也无法发起新的联系；建议图书交接完成后再操作。是否确认暂时下架？",
            okText: sold ? "确认已售出" : "确认下架",
            danger: sold
        }, function (ok) {
            if (!ok) return
            Api.post("/api/books/" + b.id + "/status", { status: st }).then(function () {
                if (sold) Ui.toast("已标记售出，本书信息已从平台删除")
                loadMine()
            }).catch(function (e) { Ui.toast(e.msg) })
        })
    }

    function loadMine() {
        Api.get("/api/books/mine").then(function (d) {
            page.myBooks = d.list
            pullRef.finish()
        }).catch(function () {
            pullRef.finish()
        })
    }

    function refresh() { loadMine() }

    Component.onCompleted: {
        loadMine()
        // 登出时 Loader 卸载会销毁本页，handler 必须解除，否则重登后重复触发
        page._unsubs = [
            Realtime.on("bchat", function () { page.loadMine() }),
            Realtime.on("notif", function () { page.loadMine() })
        ]
    }

    Component.onDestruction: {
        if (page._unsubs) for (var i = 0; i < page._unsubs.length; i++) page._unsubs[i]()
    }
}
