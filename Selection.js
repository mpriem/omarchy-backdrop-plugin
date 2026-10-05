.pragma library

// Paths are canonical rotation state. Indices only exist during traversal.
function rotationImage(pool, state, scope, screens, screen) {
  if (!pool.length) return ""
  if (scope === "different" && pool.indexOf(state.own[screen]) >= 0) return state.own[screen]
  var base = Math.max(0, pool.indexOf(state.base))
  var offset = scope === "different" ? Math.max(0, screens.indexOf(screen)) : 0
  return pool[(base + offset) % pool.length]
}
function reconcile(pool, state, screens, previousPool, previousScreens, scope) {
  var own = {}
  var base = pool.indexOf(state.base) >= 0 ? state.base : (pool[0] || "")
  screens.forEach(function(screen) {
    var path = state.own[screen]
    if (!path && previousPool && scope === "different")
      path = rotationImage(previousPool, state, scope, previousScreens || screens, screen)
    if (pool.indexOf(path) >= 0) own[screen] = path
  })
  return {base: base, own: own}
}
function plan(pool, state, policy, screens, random) {
  if (!pool.length) return {base: "", own: {}}
  function next(path) {
    var index = Math.max(0, pool.indexOf(path))
    var step = policy.order === "random" && pool.length > 1 ? 1 + Math.floor(random() * (pool.length - 1)) : 1
    return pool[(index + step) % pool.length]
  }
  var own = {}
  if (policy.scope === "different" && policy.order === "random") {
    screens.forEach(function(screen) { own[screen] = next(rotationImage(pool, state, policy.scope, screens, screen)) })
    return {base: state.base, own: own}
  }
  return {base: next(state.base), own: own}
}
function workspaceImage(pool, picks, random, assignment, workspace) {
  var first = pool[0] || ""
  var pick = picks[String(workspace)]
  if (pick === "random") return random[String(workspace)] || first
  if (pick) return pick
  if (assignment === "fixed" || workspace <= 0) return first
  return pool[(workspace - 1) % pool.length] || first
}
