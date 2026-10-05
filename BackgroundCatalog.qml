import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

// Directory signals request a completed snapshot. Polling also observes byte replacement,
// symlink repoints, and recovery of directories that did not exist at startup.
Item {
  id: catalog
  property string home: Quickshell.env("HOME")
  property var extraPaths: []
  property var snapshot: ({theme: "", themeDirectory: "", images: [], revisions: {}})
  readonly property string themeName: snapshot.theme
  readonly property var images: snapshot.images
  readonly property string userBackgroundsDir: home + "/.config/omarchy/backgrounds/" + themeName
  property int generation: 0
  property string error: ""
  property bool refreshPending: false
  property int requestSerial: 0
  property int completedSerial: 0
  signal refreshed()

  function folderUrl(path) { return "file://" + path.split("/").map(encodeURIComponent).join("/") }
  function revision(path) { return snapshot.revisions[path] || "missing" }
  function refresh() {
    requestSerial += 1
    if (scan.running) refreshPending = true
    else { scan.serial = requestSerial; scan.running = true }
  }
  onExtraPathsChanged: Qt.callLater(refresh)
  Component.onCompleted: refresh()
  FolderListModel {
    id: userFolder
    folder: catalog.themeName ? catalog.folderUrl(catalog.userBackgroundsDir) : ""
    showDirs: false
    onCountChanged: Qt.callLater(catalog.refresh)
    onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(catalog.refresh)
  }
  FolderListModel {
    id: themeFolder
    folder: catalog.snapshot.themeDirectory ? catalog.folderUrl(catalog.snapshot.themeDirectory) : ""
    showDirs: false
    onCountChanged: Qt.callLater(catalog.refresh)
    onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(catalog.refresh)
  }
  Connections {
    target: userFolder
    function onDataChanged() { Qt.callLater(catalog.refresh) }
    function onModelReset() { Qt.callLater(catalog.refresh) }
  }
  Connections {
    target: themeFolder
    function onDataChanged() { Qt.callLater(catalog.refresh) }
    function onModelReset() { Qt.callLater(catalog.refresh) }
  }
  Timer { interval: 2000; running: true; repeat: true; onTriggered: catalog.refresh() }
  Process {
    id: scan
    property int serial: 0
    command: ["python3", decodeURIComponent(Qt.resolvedUrl("catalog.py").toString().replace(/^file:\/\//, "")), catalog.home, JSON.stringify(catalog.extraPaths)]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var next = JSON.parse(text)
          if (JSON.stringify(next) !== JSON.stringify(catalog.snapshot)) {
            catalog.snapshot = next
            catalog.generation += 1
          }
          catalog.error = ""
          catalog.completedSerial = scan.serial
          catalog.refreshed()
        } catch (e) { catalog.error = "Cannot read background catalog; retaining the previous pool." }
      }
    }
    onExited: {
      if (catalog.error) console.warn("Backgrounds: " + catalog.error)
      if (catalog.refreshPending) { catalog.refreshPending = false; Qt.callLater(catalog.refresh) }
    }
  }
}
