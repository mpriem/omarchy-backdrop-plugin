import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui
import "Config.js" as Config
import "Selection.js" as Selection

// Desktop background renderer with four modes, configured through
// ~/.config/omarchy/background.json (see Config.js) -- written by the
// service store via panel/IPC operations, or by hand:
//
//   classic    one image on every monitor, Omarchy's default behavior
//   workspace  every monitor shows the image mapped to its own active
//              workspace (the theme's images dealt out to workspaces 1..N,
//              wrapping, or only explicit assignments), with picks on top
//   pinned     one picked image per monitor
//   rotate     a new image every so often, ordered or random, the same on
//              every monitor or different per monitor
//
// The theme's images (user folder first, then the theme's own, sorted by
// name -- the same set and order as omarchy-theme-bg-next) are the pool for
// workspace and rotate modes and the fallback for the others. Picking a
// background the usual way (double-click, the switcher, omarchy-theme-bg-set)
// does the natural thing for the active mode.
//
// Bounded per-screen residency preloads likely choices; cold loads retain the
// outgoing texture until their replacement is ready.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"
  readonly property string configPath: home + "/.config/omarchy/background.json"

  // How many images a monitor keeps decoded besides the one on screen --
  // only ones the active mode can actually show there (see residentFor);
  // classic keeps none, pinned none beyond the pin, assigned-only just the
  // assignments. Each costs roughly monitorWidth * monitorHeight * 4 bytes
  // of GPU memory, and it is released as soon as it stops being needed.
  property int maxResident: 6
  // How images change (Config.TRANSITION_OPTIONS) and how long it takes;
  // one setting for every kind of change, incl. Omarchy's theme switch.
  readonly property var transitionConfig: Config.transition(config)
  readonly property string transitionStyle: transitionConfig.style
  readonly property int transitionMs: transitionConfig.ms
  // "Try it": briefly targets another pool image on every monitor, then
  // goes back, so the chosen transition plays twice.
  property string previewImage: ""

  readonly property string themeName: catalog.themeName
  readonly property var images: catalog.images
  readonly property var config: configStore.config
  readonly property int catalogGeneration: catalog.generation
  function imageRevision(path) { return catalog.revision(path) }
  readonly property string mode: Config.mode(config)
  readonly property string workspaceAssign: Config.workspaceAssign(config)
  readonly property var rotateConfig: Config.rotate(config)
  readonly property int rotateMs: Config.parseInterval(rotateConfig.every)
  readonly property var pins: Config.pins(config, themeName)
  readonly property var workspacePicks: Config.workspaces(config, themeName)
  // "random" assignments, rolled here: each such workspace gets an image no
  // other workspace has (explicitly or by an earlier roll) while any are
  // left, else any pool image. Kept for the session; re-rolled only when
  // the pool or the assignments change.
  property var randomPicks: ({})
  onImagesChanged: { rollRandom(); reconcileRotation() }
  onWorkspacePicksChanged: rollRandom()
  function rollRandom() {
    var next = {}
    var taken = []
    var ws
    for (ws in workspacePicks) if (workspacePicks[ws] !== Config.RANDOM) taken.push(workspacePicks[ws])
    for (ws in workspacePicks) {
      if (workspacePicks[ws] !== Config.RANDOM) continue
      var kept = randomPicks[ws]
      if (kept && images.indexOf(kept) >= 0 && taken.indexOf(kept) < 0) { next[ws] = kept; taken.push(kept) }
    }
    for (ws in workspacePicks) {
      if (workspacePicks[ws] !== Config.RANDOM || next[ws]) continue
      var pool = images.filter(function(p) { return taken.indexOf(p) < 0 })
      if (pool.length === 0) pool = images
      if (pool.length === 0) continue
      var pick = pool[Math.floor(Math.random() * pool.length)]
      next[ws] = pick
      taken.push(pick)
    }
    randomPicks = next
  }

  // classic mode: the current-background link's target
  property string classicImage: ""
  property var rotation: ({base: "", own: {}})
  property int rotationGeneration: 0
  property var previousPool: []
  property var previousScreens: []
  property var rotationOverrides: ({})
  readonly property var screenNames: Quickshell.screens.map(function(s) { return s.name })
  onScreenNamesChanged: reconcileRotation()
  readonly property string rotationPolicy: JSON.stringify(rotateConfig)
  onRotationPolicyChanged: { rotationOverrides = ({}); reconcileRotation() }
  onThemeNameChanged: { rotationOverrides = ({}); reconcileRotation() }
  onCatalogGenerationChanged: reconcileRotation()
  onModeChanged: {
    reconcileRotation()
    if (mode === "classic") { forceClassicRead = true; refreshClassic() }
  }
  function reconcileRotation() {
    rotation = Selection.reconcile(images, rotation, screenNames, previousPool, previousScreens, rotateConfig.scope)
    previousPool = images.slice()
    previousScreens = screenNames.slice()
    var overrides = {}
    Object.keys(rotationOverrides).forEach(function(name) {
      if (name === "*" || screenNames.indexOf(name) >= 0) overrides[name] = rotationOverrides[name]
    })
    rotationOverrides = overrides
    rotationGeneration += 1
    rearmRotate()
  }

  // An instant request is consumed by each matching screen, including cold loads.
  property int instantSerial: 0
  property var instantTargets: ({})
  function instantFor(screen, path) { return instantTargets[screen] === path ? instantSerial : 0 }

  // A theme switch hands us its colors; apply them once the first monitor
  // has the new theme's image up, so the palette flips with the picture.
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property bool themePending: false
  property int themeRequest: 0
  property int themeReadyRequest: 0
  property int themeCatalogRequest: 0

  property var plannedRotate: null
  readonly property int preloadMs: Math.min(3000, Math.max(500, Math.round(rotateMs / 4)))
  function planRotate() {
    return { generation: rotationGeneration,
      state: Selection.plan(images, rotation, rotateConfig, screenNames, Math.random) }
  }
  function plannedImageFor(screenName) {
    if (!plannedRotate || plannedRotate.generation !== rotationGeneration) return ""
    return Selection.rotationImage(images, plannedRotate.state, rotateConfig.scope, screenNames, screenName)
  }

  // What a monitor should be showing right now, by mode.
  function imageFor(screenName, workspaceId) {
    var first = images.length > 0 ? images[0] : ""
    if (mode === "classic") return classicImage || first
    if (mode === "pinned") return pins[screenName] || first
    if (mode === "rotate") return rotationOverrides[rotateConfig.scope === "same" ? "*" : screenName]
      || Selection.rotationImage(images, rotation, rotateConfig.scope, screenNames, screenName)
    return Selection.workspaceImage(images, workspacePicks, randomPicks, workspaceAssign, workspaceId)
  }

  // The images worth keeping warm on a monitor, most likely first, capped
  // at maxResident. Whatever is on screen is always kept, on top of this.
  function residentFor(screenName) {
    var list = []
    function add(p) { if (p && list.indexOf(p) < 0 && list.length < maxResident) list.push(p) }
    var n = images.length
    if (mode === "classic" || mode === "pinned" || n === 0) return list
    if (mode === "rotate") {
      // only the planned next image, and only during the lead before the tick
      add(plannedImageFor(screenName))
      return list
    }
    // workspace: the workspaces that exist on this monitor first, then the
    // rest of what the scheme can show
    var ids = []
    var all = Hyprland.workspaces.values
    for (var i = 0; i < all.length; i++) {
      var ws = all[i]
      if (ws.id > 0 && ws.monitor && ws.monitor.name === screenName) ids.push(ws.id)
    }
    ids.sort(function(a, b) { return a - b })
    for (var j = 0; j < ids.length; j++) add(imageFor(screenName, ids[j]))
    if (workspaceAssign === "fixed") {
      for (var key in workspacePicks) add(imageFor(screenName, Number(key)))
      add(images[0])
    } else {
      for (var k = 0; k < n; k++) add(images[k])
    }
    return list
  }

  function mutate(operation) { return configStore.mutate(operation) }

  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? monitor.name : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
  }

  function focusedWorkspaceId() {
    var monitor = Hyprland.focusedMonitor
    if (monitor && monitor.activeWorkspace && monitor.activeWorkspace.id > 0) return monitor.activeWorkspace.id
    for (var i = 0; i < panels.instances.length; i++) {
      if (panels.instances[i].screenName === focusedScreenName()) return panels.instances[i].shownWorkspace
    }
    return 1
  }

  function setMode(name) { return mutate({type: "mode", value: name}) }
  function setWorkspaceAssign(name) { return mutate({type: "workspaceAssign", value: name}) }
  function setRotate(key, value) { return mutate({type: "rotate", key: key, value: value}) }
  function pin(screenName, path) {
    return mutate({type: "pin", theme: themeName, target: screenName || focusedScreenName(), value: path})
  }
  function assignWorkspace(workspaceId, path) {
    return mutate({type: "assign", theme: themeName, target: workspaceId, value: path})
  }
  function clearWorkspacePicks() { return mutate({type: "clearWorkspacePicks", theme: themeName}) }

  // Timer.restart() would replace the `running` binding with a plain true,
  // leaving the timer ticking after leaving rotate mode; re-establish the
  // binding instead.
  readonly property bool rotating: mode === "rotate" && images.length > 1
  onRotatingChanged: rearmRotate()
  onRotateMsChanged: rearmRotate()
  function rearmRotate() {
    rotateTimer.stop()
    preloadTimer.stop()
    plannedRotate = null
    if (rotating) preloadTimer.start()
  }

  function rotateStep() {
    if (images.length === 0) return
    var plan = plannedRotate && plannedRotate.generation === rotationGeneration ? plannedRotate : planRotate()
    plannedRotate = null
    rotation = plan.state
    rotationOverrides = ({})
    instantTargets = ({})
  }

  // Picking a background does the natural thing for the active mode.
  function pick(path, instant) {
    path = String(path || "").trim()
    if (!Config.validPath(path)) return "error: image must be an absolute path"
    var result = "ok"
    // Set the request before publishing its target so ready preloads also cut.
    if (instant) {
      var targets = {}
      if (mode === "classic" || (mode === "rotate" && rotateConfig.scope === "same"))
        screenNames.forEach(function(name) { targets[name] = path })
      else targets[focusedScreenName()] = path
      instantTargets = targets
      instantSerial += 1
    } else instantTargets = ({})
    if (mode === "classic") classicImage = path
    else if (mode === "pinned") result = pin("", path)
    else if (mode === "rotate") {
      // An explicit per-monitor pick lasts until the next rotation tick.
      var overrides = Object.assign({}, rotationOverrides)
      overrides[rotateConfig.scope === "same" ? "*" : focusedScreenName()] = path
      rotationOverrides = overrides
      var own = Object.assign({}, rotation.own)
      if (rotateConfig.scope === "different") own[focusedScreenName()] = path
      rotation = {base: rotateConfig.scope === "same" ? path : rotation.base, own: own}
      rearmRotate()
    } else result = assignWorkspace(focusedWorkspaceId(), path)
    return result
  }

  function setTransition(key, value) { return mutate({type: "transition", key: key, value: value}) }

  function previewTransition() {
    if (images.length < 2) return
    var shown = ""
    for (var i = 0; i < panels.instances.length; i++) {
      var p = panels.instances[i]
      if (p.screen && p.screen.name === focusedScreenName()) shown = p.displayedImage
    }
    var index = Math.max(0, images.indexOf(shown))
    previewImage = images[(index + 1) % images.length]
    previewTimer.interval = transitionMs + 700
    previewTimer.restart()
  }

  Timer {
    id: previewTimer
    repeat: false
    onTriggered: root.previewImage = ""
  }

  function applyPendingTheme(request) {
    if (!themePending || request !== themeRequest) return
    themePending = false
    themeFallbackTimer.stop()
    Color.loadColors(pendingColorsRaw)
    Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function openSelector() {
    if (!bgSwitchProc.running) bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  function status() {
    var screens = []
    for (var i = 0; i < panels.instances.length; i++) {
      var p = panels.instances[i]
      screens.push({
        screen: p.screen ? p.screen.name : "",
        workspace: p.shownWorkspace,
        image: p.displayedImage,
        incoming: p.incomingImage,
        resident: p.residentCount,
        keep: p.keep,
        error: p.loadError
      })
    }
    return JSON.stringify({
      settingsError: configStore.error,
      catalogError: catalog.error,
      mode: mode,
      workspaceAssign: workspaceAssign,
      theme: themeName,
      rotate: { every: rotateConfig.every, ms: rotateMs, order: rotateConfig.order, scope: rotateConfig.scope, running: rotating, preloading: plannedRotate !== null, leadMs: preloadMs },
      transition: transitionConfig,
      pins: pins,
      workspaces: workspacePicks,
      random: randomPicks,
      classic: classicImage,
      images: images,
      screens: screens
    })
  }

  ConfigStore {
    id: configStore
    path: root.configPath
    writable: true
    onFailed: function(message) { Util.execArgv(["notify-send", "Backgrounds", message]) }
  }

  BackgroundCatalog {
    id: catalog
    extraPaths: {
      var paths = [root.classicImage]
      for (var screen in root.rotationOverrides) paths.push(root.rotationOverrides[screen])
      for (var name in root.pins) paths.push(root.pins[name])
      for (var ws in root.workspacePicks) if (root.workspacePicks[ws] !== Config.RANDOM) paths.push(root.workspacePicks[ws])
      return paths.filter(function(p) { return !!p })
    }
    onRefreshed: {
      // Only completions using a snapshot obtained after this theme request
      // may apply its palette. Old in-flight animations cannot do so.
      if (root.themePending && catalog.completedSerial >= root.themeCatalogRequest) root.themeReadyRequest = root.themeRequest
    }
  }

  property string observedClassicLink: ""
  property bool forceClassicRead: true
  function refreshClassic() { if (!readlinkProc.running) readlinkProc.running = true }
  Timer { interval: 1000; running: true; repeat: true; onTriggered: root.refreshClassic() }
  Component.onCompleted: refreshClassic()
  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path && (path !== root.observedClassicLink || root.forceClassicRead)) root.classicImage = path
        root.observedClassicLink = path
        root.forceClassicRead = false
      }
    }
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
  }

  Timer {
    id: preloadTimer
    interval: Math.max(0, root.rotateMs - root.preloadMs)
    repeat: false
    onTriggered: { root.plannedRotate = root.planRotate(); rotateTimer.start() }
  }

  Timer {
    id: rotateTimer
    interval: root.preloadMs
    repeat: false
    onTriggered: { root.rotateStep(); if (root.rotating) preloadTimer.start() }
  }

  Timer {
    id: themeFallbackTimer
    interval: root.transitionMs + 3000
    repeat: false
    onTriggered: root.applyPendingTheme(root.themeRequest)
  }

  // Same target and calls as the stock plugin, so omarchy-theme-bg-set,
  // omarchy-theme-set and the switchers keep working, plus the mode controls.
  IpcHandler {
    target: "background"

    function refresh(): void {
      catalog.refresh()
      configStore.reload()
      root.refreshClassic()
    }

    function set(path: string): string { return root.pick(path, false) }
    function setInstant(path: string): string { return root.pick(path, true) }
    function transition(fromPath: string, path: string): void { root.pick(path) }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.pendingColorsRaw = Util.decodeBase64(colorsB64)
      root.pendingShellRaw = Util.decodeBase64(shellB64)
      root.themeRequest += 1
      root.themeReadyRequest = 0
      root.themePending = true
      root.themeCatalogRequest = catalog.requestSerial + 1
      catalog.refresh()
      themeFallbackTimer.interval = root.transitionMs + 3000
      themeFallbackTimer.restart()
      if (root.mode === "classic") { root.classicImage = String(finalPath || path || "").trim() }
    }

    // mode "" queries, otherwise classic | workspace | pinned | rotate
    function mode(name: string): string {
      var result = name ? root.setMode(name) : "ok"
      return result === "ok" ? root.mode : result
    }

    // workspace mode: "" queries, otherwise modulo | fixed
    function workspaceAssign(name: string): string {
      var result = name ? root.setWorkspaceAssign(name) : "ok"
      return result === "ok" ? root.workspaceAssign : result
    }
    // assign an image to a workspace (path "" clears it), no need to be on it
    function assign(workspace: int, path: string): string { return root.assignWorkspace(workspace, path) }
    function clearWorkspacePicks(): string { return root.clearWorkspacePicks() }

    // e.g. "45s", "30m", "2h" (a bare number is minutes; minimum 5s)
    function rotateEvery(spec: string): string { var r = root.setRotate("every", spec); return r === "ok" ? String(root.rotateMs / 1000) + "s" : r }
    // ordered | random
    function rotateOrder(order: string): string { var r = root.setRotate("order", order); return r === "ok" ? root.rotateConfig.order : r }
    // same | different (per monitor)
    function rotateScope(scope: string): string { var r = root.setRotate("scope", scope); return r === "ok" ? root.rotateConfig.scope : r }
    function rotateNow(): void { root.rotateStep(); root.rearmRotate() }

    // transitionStyle cut|fade|slide|zoom|wipe|reveal; transitionDuration <ms>
    function transitionStyle(name: string): string { var r = name ? root.setTransition("style", name) : "ok"; return r === "ok" ? root.transitionStyle : r }
    function transitionDuration(ms: string): string { var r = ms !== "" ? root.setTransition("ms", ms) : "ok"; return r === "ok" ? String(root.transitionMs) : r }
    function previewTransition(): void { root.previewTransition() }

    // pinned mode: monitor "" is the focused one
    function pin(monitor: string, path: string): string { return root.pin(monitor, path) }
    function unpin(monitor: string): string { return root.pin(monitor, "") }

    function status(): string { return root.status() }
    function statusSafe(): string {
      return JSON.stringify({mode: root.mode, images: root.images.length,
        screens: panels.instances.map(function(p, i) { return {screen: i + 1, resident: p.residentCount, failed: !!p.loadError} }),
        settingsError: !!configStore.error, catalogError: !!catalog.error})
    }
    function configure(operation: string): string {
      try { return root.mutate(JSON.parse(operation)) }
      catch (e) { return "error: invalid settings operation" }
    }
    function choose(): void { root.openSelector() }
  }

  Variants {
    id: panels
    model: Quickshell.screens
    BackgroundScreen { renderer: root }
  }
}
