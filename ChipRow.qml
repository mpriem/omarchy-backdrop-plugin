import QtQuick
import qs.Commons
import qs.Ui

// A row of equal-width chips (wrapping to `columns` per row), so every
// control shares the panel's edges. `cursorIndex` is the chip under the
// panel's keyboard cursor, or -1.
Grid {
  id: chips
  property var options: []
  property string value: ""
  property int cursorIndex: -1
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal changed(string value)
  signal hovered(int index)

  function cursorRect(index) {
    var item = buttons.itemAt(index)
    return item ? Qt.rect(item.x, item.y, item.width, item.height) : Qt.rect(0, 0, width, height)
  }
  columns: Math.max(1, options.length)
  columnSpacing: Style.space(6)
  rowSpacing: Style.space(6)

  Repeater {
    id: buttons
    model: chips.options
    Button {
      required property var modelData
      required property int index
      width: (chips.width - chips.columnSpacing * (chips.columns - 1)) / Math.max(1, chips.columns)
      text: modelData.label
      selected: modelData.value === chips.value
      hasCursor: chips.cursorIndex === index
      bordered: true
      foreground: chips.foreground
      fontFamily: chips.fontFamily
      onClicked: chips.changed(modelData.value)
      onHovered: function(h) { if (h) chips.hovered(index) }
    }
  }
}
