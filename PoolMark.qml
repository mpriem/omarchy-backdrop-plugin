import QtQuick
import qs.Commons

// The "pool" placeholder: a stack of image cards, the front one carrying
// the plugin's glyph.
Item {
  id: mark
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  width: Style.space(30)
  height: Style.space(22)

  Repeater {
    model: 3
    Rectangle {
      required property int index
      x: (2 - index) * Style.space(3)
      y: index * Style.space(2) - (2 - index) * Style.space(1)
      width: mark.width - Style.space(6)
      height: mark.height - Style.space(4)
      radius: Style.space(2)
      color: Util.alpha(mark.foreground, 0.10 + index * 0.08)
      border.width: 1
      border.color: Util.alpha(mark.foreground, 0.35 + index * 0.2)
      Text {
        visible: parent.index === 2
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "󰸉"
        color: mark.foreground
        opacity: 0.9
        font.family: mark.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
