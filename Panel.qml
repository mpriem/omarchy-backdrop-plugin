import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Config.js" as Config

// Settings panel for the background renderer: a bar button with a popup in
// the standard Omarchy panel style. State, the keyboard cursor and the
// actions live here; the controls are ChipRow, PickerList, IntervalWheels
// and TransitionSection.
//
// The service owns persistence. This panel observes the file and submits
// validated operations over the existing background IPC boundary.
Panel {
  id: root
  moduleName: "backgrounds"
  ipcTarget: "backgrounds"

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/background.json"
  readonly property string themeName: catalog.themeName
  readonly property string userBackgroundsDir: catalog.userBackgroundsDir
  readonly property var images: catalog.images
  readonly property var config: configStore.config

  readonly property string mode: Config.mode(config)
  readonly property string workspaceAssign: Config.workspaceAssign(config)
  readonly property var rotate: Config.rotate(config)
  readonly property var transition: Config.transition(config)
  readonly property var pins: Config.pins(config, themeName)
  readonly property var workspaces: Config.workspaces(config, themeName)
  readonly property var screens: Quickshell.screens
  property int focusedWorkspaceId: 1
  readonly property int activeWorkspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
  property var regularWorkspaces: ({})
  function updateFocusedWorkspace() {
    if (activeWorkspaceId > 0) {
      var next = Object.assign({}, regularWorkspaces)
      next[focusedScreenName] = activeWorkspaceId
      regularWorkspaces = next
    }
    focusedWorkspaceId = regularWorkspaces[focusedScreenName] || 1
  }
  onActiveWorkspaceIdChanged: updateFocusedWorkspace()
  readonly property string focusedScreenName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : (screens.length > 0 ? screens[0].name : "")

  readonly property color fg: root.barForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)

  // ---- the one picker: which workspace / monitor it edits ----
  property string editWorkspace: "1"
  property string editScreen: ""
  property string search: ""
  onFocusedWorkspaceIdChanged: if (!opened) editWorkspace = String(focusedWorkspaceId)
  onFocusedScreenNameChanged: { updateFocusedWorkspace(); if (!opened || !editScreen) editScreen = focusedScreenName }
  Component.onCompleted: { updateFocusedWorkspace(); editWorkspace = String(focusedWorkspaceId); editScreen = focusedScreenName }
  onOpenedChanged: if (opened) { search = ""; picker.clearSearch(); editWorkspace = String(focusedWorkspaceId); editScreen = focusedScreenName; cursorActive = false; focusSection = "" }

  // ---- keyboard: one cursor over the panel, the kit's recipe ----
  // Tab / Shift+Tab move between sections, arrows or h j k l between a
  // section's options (Up/Down leave a single-row section for the next
  // one), Enter confirms. The slider slides and the drums turn as the
  // keys move. No highlight until the keyboard or the mouse enters.
  property bool cursorActive: false
  property string focusSection: ""
  property int selectedIndex: 0
  readonly property var sections: {
    var list = [{ id: "mode", n: Config.MODES.length, cols: Config.MODES.length }]
    if (mode === "classic") list.push({ id: "classic", n: 2, cols: 2 })
    else if (mode === "workspace" || mode === "pinned") {
      if (mode === "workspace") list.push({ id: "assign", n: 2, cols: 2 })
      if (picking) {
        var targets = mode === "pinned" ? screenOptions.length : workspaceOptions.length
        list.push({ id: "target", n: targets, cols: targets })
        list.push({ id: "search", n: 1, cols: 1 })
        list.push({ id: "picker", n: pickerRows.length, cols: 1 })
      }
    } else {
      list.push({ id: "interval", n: 2, cols: 2 })
      list.push({ id: "order", n: 2, cols: 2 })
      list.push({ id: "scope", n: 2, cols: 2 })
      list.push({ id: "rotate-now", n: 1, cols: 1 })
    }
    list.push({ id: "style", n: Config.TRANSITION_OPTIONS.length, cols: 3 })
    list.push({ id: "duration", n: 1, cols: 1 })
    list.push({ id: "try", n: 1, cols: 1 })
    return list
  }
  function section(id) {
    for (var i = 0; i < sections.length; i++) if (sections[i].id === id) return sections[i]
    return null
  }
  function setCursor(id, index) {
    var sec = section(id)
    if (!sec || sec.n === 0) return
    cursorActive = true; focusSection = id; selectedIndex = Math.max(0, Math.min(sec.n - 1, index))
    Qt.callLater(ensureCursorVisible)
  }
  function reconcileCursor() {
    var options = screenOptions.map(function(o) { return o.value })
    if (options.indexOf(editScreen) < 0) editScreen = options[0] || ""
    var workspaces = workspaceOptions.map(function(o) { return o.value })
    if (workspaces.indexOf(editWorkspace) < 0) editWorkspace = workspaces[0] || "1"
    var sec = section(focusSection)
    if (!sec) { focusSection = ""; cursorActive = false; selectedIndex = 0 }
    else selectedIndex = Math.max(0, Math.min(sec.n - 1, selectedIndex))
  }
  onSectionsChanged: Qt.callLater(reconcileCursor)
  onScreenOptionsChanged: Qt.callLater(reconcileCursor)
  onWorkspaceOptionsChanged: Qt.callLater(reconcileCursor)
  onFocusSectionChanged: Qt.callLater(ensureCursorVisible)
  onSelectedIndexChanged: Qt.callLater(ensureCursorVisible)
  function ensureCursorVisible() {
    var item = {mode: modeChips, classic: classicControls, assign: assignChips,
      target: targetChips, search: picker, picker: picker, interval: intervalWheels,
      order: orderChips, scope: scopeChips, "rotate-now": rotateButton,
      style: transitionSection, duration: transitionSection, try: transitionSection}[focusSection]
    if (!item || !cursorActive) return
    var rect = Qt.rect(0, 0, item.width, item.height)
    if (item === picker) rect = picker.cursorRect(focusSection === "search" ? -1 : selectedIndex)
    else if (item === transitionSection) rect = transitionSection.cursorRect(focusSection, selectedIndex)
    else if (item.cursorRect) rect = item.cursorRect(selectedIndex)
    var top = item.mapToItem(column, rect.x, rect.y).y
    var bottom = top + rect.height
    var next = viewport.contentY
    if (top < next) next = top
    else if (bottom > next + viewport.height) next = bottom - viewport.height
    viewport.contentY = Math.max(0, Math.min(Math.max(0, viewport.contentHeight - viewport.height), next))
  }
  // the cursor as a control sees it: its index within `id`, or -1
  function cursorFor(id) { return cursorActive && focusSection === id ? selectedIndex : -1 }
  // where the cursor lands entering a section: on its current value
  function homeIndex(id) {
    var opts = { mode: Config.MODES, assign: Config.ASSIGN_OPTIONS.map(function(o) { return o.value }),
                 order: Config.ORDER_OPTIONS.map(function(o) { return o.value }), scope: Config.SCOPE_OPTIONS.map(function(o) { return o.value }),
                 style: Config.TRANSITION_OPTIONS.map(function(o) { return o.value }) }
    var value = { mode: mode, assign: workspaceAssign, order: rotate.order, scope: rotate.scope, style: transition.style }[id]
    if (opts[id]) return Math.max(0, opts[id].indexOf(value))
    if (id === "target") {
      var t = mode === "pinned" ? screenOptions.map(function(o) { return o.value }).indexOf(editScreen) : workspaceOptions.map(function(o) { return o.value }).indexOf(editWorkspace)
      return Math.max(0, t)
    }
    if (id === "picker") { for (var i = 0; i < pickerRows.length; i++) if (pickerRows[i].path === targetValue) return i }
    return 0
  }
  function moveSection(direction) {
    var at = -1
    for (var i = 0; i < sections.length; i++) if (sections[i].id === focusSection) at = i
    var next = at < 0 ? (direction > 0 ? 0 : sections.length - 1) : (at + direction + sections.length) % sections.length
    setCursor(sections[next].id, homeIndex(sections[next].id))
    if (sections[next].id === "picker") picker.showIndex(selectedIndex)
    // landing on the search box by keyboard starts typing in it right away
    // (h j k l would otherwise be taken as moves)
    if (sections[next].id === "search") picker.focusSearch(false)
  }
  function moveCursor(dx, dy) {
    if (!cursorActive || !section(focusSection)) { moveSection(1); return }
    var sec = section(focusSection)
    if (sec.id === "duration") { if (dx) setTransition("ms", transition.ms + dx * 50); else if (dy) moveSection(dy); return }
    if (sec.id === "interval") {
      if (dx) selectedIndex = Math.max(0, Math.min(1, selectedIndex + dx))
      else if (dy) turnInterval(selectedIndex === 0 ? "hours" : "minutes", -dy)
      return
    }
    var next = selectedIndex + dx + dy * sec.cols
    if (dx && (next < 0 || next >= sec.n)) return
    if (dy && (next < 0 || next >= sec.n)) { moveSection(dy); return }
    selectedIndex = next
    if (sec.id === "picker") picker.showIndex(selectedIndex)
  }
  function activateCursor() {
    if (!cursorActive) { moveSection(1); return }
    var sec = section(focusSection)
    if (!sec || selectedIndex < 0 || selectedIndex >= sec.n) return
    var i = selectedIndex
    switch (focusSection) {
    case "mode": setMode(Config.MODES[i]); break
    case "classic": if (i === 0) chooseBackground(); else nextBackground(); break
    case "assign": setWorkspaceAssign(Config.ASSIGN_OPTIONS[i].value); break
    case "target": if (mode === "pinned") editScreen = screenOptions[i].value; else editWorkspace = workspaceOptions[i].value; break
    case "search": picker.focusSearch(true); break
    case "picker": if (pickerRows[i]) pickForTarget(pickerRows[i].path); break
    case "order": setRotate("order", Config.ORDER_OPTIONS[i].value); break
    case "scope": setRotate("scope", Config.SCOPE_OPTIONS[i].value); break
    case "rotate-now": rotateNow(); break
    case "style": setTransition("style", Config.TRANSITION_OPTIONS[i].value); break
    case "try": tryTransition(); break
    }
  }

  // the picker only shows where a pick takes effect
  readonly property bool picking: mode === "pinned" || (mode === "workspace" && workspaceAssign === "fixed")
  readonly property string targetValue: mode === "pinned" ? (pins[editScreen] || "") : (workspaces[editWorkspace] || "")
  readonly property string fallbackLabel: mode === "pinned" || workspaceAssign === "fixed" ? "Pool's first image" : "From the pool"

  function pickForTarget(path) {
    if (mode === "pinned") pin(editScreen, path)
    else assignWorkspace(Number(editWorkspace), path)
  }
  function turnInterval(drum, direction) {
    if (drum === "hours") setInterval((editHours + direction + 25) % 25, editMinutes)
    else setInterval(editHours, (editMinutes + direction + 60) % 60)
  }

  function matches(path, query) {
    if (!query) return true
    var q = query.toLowerCase()
    return Config.label(path).toLowerCase().indexOf(q) >= 0 || String(path).split("/").pop().toLowerCase().indexOf(q) >= 0
  }

  readonly property var pickerRows: {
    var rows = [{ path: "", label: fallbackLabel, file: "" }]
    if (mode === "workspace") rows.push({ path: Config.RANDOM, label: Config.RANDOM_LABEL, file: Config.RANDOM_DESCRIPTION })
    for (var i = 0; i < images.length; i++) {
      if (matches(images[i], search)) rows.push({ path: images[i], label: Config.label(images[i]), file: String(images[i]).split("/").pop() })
    }
    return rows
  }

  readonly property var workspaceOptions: {
    var list = []
    for (var i = 1; i <= 10; i++) list.push({ value: String(i), label: i === 10 ? "0" : String(i) })
    var ids = {}
    for (var j = 1; j <= 10; j++) ids[j] = true
    ids[focusedWorkspaceId] = true
    Hyprland.workspaces.values.forEach(function(ws) { if (ws.id > 0) ids[ws.id] = true })
    Object.keys(workspaces).forEach(function(id) { ids[id] = true })
    Object.keys(ids).map(Number).sort(function(a, b) { return a - b }).forEach(function(id) {
      if (id > 10) list.push({value: String(id), label: String(id)})
    })
    return list
  }
  readonly property var screenOptions: screens.map(function(s) { return { value: s.name, label: s.name } })

  // ---- the interval drums: hours 0-24, minutes 0-59 ----
  property int editHours: 0
  property int editMinutes: 30
  property bool intervalDirty: false
  function syncInterval() {
    if (intervalDirty) return
    var p = Config.intervalParts(rotate.every)
    editHours = p.hours
    editMinutes = p.hours === 0 ? Math.max(1, p.minutes) : p.minutes
  }
  onRotateChanged: syncInterval()
  onConfigChanged: syncInterval()
  function setInterval(hours, minutes) {
    if (hours >= 24) minutes = 0
    if (hours === 0 && minutes === 0) minutes = 1
    editHours = hours
    editMinutes = minutes
    intervalDirty = true
    intervalCommit.restart()
  }
  Timer {
    id: intervalCommit
    interval: 500
    repeat: false
    onTriggered: {
      root.intervalDirty = false
      root.setRotate("every", Config.intervalSpec(root.editHours, root.editMinutes))
    }
  }

  // Queue commands in order even when a slider emits several quick edits.
  property var commandQueue: []
  property string commandError: ""
  readonly property bool commandPending: commandProc.running || commandQueue.length > 0
  function command(args) {
    commandQueue = commandQueue.concat([args])
    runCommand()
  }
  function runCommand() {
    if (commandProc.running || !commandQueue.length) return
    commandProc.command = ["omarchy-shell", "background"].concat(commandQueue[0])
    commandQueue = commandQueue.slice(1)
    commandError = ""
    commandProc.running = true
  }
  function save(operation) { command(["configure", JSON.stringify(operation)]) }
  function setMode(name) { save({type: "mode", value: name}) }
  function setWorkspaceAssign(name) { save({type: "workspaceAssign", value: name}) }
  function assignWorkspace(workspaceId, path) { save({type: "assign", theme: themeName, target: workspaceId, value: path}) }
  function pin(screenName, path) { save({type: "pin", theme: themeName, target: screenName, value: path}) }
  function setRotate(key, value) { save({type: "rotate", key: key, value: value}) }
  function rotateNow() { command(["rotateNow"]) }
  function setTransition(key, value) { save({type: "transition", key: key, value: value}) }
  function tryTransition() { command(["previewTransition"]) }
  function chooseBackground() { close(); command(["choose"]) }
  function nextBackground() { Util.execArgv(["omarchy-theme-bg-next"]) }

  Process {
    id: commandProc
    property string response: ""
    stdout: StdioCollector { onStreamFinished: commandProc.response = text.trim() }
    onExited: function(code) {
      if (code !== 0 || response.indexOf("error:") === 0) {
        root.commandError = code !== 0 ? "Background settings service is unavailable." : response
        Util.execArgv(["notify-send", "Backgrounds", root.commandError])
      }
      response = ""
      configStore.reload()
      Qt.callLater(root.runCommand)
    }
  }
  ConfigStore { id: configStore; path: root.configPath }
  BackgroundCatalog { id: catalog }

  // ---- bar button + popup ----
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰸉"
    tooltipText: root.commandError || configStore.error || (root.commandPending ? "Saving background settings…" : "Background")
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: picker.searching
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.cursorActive = true; root.moveSection(direction) }

      Flickable {
        id: viewport
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(14)

          PanelHero {
            title: "Background"
            meta: Config.MODE_DESCRIPTIONS[root.mode]
            detail: root.images.length + (root.images.length === 1 ? " image" : " images")
            foreground: root.fg
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰸉"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { foreground: root.fg }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "MODE"; foreground: root.fg; fontFamily: root.fontFamily }

            ChipRow {
              id: modeChips
              width: parent.width
              options: Config.MODES.map(function(m) { return { value: m, label: Config.MODE_SHORT[m] } })
              value: root.mode
              cursorIndex: root.cursorFor("mode")
              foreground: root.fg
              fontFamily: root.fontFamily
              onChanged: function(value) { root.setMode(value) }
              onHovered: function(index) { root.setCursor("mode", index) }
            }
          }

          // ---- classic mode ----
          Column {
            id: classicControls
            visible: root.mode === "classic"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "BACKGROUND"; foreground: root.fg; fontFamily: root.fontFamily }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Button {
                width: (parent.width - parent.spacing) / 2
                hasCursor: root.cursorFor("classic") === 0
                onHovered: function(h) { if (h) root.setCursor("classic", 0) }
                text: "Choose…"
                iconText: "󰋩"
                foreground: root.fg
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.chooseBackground()
              }

              Button {
                width: (parent.width - parent.spacing) / 2
                hasCursor: root.cursorFor("classic") === 1
                onHovered: function(h) { if (h) root.setCursor("classic", 1) }
                text: "Next"
                iconText: "󰒭"
                foreground: root.fg
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.nextBackground()
              }
            }
          }

          // ---- workspace / pinned: one picker, aimed at a target ----
          Column {
            visible: root.mode === "workspace" || root.mode === "pinned"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: root.mode === "pinned" ? "MONITORS" : "WORKSPACES"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            ChipRow {
              id: assignChips
              visible: root.mode === "workspace"
              width: parent.width
              options: Config.ASSIGN_OPTIONS
              value: root.workspaceAssign
              cursorIndex: root.cursorFor("assign")
              foreground: root.fg
              fontFamily: root.fontFamily
              onChanged: function(value) { root.setWorkspaceAssign(value) }
              onHovered: function(index) { root.setCursor("assign", index) }
            }

            Text {
              visible: root.mode === "workspace"
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: Config.ASSIGN_DESCRIPTIONS[root.workspaceAssign]
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            ChipRow {
              id: targetChips
              columns: root.mode === "workspace" ? Math.min(10, options.length) : Math.max(1, options.length)
              visible: root.picking
              width: parent.width
              options: root.mode === "pinned" ? root.screenOptions : root.workspaceOptions
              value: root.mode === "pinned" ? root.editScreen : root.editWorkspace
              cursorIndex: root.cursorFor("target")
              foreground: root.fg
              fontFamily: root.fontFamily
              onChanged: function(value) { if (root.mode === "pinned") root.editScreen = value; else root.editWorkspace = value }
              onHovered: function(index) { root.setCursor("target", index) }
            }

            PickerList {
              revision: catalog.generation
              id: picker
              visible: root.picking
              width: parent.width
              rows: root.pickerRows
              current: root.targetValue
              active: root.opened
              // -2 puts the cursor on the search box, an index on a row
              cursorIndex: root.cursorActive ? (root.focusSection === "search" ? -2 : root.focusSection === "picker" ? root.selectedIndex : -1) : -1
              foreground: root.fg
              fontFamily: root.fontFamily
              onSearchChanged: root.search = search
              onPicked: function(path) { root.pickForTarget(path) }
              onHovered: function(index) { root.setCursor("picker", index) }
              onSearchHovered: root.setCursor("search", 0)
              onSearchLeft: function(direction) { keyCatcher.forceActiveFocus(); if (direction !== 0) root.moveSection(direction) }
            }
          }

          // ---- rotate mode ----
          Column {
            visible: root.mode === "rotate"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "ROTATION"; foreground: root.fg; fontFamily: root.fontFamily }

            IntervalWheels {
              id: intervalWheels
              actualSpec: root.intervalDirty ? Config.intervalSpec(root.editHours, root.editMinutes) : root.rotate.every
              width: parent.width
              hours: root.editHours
              minutes: root.editMinutes
              cursorIndex: root.cursorFor("interval")
              foreground: root.fg
              fontFamily: root.fontFamily
              onHoursTurned: function(v) { root.setInterval(v, root.editMinutes) }
              onMinutesTurned: function(v) { root.setInterval(root.editHours, v) }
              onHovered: function(index) { root.setCursor("interval", index) }
            }

            ChipRow {
              id: orderChips
              width: parent.width
              options: Config.ORDER_OPTIONS
              value: root.rotate.order
              cursorIndex: root.cursorFor("order")
              foreground: root.fg
              fontFamily: root.fontFamily
              onChanged: function(value) { root.setRotate("order", value) }
              onHovered: function(index) { root.setCursor("order", index) }
            }

            ChipRow {
              id: scopeChips
              width: parent.width
              options: Config.SCOPE_OPTIONS
              value: root.rotate.scope
              cursorIndex: root.cursorFor("scope")
              foreground: root.fg
              fontFamily: root.fontFamily
              onChanged: function(value) { root.setRotate("scope", value) }
              onHovered: function(index) { root.setCursor("scope", index) }
            }

            Button {
              id: rotateButton
              width: parent.width
              hasCursor: root.cursorFor("rotate-now") === 0
              onHovered: function(h) { if (h) root.setCursor("rotate-now", 0) }
              text: "Next image now"
              iconText: "󰑐"
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.rotateNow()
            }
          }

          TransitionSection {
            id: transitionSection
            width: parent.width
            style: root.transition.style
            ms: root.transition.ms
            cursorSection: root.cursorActive ? root.focusSection : ""
            cursorIndex: root.selectedIndex
            bar: root.bar
            foreground: root.fg
            fontFamily: root.fontFamily
            onStylePicked: function(value) { root.setTransition("style", value) }
            onDurationChanged: function(v) { root.setTransition("ms", v) }
            onTryRequested: root.tryTransition()
            onHovered: function(section, index) { root.setCursor(section, index) }
          }

          PanelSeparator { foreground: root.fg }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.images.length + (root.images.length === 1 ? " image" : " images") + " for " + (root.themeName || "this theme")
              + " · add your own to " + root.userBackgroundsDir.replace(root.home, "~")
              + "\nTab ⇧Tab section · ←↑↓→ hjkl option · Enter confirm"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
