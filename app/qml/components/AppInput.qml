import QtQuick
import QtQuick.Controls
import ".." as Root

// 圆角输入框（带可选密码/数字键盘类型）
TextField {
    id: root
    property string hint: ""
    property bool pw: false

    width: parent ? parent.width : 0
    height: 48
    padding: 14
    font.pixelSize: 15
    color: Root.Theme.text
    placeholderText: root.hint
    placeholderTextColor: Root.Theme.textLight
    echoMode: root.pw ? TextInput.Password : TextInput.Normal
    selectByMouse: true
    inputMethodHints: root.pw ? Qt.ImhHiddenText : Qt.ImhNone

    background: Rectangle {
        radius: Root.Theme.radiusBtn
        color: Root.Theme.card
        border.color: root.activeFocus ? Root.Theme.primary : Root.Theme.line
        border.width: root.activeFocus ? 1.6 : 1
    }
}
