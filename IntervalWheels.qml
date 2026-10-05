import QtQuick
import qs.Commons
import "Config.js" as Config

// The rotation interval: an hours drum, a minutes drum, and the reading.
Row {
  id: wheels
  property string actualSpec: Config.intervalSpec(hours, minutes)
  property int hours: 0
  property int minutes: 30
  property int cursorIndex: -1
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal hoursTurned(int value)
  signal minutesTurned(int value)
  signal hovered(int index)

  spacing: Style.space(10)

  Drum {
    value: wheels.hours
    minimum: 0
    maximum: 24
    step: 1
    unit: "h"
    hasCursor: wheels.cursorIndex === 0
    foreground: wheels.foreground
    fontFamily: wheels.fontFamily
    onHoverEntered: wheels.hovered(0)
    onTurned: function(v) { wheels.hoursTurned(v) }
  }

  Drum {
    value: wheels.minutes
    minimum: 0
    maximum: 59
    step: 1
    unit: "min"
    hasCursor: wheels.cursorIndex === 1
    foreground: wheels.foreground
    fontFamily: wheels.fontFamily
    onHoverEntered: wheels.hovered(1)
    onTurned: function(v) { wheels.minutesTurned(v) }
  }

  Column {
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - Style.space(70) * 2 - parent.spacing * 2
    spacing: Style.space(3)

    Text {
      textFormat: Text.PlainText
      text: "Every " + Config.intervalLabel(wheels.actualSpec)
      color: wheels.foreground
      font.family: wheels.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Text {
      width: parent.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Scroll, drag or click the drums. Up to 24 hours."
      color: Qt.darker(wheels.foreground, 1.4)
      font.family: wheels.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
