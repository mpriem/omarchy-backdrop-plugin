import QtQuick
import qs.Commons

// A rotary drum: the current value large, its neighbours dimmed above and
// below; the wheel, a drag, or a click on the upper/lower half turns it.
// Higher numbers sit above, like a thumbwheel: the top half, the wheel up
// and a drag up all turn it up.
Item {
  id: drum
  property int value: 0
  property int minimum: 0
  property int maximum: 24
  property int step: 1
  property string unit: ""
  property bool hasCursor: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal turned(int value)
  signal hoverEntered()

  width: Style.space(70)
  height: Style.space(74)

  function wrap(v) {
    var span = maximum - minimum + step
    return minimum + ((((v - minimum) % span) + span) % span)
  }
  function turn(direction) { turned(wrap(value + direction * step)) }
  function display(v) { return v < 10 ? "0" + v : String(v) }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Util.alpha(drum.foreground, drum.hasCursor ? 0.10 : 0.05)
    border.width: drum.hasCursor ? 2 : 1
    border.color: Util.alpha(drum.foreground, drum.hasCursor ? 0.7 : 0.16)
  }

  Column {
    anchors.centerIn: parent
    spacing: 0

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: drum.display(drum.wrap(drum.value + drum.step))
      color: drum.foreground
      opacity: 0.28
      font.family: drum.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(3)
      Text {
        textFormat: Text.PlainText
        text: drum.display(drum.value)
        color: drum.foreground
        font.family: drum.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }
      Text {
        anchors.baseline: parent.children[0].baseline
        textFormat: Text.PlainText
        text: drum.unit
        color: Qt.darker(drum.foreground, 1.4)
        font.family: drum.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: drum.display(drum.wrap(drum.value - drum.step))
      color: drum.foreground
      opacity: 0.28
      font.family: drum.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.SizeVerCursor
    hoverEnabled: true
    onContainsMouseChanged: if (containsMouse) drum.hoverEntered()
    property real dragStart: 0
    property int dragSteps: 0
    onWheel: function(wheel) { drum.turn(wheel.angleDelta.y > 0 ? 1 : -1); wheel.accepted = true }
    onPressed: function(mouse) { dragStart = mouse.y; dragSteps = 0 }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      var steps = Math.trunc((dragStart - mouse.y) / Style.space(10))
      while (dragSteps < steps) { drum.turn(1); dragSteps++ }
      while (dragSteps > steps) { drum.turn(-1); dragSteps-- }
    }
    onClicked: function(mouse) { if (dragSteps === 0) drum.turn(mouse.y < height / 2 ? 1 : -1) }
  }
}
