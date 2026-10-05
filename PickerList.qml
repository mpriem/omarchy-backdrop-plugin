import QtQuick
import qs.Commons
import qs.Ui
import "Config.js" as Config

// The one picker: a search box and the pool as a list with a thumbnail per
// image. `rows` is [{path, label, file}] with path "" for "from the pool"
// and Config.RANDOM for a random assignment; `current` is the target's
// present value. `cursorIndex` is the row under the panel's keyboard cursor.
Column {
  id: picker
  property int revision: 0
  property var rows: []
  property string current: ""
  property int cursorIndex: -1
  property bool active: true          // thumbnails only decode while true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property bool searching: searchField.activeFocus
  readonly property string search: searchField.text

  signal picked(string path)
  signal hovered(int index)
  signal searchHovered()
  // the search box hands the keys back: Enter/Escape leave it, Tab and the
  // arrows leave it and move on (direction +1 / -1)
  signal searchLeft(int direction)

  function clearSearch() { searchField.text = "" }
  function focusSearch(selectAll) { searchField.forceActiveFocus(); if (selectAll) searchField.selectAll() }
  function cursorRect(index) {
    var item = index < 0 ? searchField : list.itemAtIndex(index)
    if (!item) return Qt.rect(0, 0, width, height)
    var p = item.mapToItem(picker, 0, 0)
    return Qt.rect(p.x, p.y, item.width, item.height)
  }
  function showIndex(index) { list.positionViewAtIndex(index, ListView.Contain) }
  // land on the current pick whenever the list or the target changes
  function showCurrent() {
    for (var i = 0; i < list.count; i++) {
      if (rows[i].path === current) { list.positionViewAtIndex(i, ListView.Contain); return }
    }
  }
  onCurrentChanged: Qt.callLater(showCurrent)

  spacing: Style.space(10)

  TextField {
    id: searchField
    width: parent.width
    placeholderText: "Search wallpapers…"
    foreground: picker.foreground
    font.family: picker.fontFamily
    hasCursor: !activeFocus && picker.cursorIndex === -2
    onHoveredChanged: if (hovered) picker.searchHovered()
    Keys.onPressed: function(e) {
      if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { picker.searchLeft(0); e.accepted = true }
      else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab || e.key === Qt.Key_Down || e.key === Qt.Key_Up) {
        picker.searchLeft(e.key === Qt.Key_Backtab || e.key === Qt.Key_Up ? -1 : 1); e.accepted = true
      }
    }
  }

  Rectangle {
    width: parent.width
    height: Style.space(214)
    radius: Style.cornerRadius
    color: Util.alpha(picker.foreground, 0.04)
    border.width: 1
    border.color: Util.alpha(picker.foreground, 0.14)
    clip: true

    ListView {
      id: list
      anchors.fill: parent
      anchors.margins: Style.space(4)
      model: picker.active ? picker.rows : []
      spacing: Style.space(2)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      onModelChanged: Qt.callLater(picker.showCurrent)

      delegate: Rectangle {
        id: pickRow
        required property var modelData
        required property int index
        readonly property bool isCurrent: modelData.path === picker.current
        readonly property bool hasCursor: picker.cursorIndex === index
        width: ListView.view.width
        height: Style.space(44)
        radius: Math.min(Style.cornerRadius, Style.space(6))
        color: hasCursor ? Util.alpha(picker.foreground, 0.10) : isCurrent ? Util.alpha(picker.foreground, 0.12) : "transparent"
        border.width: hasCursor ? 1 : 0
        border.color: Util.alpha(picker.foreground, 0.55)

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(10)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(64)
            height: Style.space(36)
            radius: Math.min(Style.cornerRadius, Style.space(4))
            color: Util.alpha(picker.foreground, 0.08)
            clip: true

            Image {
              anchors.fill: parent
              visible: pickRow.modelData.path !== "" && pickRow.modelData.path !== Config.RANDOM
              source: visible ? Util.fileUrl(pickRow.modelData.path) + "#" + picker.revision : ""
              sourceSize: Qt.size(Style.space(128), Style.space(72))
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: false
              smooth: true
            }

            PoolMark {
              visible: pickRow.modelData.path === ""
              anchors.centerIn: parent
              foreground: picker.foreground
              fontFamily: picker.fontFamily
            }

            Text {
              visible: pickRow.modelData.path === Config.RANDOM
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "󰒟"
              color: picker.foreground
              opacity: 0.9
              font.family: picker.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(64) - Style.space(10) - Style.space(24)
            spacing: Style.space(1)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: pickRow.modelData.label
              color: picker.foreground
              font.family: picker.fontFamily
              font.pixelSize: Style.font.body
              font.bold: pickRow.isCurrent
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              visible: pickRow.modelData.file !== ""
              textFormat: Text.PlainText
              text: pickRow.modelData.file
              color: Qt.darker(picker.foreground, 1.4)
              font.family: picker.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: pickRow.isCurrent
            textFormat: Text.PlainText
            text: "󰄬"
            color: picker.foreground
            font.family: picker.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: if (containsMouse) picker.hovered(pickRow.index)
          onClicked: picker.picked(pickRow.modelData.path)
        }
      }
    }
  }
}
