// The shape of ~/.config/omarchy/background.json and pure helpers around it,
// shared by the renderer (Background.qml) and the settings panel (Panel.qml).
// No Qt imports; persistence and host IPC live in the QML components.
.pragma library

var MODES = ["classic", "workspace", "pinned", "rotate"]
var MODE_SHORT = {
  classic: "Classic",
  workspace: "Workspace",
  pinned: "Pinned",
  rotate: "Rotating"
}
var MODE_DESCRIPTIONS = {
  classic: "One image on every monitor",
  workspace: "Each monitor shows its workspace's image",
  pinned: "A picked image on each monitor",
  rotate: "A new image every so often"
}
var ASSIGN_OPTIONS = [
  { value: "modulo", label: "Deal out" },
  { value: "fixed", label: "Assigned only" }
]
var ASSIGN_DESCRIPTIONS = {
  modulo: "The pool goes to workspaces 1, 2, 3, … in order, wrapping around",
  fixed: "Pick per workspace, or Random; the pool's first image where nothing is picked"
}
// A workspace assignment that means "roll one for me" rather than a path.
var RANDOM = "random"
var RANDOM_LABEL = "Random"
var RANDOM_DESCRIPTION = "an image no other workspace has, while any are left"
var ORDER_OPTIONS = [
  { value: "ordered", label: "In order" },
  { value: "random", label: "Random" }
]
var SCOPE_OPTIONS = [
  { value: "same", label: "Same everywhere" },
  { value: "different", label: "Per monitor" }
]
// How one image gives way to the next, on every change (workspace switch,
// pick, rotation tick, theme switch).
var TRANSITION_OPTIONS = [
  { value: "cut", label: "Cut" },
  { value: "fade", label: "Fade" },
  { value: "slide", label: "Slide" },
  { value: "zoom", label: "Zoom" },
  { value: "wipe", label: "Wipe" },
  { value: "reveal", label: "Reveal" }
]
var TRANSITION_DESCRIPTIONS = {
  cut: "Straight to the next image",
  fade: "Crossfade",
  slide: "The next image pushes in from the right",
  zoom: "The next image settles in from slightly larger",
  wipe: "An edge sweeps left to right",
  reveal: "Omarchy's slanted split from the centre"
}
var TRANSITION_MAX_MS = 2000
// QML Timer intervals are signed 32-bit milliseconds.
var INTERVAL_MAX_MS = 2147483647

function isObject(value) {
  return Object.prototype.toString.call(value) === "[object Object]"
}
function validWorkspace(value) {
  return /^([1-9][0-9]*)$/.test(String(value)) && Number(value) <= 2147483647
}
function validPath(value) { return typeof value === "string" && value.charAt(0) === "/" && value.indexOf("\0") < 0 }

function normalizeConfig(value) {
  var cfg = isObject(value) ? JSON.parse(JSON.stringify(value)) : {}
  cfg.mode = mode(cfg)
  cfg.workspaceAssign = workspaceAssign(cfg)
  cfg.rotate = Object.assign({}, isObject(cfg.rotate) ? cfg.rotate : {}, rotate(cfg))
  cfg.transition = Object.assign({}, isObject(cfg.transition) ? cfg.transition : {}, transition(cfg))
  ;["pins", "workspaces"].forEach(function(kind) {
    var maps = isObject(cfg[kind]) ? cfg[kind] : {}
    var clean = Object.create(null)
    Object.keys(maps).forEach(function(theme) {
      if (!isObject(maps[theme]) || theme === "__proto__") return
      var entries = Object.create(null)
      Object.keys(maps[theme]).forEach(function(key) {
        var path = maps[theme][key]
        if (key === "__proto__" || (kind === "workspaces" && !validWorkspace(key))) return
        if (validPath(path) || (kind === "workspaces" && path === RANDOM)) entries[key] = path
      })
      clean[theme] = entries
    })
    cfg[kind] = clean
  })
  return cfg
}

function mode(cfg) {
  return cfg && MODES.indexOf(cfg.mode) >= 0 ? cfg.mode : "workspace"
}

