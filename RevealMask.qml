import QtQuick
import QtQuick.Shapes

// The mask for the "reveal" transition: a slanted band growing out from the
// centre as `progress` goes 0 -> 1, the way Omarchy's own theme switch draws
// it. Rendered as a layer only while a reveal is in progress.
Item {
  id: mask
  property real progress: 0
  property bool active: false

  visible: false
  layer.enabled: active

  readonly property real slant: -0.18
  readonly property real centerTop: width / 2 - slant * height / 2
  readonly property real centerBottom: width / 2 + slant * height / 2
  readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
  readonly property real spread: reach * progress

  Shape {
    anchors.fill: parent
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: "white"
      strokeColor: "transparent"
      startX: mask.centerTop - mask.spread; startY: 0
      PathLine { x: mask.centerTop + mask.spread; y: 0 }
      PathLine { x: mask.centerBottom + mask.spread; y: mask.height }
      PathLine { x: mask.centerBottom - mask.spread; y: mask.height }
      PathLine { x: mask.centerTop - mask.spread; y: 0 }
    }
  }
}
