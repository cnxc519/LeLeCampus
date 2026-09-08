import QtQuick
import QtQuick.Controls
import ".." as Root

// 多行输入
TextArea {
    id: root
    property string hint: ""

    width: parent ? parent.width : 0
    height: 96
    padding: 12
    font.pixelSize: 15
    color: Root.Theme.text
    placeholderText: root.hint
    placeholderTextColor: Root.Theme.textLight
    wrapMode: TextEdit.Wrap
    selectByMouse: true

    background: Rectangle {
        radius: Root.Theme.radiusBtn
        color: Root.Theme.card
        border.color: root.activeFocus ? Root.Theme.primary : Root.Theme.line
        border.width: root.activeFocus ? 1.6 : 1
    }
}
