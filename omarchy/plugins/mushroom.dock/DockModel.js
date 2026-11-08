.pragma library

// ---------------------------------------------------------------------------
// Mushroom Grove Dock - pure data model
//
// Plain JS so the QML side stays declarative. Inputs are Hyprland toplevels,
// desktop entries, the active window, and the user's pin list.
// ---------------------------------------------------------------------------

// Fallback pins, used when pinned.json is missing. Resolution is deliberately
// fuzzy: an entry may be a desktop id, a startup class, or an app name.
var defaultPinned = [
  "chromium",
  "org.wezfurlong.wezterm",
  "org.gnome.Nautilus",
  "obsidian",
  "signal",
  "Discord",
  "com.obsproject.Studio",
  "org.kde.kdenlive",
  "mpv",
  "com.moonlight_stream.Moonlight"
]

function normalize(value) {
  return String(value || "").replace(/\.desktop$/, "").toLowerCase().trim()
}

function lastSegment(value) {
  var v = normalize(value)
  var i = v.lastIndexOf(".")
  return i >= 0 ? v.slice(i + 1) : v
}

// All the spellings a window class or desktop id might be known by.
function candidateKeys(value) {
  var v = normalize(value)
  if (!v) return []
  var out = [v]
  var last = lastSegment(v)
  if (last && last !== v) out.push(last)
  return out
}

function keysOverlap(a, b) {
  for (var i = 0; i < a.length; i++)
    for (var j = 0; j < b.length; j++)
      if (a[i] === b[j]) return true
  return false
}

function titleCase(value) {
  var v = String(value || "").replace(/[-_.]+/g, " ").replace(/\s+/g, " ").trim()
  if (!v) return "Application"
  return v.charAt(0).toUpperCase() + v.slice(1)
}

function buildIndex(entries) {
  var index = {}
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (!e) continue
    var keys = candidateKeys(e.id)
    keys.push(normalize(e.startupClass))
    keys.push(normalize(e.name))
    for (var k = 0; k < keys.length; k++) {
      if (keys[k] && index[keys[k]] === undefined) index[keys[k]] = e
    }
  }
  return index
}

function lookup(index, keys) {
  for (var i = 0; i < keys.length; i++) {
    var hit = index[keys[i]]
    if (hit) return hit
  }
  return null
}

function displayName(entry, appId) {
  if (entry && entry.name) return entry.name
  return titleCase(lastSegment(appId))
}

// Group Hyprland toplevels by application. Returns an array of
// { key, appId, keys, windows } in first-seen order.
function groupToplevels(toplevels) {
  var groups = []
  var byKey = {}
  for (var i = 0; i < toplevels.length; i++) {
    var t = toplevels[i]
    if (!t || !t.wayland) continue
    var appId = ""
    if (t.wayland.appId) appId = t.wayland.appId
    else if (t.lastIpcObject && t.lastIpcObject.class) appId = t.lastIpcObject.class
    else if (t.title) appId = t.title
    appId = normalize(appId)
    if (!appId) continue
    var keys = candidateKeys(appId)
    var key = keys[0]
    var group = byKey[key]
    if (!group) {
      group = { key: key, appId: appId, keys: keys, windows: [] }
      byKey[key] = group
      groups.push(group)
    }
    group.windows.push(t)
  }
  return groups
}

function findGroup(groups, used, keys) {
  for (var i = 0; i < groups.length; i++) {
    if (used[i]) continue
    if (keysOverlap(groups[i].keys, keys)) return i
  }
  return -1
}

function makeApp(entry, appId, keys, windows) {
  return {
    pinned: true,
    entry: entry,
    desktopId: entry ? entry.id : "",
    appId: appId,
    keys: keys,
    name: displayName(entry, appId),
    icon: entry ? entry.icon : appId,
    windows: windows
  }
}

// The dock model: the pinned apps in configured order. Each app carries the
// windows that belong to it so the indicator can show running/focused state.
function buildApps(pinnedIds, entries, toplevels, activeAppId) {
  var index = buildIndex(entries || [])
  var groups = groupToplevels(toplevels || [])
  var used = {}
  var apps = []

  var pins = Array.isArray(pinnedIds) ? pinnedIds : defaultPinned
  for (var p = 0; p < pins.length; p++) {
    var id = normalize(pins[p])
    if (!id) continue
    var keys = candidateKeys(id)
    var entry = lookup(index, keys)
    var gi = findGroup(groups, used, keys)
    var windows = []
    if (gi >= 0) {
      used[gi] = true
      windows = groups[gi].windows
    }
    apps.push(makeApp(entry, entry ? entry.id : id, keys, windows))
  }

  return apps
}

function isFocused(app, activeAppId) {
  var a = normalize(activeAppId)
  if (!a || !app) return false
  var keys = app.keys && app.keys.length ? app.keys : candidateKeys(app.appId)
  return keysOverlap(keys, candidateKeys(a))
}

// ------------------------------------------------------------------ pin index

function pinnedKeySet(pinnedIds) {
  var set = {}
  var list = Array.isArray(pinnedIds) ? pinnedIds : defaultPinned
  for (var i = 0; i < list.length; i++) {
    var keys = candidateKeys(list[i])
    for (var k = 0; k < keys.length; k++) set[keys[k]] = true
  }
  return set
}

function isPinned(pinnedIds, id) {
  var set = pinnedKeySet(pinnedIds)
  var keys = candidateKeys(id)
  for (var i = 0; i < keys.length; i++) if (set[keys[i]]) return true
  return false
}