function workspaceAssign(cfg) {
  return cfg && cfg.workspaceAssign === "fixed" ? "fixed" : "modulo"
}

function rotate(cfg) {
  var r = (cfg && cfg.rotate) || {}
  return {
    every: intervalMs(r.every) !== null ? String(r.every).trim() : "30m",
    order: r.order === "random" ? "random" : "ordered",
    scope: r.scope === "different" ? "different" : "same"
  }
}

function transitionStyle(name) {
  for (var i = 0; i < TRANSITION_OPTIONS.length; i++) if (TRANSITION_OPTIONS[i].value === name) return name
  return "fade"
}

function validDuration(value) {
  return (typeof value === "number" || (typeof value === "string" && /^[0-9]+(?:\.[0-9]+)?$/.test(value.trim())))
    && isFinite(Number(value)) && Number(value) >= 0 && Number(value) <= TRANSITION_MAX_MS
}

function transition(cfg) {
  var t = (cfg && cfg.transition) || {}
  var ms = Number(t.ms)
  if ((typeof t.ms !== "number" && typeof t.ms !== "string") || t.ms === "" || !isFinite(ms)) ms = 220
  return { style: transitionStyle(t.style), ms: Math.max(0, Math.min(TRANSITION_MAX_MS, Math.round(ms))) }
}

function transitionLabel(ms) {
  return ms <= 0 ? "instant" : (Math.round(ms / 50) * 50 / 1000).toFixed(2).replace(/0$/, "") + " s"
}

function pins(cfg, theme) {
  return ((cfg && cfg.pins) || {})[theme] || {}
}

function workspaces(cfg, theme) {
  return ((cfg && cfg.workspaces) || {})[theme] || {}
}

// "45s", "30m", "2h", "1h30m"; a bare number is minutes; never under 5 s.
function intervalMs(spec) {
  if (typeof spec !== "string" && typeof spec !== "number") return null
  var s = String(spec).trim()
  if (!/^(?:[0-9]+|(?:[0-9]+\s*[smh]\s*)+)$/i.test(s)) return null
  var total = 0
  if (/^[0-9]+$/.test(s)) total = Number(s) * 60000
  else {
    var re = /([0-9]+)\s*([smh])/gi
    var m
    while ((m = re.exec(s)) !== null) total += Number(m[1]) * ({s: 1000, m: 60000, h: 3600000}[m[2].toLowerCase()])
  }
  return isFinite(total) && total > 0 && total <= INTERVAL_MAX_MS ? Math.max(5000, total) : null
}
function parseInterval(spec) {
  var ms = intervalMs(spec)
  return ms === null ? 1800000 : ms
}

// The interval as the hour/minute drums show it (0-24 h, 0-59 min).
function intervalParts(spec) {
  var minutes = Math.round(parseInterval(spec) / 60000)
  var hours = Math.floor(minutes / 60)
  if (hours >= 24) return { hours: 24, minutes: 0 }
  return { hours: hours, minutes: minutes % 60 }
}

// Drum values back to a spec: 24 h is the ceiling, and it never collapses
// to zero (the drums are minute-granular; seconds only exist over IPC).
function intervalSpec(hours, minutes) {
  hours = Math.max(0, Math.min(24, Math.round(Number(hours) || 0)))
  minutes = Math.max(0, Math.min(59, Math.round(Number(minutes) || 0)))
  if (hours >= 24) minutes = 0
  if (hours === 0 && minutes === 0) minutes = 1
  return (hours ? hours + "h" : "") + (minutes ? minutes + "m" : "")
}

function intervalLabel(spec) {
  var ms = parseInterval(spec)
  if (ms < 60000) return Math.round(ms / 1000) + " s"
  var seconds = Math.round(ms / 1000)
  var parts = []
  if (seconds >= 3600) parts.push(Math.floor(seconds / 3600) + " h")
  if (seconds % 3600 >= 60) parts.push(Math.floor(seconds % 3600 / 60) + " min")
  if (seconds % 60) parts.push(seconds % 60 + " s")
  return parts.join(" ")
}

