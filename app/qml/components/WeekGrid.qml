import QtQuick
import ".." as Root

// 周时间表选择器（电影院选座式）：周日~周六 × 8点~23点，共 16×7 个格子
// 点击切换单个格子；按住拖拽可框选一串连续格子
// 注意：不做"今天已过时间置灰"——挂单是按周几重复的时间表（一次挂多单、可能跨周），
// 今天过期的某格下周同一时间仍有效；"今天已过的时间点接不了"由服务端 availableDates 过滤
Item {
    id: root
    property var selected: ({})          // "day:hour" -> true
    property int cellH: 40
    property bool interactive: true
    signal changed()

    readonly property int timeCol: 48
    readonly property int nRows: 16
    readonly property int nCols: 7
    property int bump: 0                 // 强制刷新绑定用

    function key(day, hour) { return day + ':' + hour }
    function has(day, hour) { return !!selected[key(day, hour)] }
    function count() { return Object.keys(selected).length }
    function clear() { selected = {}; bump++; changed(); }

    function toSlots() {
        var arr = []
        Object.keys(selected).forEach(function (k) {
            var p = k.split(':')
            arr.push({ day: +p[0], hour: +p[1] })
        })
        return arr
    }

    // 北京时间今天星期几（0=周日）。必须按 UTC 零点解析：+08:00 零点=UTC 前一天 16 点，
    // 用 UTC 取值会拿到昨天的星期（曾导致高亮/置灰错一列）
    property int todayCol: (function () {
        var today = new Date(Date.now() + 8 * 3600e3).toISOString().slice(0, 10)
        return new Date(today + 'T00:00:00Z').getUTCDay()
    })()

    // ---------- 拖拽框选 ----------
    property int dragStart: -1
    property int dragCur: -1

    function cellWidth() {
        return Math.max(1, (width - root.timeCol) / nCols)
    }
    function idxFromPos(x, y) {
        var c = Math.floor((x - root.timeCol) / cellWidth())
        var r = Math.floor(y / root.cellH)
        if (c < 0 || c >= nCols || r < 0 || r >= nRows) return -1
        return r * nCols + c
    }
    function rectCells() {
        var arr = []
        if (dragStart < 0 || dragCur < 0) return arr
        var r1 = Math.floor(dragStart / nCols), c1 = dragStart % nCols
        var r2 = Math.floor(dragCur / nCols), c2 = dragCur % nCols
        for (var r = Math.min(r1, r2); r <= Math.max(r1, r2); r++)
            for (var c = Math.min(c1, c2); c <= Math.max(c1, c2); c++)
                arr.push(c + ':' + (r + 8))
        return arr
    }
    function inDragRect(day, hour) {
        if (dragStart < 0 || dragCur < 0) return false
        return rectCells().indexOf(day + ':' + hour) >= 0
    }
    function cellColor(day, hour, ver) {
        if (selected[key(day, hour)]) return Root.Theme.primary
        if (dragStart >= 0 && inDragRect(day, hour)) return Root.Theme.primarySoft
        return "#FFFFFF"
    }

    // ---------- 界面 ----------
    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: 40 + root.nRows * root.cellH
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        MouseArea {
            id: dragArea
            anchors.left: parent.left
            anchors.leftMargin: root.timeCol
            anchors.top: parent.top
            anchors.topMargin: 40
            width: parent.width - root.timeCol
            height: root.nRows * root.cellH
            enabled: root.interactive

            onPressed: {
                root.dragStart = root.idxFromPos(mouseX + root.timeCol, mouseY)
                root.dragCur = root.dragStart
                root.bump++
            }
            onPositionChanged: {
                if (root.dragStart >= 0) {
                    var idx = root.idxFromPos(mouseX + root.timeCol, mouseY)
                    if (idx !== root.dragCur) { root.dragCur = idx; root.bump++ }
                }
            }
            onReleased: {
                if (root.dragStart >= 0 && root.dragCur === root.dragStart) {
                    // 单击：切换单个格子
                    var c = root.dragStart % root.nCols
                    var r = Math.floor(root.dragStart / root.nCols)
                    var k = root.key(c, r + 8)
                    if (root.selected[k]) { var s = root.selected; delete s[k]; root.selected = s }
                    else { var s2 = root.selected; s2[k] = true; root.selected = s2 }
                } else if (root.dragStart >= 0) {
                    // 拖拽：合并矩形区域（已选中的不变）
                    var cells = root.rectCells()
                    var s3 = root.selected
                    cells.forEach(function (k) { s3[k] = true })
                    root.selected = s3
                }
                root.dragStart = -1
                root.dragCur = -1
                root.bump++
                root.changed()
            }
        }

        Column {
            width: parent.width
            spacing: 0

            // 星期表头
            Item {
                width: parent.width
                height: 40
                Text {
                    x: 0
                    width: root.timeCol
                    height: 40
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "时间"
                    color: Root.Theme.textSub
                    font.pixelSize: 11
                }
                Repeater {
                    model: 7
                    delegate: Text {
                        x: root.timeCol + index * root.cellWidth()
                        width: root.cellWidth()
                        height: 40
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][index]
                        color: index === root.todayCol ? Root.Theme.primary : Root.Theme.text
                        font.pixelSize: 12
                        font.weight: index === root.todayCol ? Font.Bold : Font.Normal
                    }
                }
            }

            // 16 行格子
            Repeater {
                model: root.nRows
                delegate: Row {
                    id: hourRow
                    property int hour: index + 8   // 行 = 小时
                    spacing: 0
                    height: root.cellH

                    // 左侧时间标签
                    Rectangle {
                        width: root.timeCol
                        height: root.cellH
                        color: "transparent"
                        Column {
                            anchors.centerIn: parent
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: hourRow.hour + "点"
                                color: Root.Theme.text
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (hourRow.hour - 1) + ":55集合"
                                color: Root.Theme.textLight
                                font.pixelSize: 9
                            }
                        }
                    }

                    Repeater {
                        model: root.nCols
                        delegate: Rectangle {
                            id: cell
                            property int day: index            // 列 = 星期
                            property int hour: hourRow.hour     // 行 = 小时
                            width: root.cellWidth() - 1
                            height: root.cellH - 1
                            radius: 6
                            color: root.cellColor(day, hour, root.bump)
                            border.color: Root.Theme.line
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: cell.hour + ":00"
                                color: root.selected[root.key(cell.day, cell.hour)] ? "#FFFFFF" : Root.Theme.text
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }
    }
}
