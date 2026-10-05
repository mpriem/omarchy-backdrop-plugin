import QtQuick
import Quickshell.Io
import "Config.js" as Config

// One service-owned writer. Panels use this component only as an observer.
// Reload before each operation; an external edit after that read is last-writer-wins.
Item {
  id: store
  required property string path
  property bool writable: false
  property var config: Config.normalizeConfig({})
  property bool valid: false
  property bool seenFile: false
  property bool saving: false
  property string error: ""
  property var pending: null
  signal failed(string message)

  function fail(message) {
    error = message
    console.warn("Backgrounds: " + message)
    failed(message)
  }
  function reload() { file.reload() }
  function mutate(operation) {
    if (!writable) return "error: settings service is read-only"
    file.reload()
    file.waitForJob()
    if (!valid) return "error: " + (error || "settings have not loaded")
    var next
    try { next = Config.applyOperation(config, operation) }
    catch (e) { return "error: " + e.message }
    if (Config.serialize(next) === Config.serialize(config) && seenFile) return "ok"
    pending = next
    saving = true
    file.setText(Config.serialize(next))
    file.waitForJob()
    return error ? "error: " + error : "ok"
  }
  FileView {
    id: file
    path: store.path
    watchChanges: true
    printErrors: false
    blockWrites: true
    onLoaded: {
      store.seenFile = true
      try {
        var value = JSON.parse(text())
        if (!Config.isObject(value)) throw new Error("settings root must be an object")
        store.config = Config.normalizeConfig(value)
        store.valid = true
        store.error = ""
      } catch (e) {
        store.valid = false
        store.fail("Settings are invalid; keeping the last valid settings. Repair background.json before editing.")
      }
    }
    onLoadFailed: function(error) {
      store.valid = error === FileViewError.FileNotFound && !store.seenFile
      if (store.valid) store.error = ""
      else store.fail("Cannot read background settings (" + FileViewError.toString(error) + ").")
    }
    onFileChanged: if (!store.saving) reload()
    onSaved: {
      store.config = store.pending
      store.pending = null
      store.saving = false
      store.seenFile = true
      store.valid = true
      store.error = ""
    }
    onSaveFailed: function(error) {
      store.pending = null
      store.saving = false
      store.fail("Cannot save background settings (" + FileViewError.toString(error) + ").")
    }
  }
}
