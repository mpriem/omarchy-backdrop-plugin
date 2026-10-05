import QtQuick
import qs.Commons
import qs.Ui
import "Config.js" as Config

// Transition style chips, the duration slider with its reading, "Try it",
// and a line describing the chosen style. The cursor is addressed by
// section ("style" with an index, "duration", "try").
Column {
  id: section
  property string style: "fade"
  property int ms: 220
  property string cursorSection: ""
  property int cursorIndex: -1
  property var bar: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  // the slider's reading while it's being dragged
  property int editMs: -1
  readonly property int shownMs: editMs >= 0 ? editMs : ms

  signal stylePicked(string value)
  signal durationChanged(int ms)
  signal tryRequested()
  signal hovered(string section, int index)

  function cursorRect(name, index) {
    var item = name === "style" ? styleChips : name === "try" ? tryButton : durationRow
    var rect = name === "style" ? styleChips.cursorRect(index) : Qt.rect(0, 0, item.width, item.height)
    var p = item.mapToItem(section, rect.x, rect.y)
    return Qt.rect(p.x, p.y, rect.width, rect.height)
  }

  spacing: Style.space(10)

  PanelSectionHeader { text: "TRANSITION"; foreground: section.foreground; fontFamily: section.fontFamily }

  ChipRow {
    id: styleChips
    width: parent.width
    columns: 3
    options: Config.TRANSITION_OPTIONS
    value: section.style
    cursorIndex: section.cursorSection === "style" ? section.cursorIndex : -1
    foreground: section.foreground
    fontFamily: section.fontFamily
    onChanged: function(value) { section.stylePicked(value) }
    onHovered: function(index) { section.hovered("style", index) }
  }

  Row {
    width: parent.width
    spacing: Style.space(10)

    CursorSurface {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - tryButton.width - parent.spacing
      implicitHeight: durationRow.implicitHeight + Style.space(8)
      outline: true
      foreground: section.foreground
      hasCursor: section.cursorSection === "duration"
      HoverHandler { onHoveredChanged: if (hovered) section.hovered("duration", 0) }

      Row {
        id: durationRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)
        spacing: Style.space(10)

        PanelSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - durationLabel.width - parent.spacing
          bar: section.bar
          minimum: 0
          maximum: Config.TRANSITION_MAX_MS
          step: 50
          integer: true
          value: section.ms
          onMoved: function(v) { section.editMs = v }
          onReleased: function(v) { section.editMs = -1; section.durationChanged(v) }
        }

        Text {
          id: durationLabel
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(52)
          textFormat: Text.PlainText
          text: Config.transitionLabel(section.shownMs)
          color: section.foreground
          font.family: section.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }
    }

    Button {
      id: tryButton
      anchors.verticalCenter: parent.verticalCenter
      hasCursor: section.cursorSection === "try"
      onHovered: function(h) { if (h) section.hovered("try", 0) }
      text: "Try it"
      iconText: "󰐊"
      foreground: section.foreground
      fontFamily: section.fontFamily
      bordered: true
      onClicked: section.tryRequested()
    }
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: Config.TRANSITION_DESCRIPTIONS[section.style]
    color: Qt.darker(section.foreground, 1.4)
    font.family: section.fontFamily
    font.pixelSize: Style.font.caption
  }
}