function clone(cfg) {
  return normalizeConfig(cfg)
}

function withMode(cfg, name) {
  var next = clone(cfg)
  next.mode = name
  return next
}

function withWorkspaceAssign(cfg, name) {
  var next = clone(cfg)
  next.workspaceAssign = name
  return next
}

function withRotate(cfg, key, value) {
  var next = clone(cfg)
  next.rotate = next.rotate || {}
  next.rotate[key] = value
  return next
}

function withTransition(cfg, key, value) {
  var next = clone(cfg)
  next.transition = next.transition || {}
  next.transition[key] = value
  return next
}

function withPin(cfg, theme, screen, path) {
  var next = clone(cfg)
  next.pins = next.pins || {}
  next.pins[theme] = next.pins[theme] || {}
  if (path) next.pins[theme][screen] = path
  else delete next.pins[theme][screen]
  return next
}

function withWorkspace(cfg, theme, workspaceId, path) {
  var next = clone(cfg)
  next.workspaces = next.workspaces || {}
  next.workspaces[theme] = next.workspaces[theme] || {}
  if (path) next.workspaces[theme][String(workspaceId)] = path
  else delete next.workspaces[theme][String(workspaceId)]
  return next
}

function withoutWorkspaces(cfg, theme) {
  var next = clone(cfg)
  if (next.workspaces) delete next.workspaces[theme]
  return next
}

function serialize(cfg) {
  return JSON.stringify(cfg, null, 2) + "\n"
}

// "3-neon-light-bathroom-sign-night.webp" -> "Neon Light Bathroom Sign Night",
// the way omarchy-theme-bg-current names a background.
function label(path) {
  var name = String(path || "").split("/").pop().replace(/\.[^.]+$/, "").replace(/^\d+-/, "")
  return name.replace(/[-_]+/g, " ").replace(/\b\w/g, function(c) { return c.toUpperCase() })
}

// Validated operations are the persistence boundary for panels and IPC alike.
function applyOperation(cfg, op) {
  if (!isObject(op)) throw new Error("invalid settings operation")
  var key = op.key, value = op.value
  switch (op.type) {
  case "mode":
    if (MODES.indexOf(value) < 0) throw new Error("unknown mode")
    return withMode(cfg, value)
  case "workspaceAssign":
    if (["fixed", "modulo"].indexOf(value) < 0) throw new Error("unknown workspace assignment")
    return withWorkspaceAssign(cfg, value)
  case "rotate":
    if (!(key === "every" && intervalMs(value) !== null)
        && !(key === "order" && ["ordered", "random"].indexOf(value) >= 0)
        && !(key === "scope" && ["same", "different"].indexOf(value) >= 0)) throw new Error("invalid rotation setting")
    return withRotate(cfg, key, String(value))
  case "transition":
    if (!(key === "style" && TRANSITION_OPTIONS.some(function(o) { return o.value === value }))
        && !(key === "ms" && validDuration(value))) throw new Error("invalid transition setting")
    return withTransition(cfg, key, key === "ms" ? Math.round(Number(value)) : value)
  case "pin":
  case "assign":
  case "clearWorkspacePicks":
    if (typeof op.theme !== "string" || !op.theme || op.theme === "__proto__") throw new Error("theme is not available")
    if (op.type === "clearWorkspacePicks") return withoutWorkspaces(cfg, op.theme)
    if (op.type === "assign" && !validWorkspace(op.target)) throw new Error("workspace must be a positive integer")
    if (op.type === "pin" && (typeof op.target !== "string" || !op.target || op.target === "__proto__")) throw new Error("monitor is not available")
    if (value !== "" && !validPath(value) && !(op.type === "assign" && value === RANDOM)) throw new Error("image must be an absolute path")
    return op.type === "pin" ? withPin(cfg, op.theme, op.target, value) : withWorkspace(cfg, op.theme, op.target, value)
  }
  throw new Error("unknown settings operation")
}
