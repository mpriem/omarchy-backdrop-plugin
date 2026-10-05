import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// One monitor's background: a layer surface holding a slot per resident
// image, with the transition moving, clipping, scaling, fading or masking
// the incoming slot. `renderer` is Background.qml, which decides what each
// monitor should show (imageFor), what to keep decoded (residentFor), and
// how to transition.
PanelWindow {
  id: panel
  required property var modelData
  required property var renderer

  screen: modelData
  visible: !remapGuard.remapping
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  // Keep render updates enabled: the background layer has been observed
  // to lose its committed buffer when parked with updatesEnabled=false.
  updatesEnabled: true

  WlrLayershell.namespace: "omarchy-background"
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  ScreenMoveRemap {
    id: remapGuard
    window: panel
  }

  readonly property string screenName: modelData ? modelData.name : ""
  readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
  readonly property int workspaceId: hyprMonitor && hyprMonitor.activeWorkspace ? hyprMonitor.activeWorkspace.id : 0
  // Special workspaces (negative ids) overlay a regular one; keep showing
  // that one's image.
  property int shownWorkspace: 1
  onWorkspaceIdChanged: if (workspaceId > 0) shownWorkspace = workspaceId
  Component.onCompleted: if (workspaceId > 0) shownWorkspace = workspaceId

  // Decode straight to the monitor's physical pixel size: enough for a
  // crop-to-fill, a fraction of the source image's memory.
  readonly property size decodeSize: {
    var w = hyprMonitor ? hyprMonitor.width : Math.ceil(width * Screen.devicePixelRatio)
    var h = hyprMonitor ? hyprMonitor.height : Math.ceil(height * Screen.devicePixelRatio)
    var transform = hyprMonitor && hyprMonitor.lastIpcObject ? Number(hyprMonitor.lastIpcObject.transform || 0) : 0
    return transform % 2 === 1 ? Qt.size(h, w) : Qt.size(w, h)
  }

  // Renderer contract: selection, warm paths, revisions, transition settings,
  // instant requests, theme completion and the two desktop picker actions.
  readonly property string requestedImage: renderer.previewImage || renderer.imageFor(screenName, shownWorkspace)
  readonly property var keep: renderer.residentFor(screenName)
  property var failures: ({})
  property string loadError: ""
  function keyFor(path) { return path ? JSON.stringify([path, renderer.imageRevision(path)]) : "" }
  readonly property string targetImage: {
    renderer.catalogGeneration
    if (requestedImage && !failures[keyFor(requestedImage)]) return requestedImage
    for (var i = 0; i < renderer.images.length; i++) {
      if (!failures[keyFor(renderer.images[i])]) return renderer.images[i]
    }
    return ""
  }
  readonly property string targetKey: keyFor(targetImage)
  property string displayedKey: ""
  property string incomingKey: ""
  readonly property string displayedImage: displayedKey ? JSON.parse(displayedKey)[0] : ""
  readonly property string incomingImage: incomingKey ? JSON.parse(incomingKey)[0] : ""
  property real incomingProgress: 0
  property string activeStyle: "fade"
  property int activeMs: 0
  property int activeThemeRequest: 0
  property int consumedInstant: 0
  property bool primed: false
  property int residentCount: 0

  onTargetKeyChanged: Qt.callLater(syncFrames)
  onKeepChanged: Qt.callLater(syncFrames)
  onDisplayedKeyChanged: Qt.callLater(syncFrames)
  onIncomingKeyChanged: Qt.callLater(syncFrames)
  onPrimedChanged: Qt.callLater(syncFrames)
  Connections {
    target: renderer
    function onCatalogGenerationChanged() {
      panel.failures = ({})
      panel.loadError = ""
      Qt.callLater(panel.syncFrames)
    }
    function onThemeReadyRequestChanged() { Qt.callLater(panel.syncFrames) }
    function onInstantSerialChanged() { Qt.callLater(panel.syncFrames) }
  }

  ListModel { id: frames }
  function syncFrames() {
    var wanted = {}
    function add(key) { if (key) wanted[key] = true }
    // Resource membership is independent of catalog membership. Never reopen
    // an outgoing file to bridge a pool/theme change: retain its actual texture.
    add(displayedKey)
    add(incomingKey)
    add(targetKey)
    if (primed) keep.forEach(function(path) { var key = keyFor(path); if (!failures[key]) add(key) })
    for (var i = frames.count - 1; i >= 0; i--) {
      var key = frames.get(i).frameKey
      if (!wanted[key]) frames.remove(i)
      else delete wanted[key]
    }
    Object.keys(wanted).forEach(function(key) {
      frames.append({frameKey: key, path: JSON.parse(key)[0]})
    })
    for (var j = 0; j < slots.count; j++) {
      var slot = slots.itemAt(j)
      if (slot && slot.frameKey === targetKey && slot.ready) beginTransition(targetKey)
    }
  }
  function failed(key) {
    if (failures[key]) return
    var next = Object.assign({}, failures)
    next[key] = true
    failures = next
    if (key === keyFor(requestedImage)) {
      loadError = "Requested background is unavailable; trying the pool and retaining the last good image."
      console.warn("Backgrounds: " + loadError)
    }
    Qt.callLater(syncFrames)
  }
  function beginTransition(key) {
    if (key !== targetKey) return
    if (targetImage === requestedImage) loadError = ""
    primed = true
    var instant = renderer.instantFor(screenName, targetImage)
    var cut = instant > consumedInstant
    if (cut) consumedInstant = instant
    var request = renderer.themeReadyRequest
    if (incomingKey === key && !cut) {
      // A completed catalog snapshot can confirm this in-flight target.
      activeThemeRequest = request
      return
    }
    if (displayedKey === key && !incomingKey) {
      renderer.applyPendingTheme(request)
      return
    }
    fade.stop()
    // An interrupted transition's incoming frame is already ready and retained.
    if (incomingKey) displayedKey = incomingKey
    incomingKey = ""
    incomingProgress = 0
    activeStyle = renderer.transitionStyle
    activeMs = renderer.transitionMs
    activeThemeRequest = request
    if (!displayedKey || cut || activeStyle === "cut" || activeMs === 0 || key === displayedKey) {
      displayedKey = key
      renderer.applyPendingTheme(request)
      return
    }
    incomingKey = key
    fade.restart()
  }

  NumberAnimation {
    id: fade
    target: panel
    property: "incomingProgress"
    from: 0
    to: 1
    duration: panel.activeMs
    easing.type: panel.activeStyle === "slide" || panel.activeStyle === "zoom" ? Easing.OutCubic
               : panel.activeStyle === "reveal" ? Easing.InOutCubic : Easing.InOutQuad
    onFinished: {
      if (panel.incomingKey) panel.displayedKey = panel.incomingKey
      panel.incomingKey = ""
      panel.incomingProgress = 0
      renderer.applyPendingTheme(panel.activeThemeRequest)
    }
  }

  RevealMask {
    id: revealMask
    anchors.fill: parent
    progress: panel.incomingProgress
    active: panel.incomingImage !== "" && panel.activeStyle === "reveal"
  }

  Repeater {
    id: slots
    model: frames

    // Each resident image sits in a slot that the transition moves,
    // clips, scales, fades or masks; the image itself never changes.
    Item {
      id: slot
      required property int index
      required property string path
      required property string frameKey
      readonly property bool ready: frame.status === Image.Ready

      readonly property bool incoming: frameKey === panel.incomingKey
      readonly property bool outgoing: frameKey === panel.displayedKey && panel.incomingImage !== ""
      readonly property string style: panel.activeStyle
      readonly property real progress: panel.incomingProgress

      x: incoming && style === "slide" ? (1 - progress) * panel.width
       : outgoing && style === "slide" ? -progress * panel.width : 0
      y: 0
      width: incoming && style === "wipe" ? Math.round(progress * panel.width) : panel.width
      height: panel.height
      clip: incoming && style === "wipe"
      opacity: incoming && (style === "fade" || style === "zoom") ? progress : 1
      scale: incoming && style === "zoom" ? 1.08 - 0.08 * progress : 1
      transformOrigin: Item.Center
      visible: frameKey === panel.displayedKey || incoming
      z: incoming ? 2 : 1

      layer.enabled: incoming && style === "reveal"
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: revealMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.02
      }

      Image {
        id: frame
        readonly property bool wanted: slot.frameKey === panel.targetKey
        property bool counted: false

        x: 0
        y: 0
        width: panel.width
        height: panel.height
        source: Util.fileUrl(slot.path)
        sourceSize: panel.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: false

        onWantedChanged: if (wanted && status === Image.Ready) Qt.callLater(panel.syncFrames)
        Component.onDestruction: if (counted) panel.residentCount -= 1
        onStatusChanged: {
          if (status === Image.Ready && !counted) { counted = true; panel.residentCount += 1 }
          else if (status !== Image.Ready && counted) { counted = false; panel.residentCount -= 1 }
          if (status === Image.Ready && wanted) Qt.callLater(panel.syncFrames)
          if (status === Image.Error) panel.failed(slot.frameKey)
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onDoubleClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) renderer.openThemeSwitcher()
      else renderer.openSelector()
      mouse.accepted = true
    }
  }
}
