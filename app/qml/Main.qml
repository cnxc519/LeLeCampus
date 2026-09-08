import QtQuick
import QtQuick.Controls
import LeLeDaiPao 1.0
import "js/util.js" as Util
import "js/api.js" as Api
import "js/ui.js" as Ui
import "components"
import "pages"

// 乐乐代跑 主界面外壳：登录/主界面切换、五 Tab、详情页栈、全局覆盖层
Window {
    id: root
    visible: true
    width: 420
    height: 840
    minimumWidth: 320
    minimumHeight: 520
    color: Theme.bg
    title: "乐乐代跑"

    property bool loggedIn: false
    property string currentTab: "order"
    property string lastErrandTab: "order" // 两种模式各自记住上次停留的 Tab
    property string lastMarketTab: "book"

    // 各模式可用的 Tab 键（invite/me 两个模式共用）
    function errandKeys() { return ["order", "post", "active"] }
    function marketKeys() { return ["book", "sell", "inbox"] }
    function tabKeys() {
        return Session.mode === "market" ? marketKeys().concat(["invite", "me"]) : errandKeys().concat(["invite", "me"])
    }
    // 底部栏显示的五项（两种模式各五格：内容/发布/进行中·消息 + 邀请 + 我的）
    function tabModel() {
        if (Session.mode === "market") return [
            { key: "book", icon: "📚", label: "书市" },
            { key: "sell", icon: "📤", label: "卖书" },
            { key: "inbox", icon: "💬", label: "消息" },
            { key: "invite", icon: "🎁", label: "邀请" },
            { key: "me", icon: "👤", label: "我的" }
        ]
        return [
            { key: "order", icon: "⚡", label: "接单" },
            { key: "post", icon: "＋", label: "挂单" },
            { key: "active", icon: "🕐", label: "进行中" },
            { key: "invite", icon: "🎁", label: "邀请" },
            { key: "me", icon: "👤", label: "我的" }
        ]
    }

    function tabVisible(k) {
        if (k === "invite" || k === "me") return root.currentTab === k
        return Session.mode === "market"
            ? marketKeys().indexOf(k) >= 0 && root.currentTab === k
            : errandKeys().indexOf(k) >= 0 && root.currentTab === k
    }

    function applyMode() {
        // 切模式时回到该模式上次停留的 Tab
        root.currentTab = Session.mode === "market" ? root.lastMarketTab : root.lastErrandTab
    }

    function isSharedTab(k) { return k === "invite" || k === "me" }
    function isMarketKey(k) { return marketKeys().indexOf(k) >= 0 }
    function isErrandKey(k) { return errandKeys().indexOf(k) >= 0 }

    // ---------- 全局桥接 ----------
    // API 超时看门狗：QML XHR 无 timeout 支持，由 Api.installWatchdog 注入此 Timer 定期清扫挂起请求
    Timer {
        id: apiWatchdog
        interval: 500
        repeat: true
        running: false
    }

    Component.onCompleted: {
        Api.install({
            token: function () { return Session.token },
            baseUrl: function () { return Session.baseUrl },
            onUnauthorized: function (path) {
                console.log("[auth] UNAUTHORIZED triggered by " + (path || "unknown"))
                if (!Session.token) { console.log("[auth] token already empty, no-op"); return }
                Session.clear()
                root.loggedIn = false
                Realtime.disconnect()
                Ui.toast("登录已过期，请重新登录")
            }
        })
        Api.installWatchdog(apiWatchdog)
        Ui.install({
            toast: function (m) { overlays.showToast(m) },
            confirm: function (o, cb) { overlays.showConfirm(o, cb) },
            input: function (o, cb) { overlays.showInput(o, cb) },
            loading: function (s, t) { overlays.showLoading(s, t) }
        })
        // 若上次停留在书市模式，启动后落在书市 Tab
        root.applyMode()

        // 重启自动登录：token 已持久化则直接进主界面；首次用户（引导未完成）重新补引导
        if (Session.token) {
            console.log("[auth] auto-restore token, entering main")
            root.loggedIn = true
            if (!Session.onboardingDone) {
                root.pushPage("OnboardingPage.qml", {})
                console.log("[auth] auto-restore: pushed onboarding")
            }
        }

    }

    onLoggedInChanged: {
        if (root.loggedIn) {
            Realtime.connect()
            checkVersion(false)
        }
    }

    // 登录/注册成功统一入口：必须在 Main(root) 上执行 ——
    // 置 loggedIn 会销毁登录页(loader)，在登录页自身上下文里继续跑后续代码不可靠
    function loginSuccess(d) {
        try {
            Session.setToken(d.token)
            Session.setEmail(d.user.email)
            Session.setNickname(d.user.nickname)
            Session.setMyId(d.user.id)
            console.log("[auth] main set ok, flipping loggedIn")
            root.loggedIn = true
            // 首次进入展示使用流程（两种模式全流程 + 当面结算说明）
            if (!Session.onboardingDone) {
                root.pushPage("OnboardingPage.qml", {})
                console.log("[auth] pushed onboarding")
            } else {
                root.currentTab = "order"
                console.log("[auth] go order tab")
            }
        } catch (err) {
            console.log("[auth] loginSuccess CRASH: " + err)
        }
    }

    // Android 系统返回键统一入口（C++ 拦截 Key_Back 后转发到这里）：
    // 顺序 = 版本弹窗 → 全局弹层（确认/输入/加载）→ 详情页栈；已在主页时不做任何事，
    // 避免"按返回直接杀掉应用"丢失进行中的操作
    function androidBack() {
        if (versionDlg.visible) { if (!versionDlg.forced) versionDlg.hide(); return }
        if (overlays.anyVisible()) { overlays.closeTop(); return }
        if (stack.depth > 1) { root.popPage(); return }
    }

    // 模式切换（Session.mode 持久化；切换时回到该模式上次停留的 Tab）
    Connections {
        target: Session
        function onModeChanged() { root.applyMode() }
    }

    // ---------- 版本检查 ----------
    function checkVersion(manual) {
        if (!Session.token) return
        Api.get("/api/version").then(function (v) {
            var cur = Session.appVersionCode
            var forced = (v.min && cur < v.min) || v.forced === true
            if (v.code > cur) {
                versionDlg.show(v, forced)
            } else if (manual) {
                Ui.toast("已是最新版本")
            }
        }).catch(function () {})
    }

    // 启动/登录只查一次的话，长期不重启的用户永远收不到新发布提示 —— 每 6 小时补查
    Timer {
        interval: 6 * 3600 * 1000
        repeat: true
        running: root.loggedIn
        onTriggered: root.checkVersion(false)
    }

    // ---------- 导航 ----------
    function pushPage(file, props) {
        stack.push(Qt.resolvedUrl("pages/" + file), Object.assign({ app: root }, props || {}))
    }
    function popPage() {
        if (stack.depth > 1) stack.pop()
    }
    function openTab(name) {
        if (tabKeys().indexOf(name) < 0) return
        if (root.currentTab === name) return
        root.currentTab = name
        if (isSharedTab(name)) { root.lastErrandTab = name; root.lastMarketTab = name }
        else if (isMarketKey(name)) root.lastMarketTab = name
        else root.lastErrandTab = name
    }
    function refreshTab(name) {
        var l = { order: tabOrder, post: tabPost, active: tabActive, invite: tabInvite, me: tabMe, book: tabBook, sell: tabSell, inbox: tabInbox }[name]
        if (l && l.item && l.item.refresh) l.item.refresh()
    }

    // ---------- 界面 ----------
    Item {
        id: appRoot
        anchors.fill: parent
        // Android 状态栏安全区：部分机型（edge-to-edge）内容会顶进状态栏，统一顶部内缩
        anchors.topMargin: Qt.platform.os === "android" ? Session.safeTop : 0
        visible: root.loggedIn

        // 代跑模式四页 + 书市模式三页 + 共用两页（实例常驻，切换不丢状态；详情页栈覆盖其上）
        // active 绑定 loggedIn：登录成功后才实例化 —— 保证各页 onCompleted 的请求晚于
        // Api.install（Main.onCompleted 的注入），否则启动期请求无 token 全部 401 误登出
        Loader { id: tabOrder;  anchors.fill: parent; visible: root.tabVisible("order");  source: "pages/TabOrder.qml";  active: root.loggedIn; onLoaded: item.app = root }
        Loader { id: tabPost;   anchors.fill: parent; visible: root.tabVisible("post");   source: "pages/TabPost.qml";   active: root.loggedIn; onLoaded: item.app = root }
        Loader { id: tabActive; anchors.fill: parent; visible: root.tabVisible("active"); source: "pages/TabActive.qml"; active: root.loggedIn; onLoaded: item.app = root }
        Loader { id: tabBook;   anchors.fill: parent; visible: root.tabVisible("book");   source: "pages/TabBookBrowse.qml"; active: root.loggedIn; onLoaded: item.app = root }
        Loader { id: tabSell;   anchors.fill: parent; visible: root.tabVisible("sell");   source: "pages/TabBookSell.qml";    active: root.loggedIn; onLoaded: item.app = root }
        Loader { id: tabInbox;  anchors.fill: parent; visible: root.tabVisible("inbox");  source: "pages/BookChatsPage.qml"; active: root.loggedIn; onLoaded: { item.app = root; item.embedded = true } }
        Loader { id: tabInvite; anchors.fill: parent; visible: root.currentTab === "invite"; source: "pages/TabInvite.qml"; active: root.loggedIn; onLoaded: item.app = root }
        Loader { id: tabMe;     anchors.fill: parent; visible: root.currentTab === "me";     source: "pages/TabMe.qml";     active: root.loggedIn; onLoaded: item.app = root }

        // 详情页栈
        StackView {
            id: stack
            anchors.fill: parent
            initialItem: Item {}
            pushEnter: Transition { NumberAnimation { property: "x"; from: stack.width; to: 0; duration: 240; easing.type: Easing.OutCubic } }
            pushExit:  Transition { NumberAnimation { property: "x"; from: 0; to: -stack.width / 3; duration: 200; easing.type: Easing.InCubic } }
            popEnter:  Transition { NumberAnimation { property: "x"; from: -stack.width / 3; to: 0; duration: 200; easing.type: Easing.OutCubic } }
            popExit:   Transition { NumberAnimation { property: "x"; from: 0; to: stack.width; duration: 240; easing.type: Easing.InCubic } }
        }

        // 底部 TabBar：模式切换条 + 五个功能 Tab
        Rectangle {
            id: tabBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 92
            color: "#FFFFFF"
            visible: stack.depth === 1

            // 模式切换条（代跑 / 书市，两种模式一键切换，选择本地记住）
            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 32
                color: "#F7F8FA"
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.line
                }
                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Repeater {
                        model: [
                            { v: "errand", l: "⚡ 代跑互助" },
                            { v: "market", l: "📚 二手书市" }
                        ]
                        delegate: Rectangle {
                            height: 24
                            width: txt.implicitWidth + 32
                            radius: 12
                            color: Session.mode === modelData.v ? Theme.primary : "#FFFFFF"
                            border.color: Session.mode === modelData.v ? Theme.primary : Theme.line
                            border.width: 1
                            Text {
                                id: txt
                                anchors.centerIn: parent
                                text: modelData.l
                                font.pixelSize: 11
                                font.weight: Session.mode === modelData.v ? Font.Medium : Font.Normal
                                color: Session.mode === modelData.v ? "#FFFFFF" : Theme.textSub
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { if (Session.mode !== modelData.v) Session.mode = modelData.v }
                            }
                        }
                    }
                }
            }

            // 功能 Tab
            Row {
                y: 32
                width: parent.width
                height: 60
                Repeater {
                    model: root.tabModel()
                    delegate: Item {
                        width: parent.width / 5
                        height: parent.height

                        // 选中指示条
                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.currentTab === modelData.key ? 22 : 0
                            height: 3
                            radius: 1.5
                            gradient: Theme.brandGradient
                            Behavior on width { NumberAnimation { duration: 150 } }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                font.pixelSize: 21
                                color: root.currentTab === modelData.key ? Theme.primary : Theme.textLight
                                scale: root.currentTab === modelData.key ? 1.12 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150 } }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.pixelSize: 10
                                font.weight: root.currentTab === modelData.key ? Font.Medium : Font.Normal
                                color: root.currentTab === modelData.key ? Theme.primaryDark : Theme.textLight
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.openTab(modelData.key)
                        }
                    }
                }
            }
        }

        // Android 返回键
        FocusScope {
            focus: true
            Keys.onReleased: {
                if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
                    event.accepted = true
                    if (stack.depth > 1) root.popPage()
                    else if (Qt.platform.os !== "android") Qt.quit()
                }
            }
        }
    }

    // ---------- 登录页 ----------
    Loader {
        id: loginLoader
        anchors.fill: parent
        anchors.topMargin: Qt.platform.os === "android" ? Session.safeTop : 0
        source: "pages/LoginPage.qml"
        active: !root.loggedIn
        onLoaded: item.app = root
    }

    // ---------- 全局覆盖层 ----------
    Overlays {
        id: overlays
        anchors.fill: parent
        z: 1000
    }

    VersionDialog {
        id: versionDlg
        anchors.fill: parent
        z: 1001
    }
}
