pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "DockModel.js" as DockModel

// Mushroom Grove Dock
//
// A minimal floating application dock. The root object owns the app model and
// the persisted pin list; DockWindow.qml draws one dock surface per monitor.
// The dock is hidden by default and peeks in on demand (Super key, bottom edge,
// or IPC).
Item {
  id: root

  // Injected by the omarchy-shell host for panel plugins.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property bool opened: true

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/mushroom.dock"
  readonly property string configPath: pluginDir + "/pinned.json"

  // ------------------------------------------------------------- mushroom palette
  readonly property color skin: Color.foreground
  readonly property color accent: Color.accent
  readonly property color gold: "#e5b65d"
  readonly property color moss: "#9dbb6d"
  readonly property color teal: "#72b39e"

  // --------------------------------------------------------------------- tuning
  readonly property int iconSize: 40
  readonly property int iconGap: 8
  readonly property real maxScale: 1.5
  readonly property real influence: 118
  readonly property int revealZone: 5
  readonly property int hideDelay: 600
  property bool alwaysVisible: false

  // ---------------------------------------------------------------------- state
  property var pinnedIds: DockModel.defaultPinned
  property int modelRevision: 0
  property int peekSerial: 0
  property int dismissSerial: 0

  // ----------------------------------------------------------------------- model
  readonly property var entries: DesktopEntries.applications.values
  readonly property var toplevels: Hyprland.toplevels.values
  readonly property string activeAppId: {
    var t = Hyprland.activeToplevel
    if (!t) return ""
    if (t.wayland && t.wayland.appId) return t.wayland.appId
    if (t.lastIpcObject && t.lastIpcObject.class) return t.lastIpcObject.class
    return ""
  }
  readonly property var apps: {
    modelRevision
    return DockModel.buildApps(pinnedIds, entries, toplevels, activeAppId)
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.modelRevision++ }
  }
  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { root.modelRevision++ }
  }
  Connections {
    target: DesktopEntries
    function onApplicationsChanged() { root.modelRevision++ }
  }

  // ----------------------------------------------------------------- persistence
  // pinned.json is a JSON array of desktop ids / startup classes / app names.
  // An object with an `apps` array is also accepted.
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onFileChanged: reload()
    onLoadFailed: {}
    onSaveFailed: function(error) { console.warn("mushroom.dock: pinned.json save failed:", error) }
  }

  function applyConfig(raw) {
    try {
      var data = JSON.parse(String(raw || "[]"))
      var list = null
      if (Array.isArray(data)) list = data
      else if (data && Array.isArray(data.apps)) list = data.apps
      if (list) {
        root.pinnedIds = list.filter(function(v) { return typeof v === "string" && v.length > 0 })
      }
    } catch (e) {
      console.warn("mushroom.dock: could not parse pinned.json:", e)
    }
  }

  function saveConfig() {
    configFile.setText(JSON.stringify(root.pinnedIds, null, 2) + "\n")
  }

  // ------------------------------------------------------------------- icon lookup
  function iconSource(icon, key) {
    var value = String(icon || "")
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    if (value.length > 0) {
      var themed = Quickshell.iconPath(value, true)
      if (themed && themed.length > 0) return themed
    }
    if (key) {
      var byKey = Quickshell.iconPath(String(key).toLowerCase(), true)
      if (byKey && byKey.length > 0) return byKey
    }
    return Quickshell.iconPath("application-x-executable", true)
  }

  // ----------------------------------------------------------------- pin management
  function togglePin(id) {
    if (!id) return
    if (DockModel.isPinned(root.pinnedIds, id)) {
      var keys = DockModel.candidateKeys(id)
      var next = []
      for (var i = 0; i < root.pinnedIds.length; i++) {
        if (!DockModel.keysOverlap(DockModel.candidateKeys(root.pinnedIds[i]), keys))
          next.push(root.pinnedIds[i])
      }
      root.pinnedIds = next
    } else {
      var withNew = root.pinnedIds.slice()
      withNew.push(id)
      root.pinnedIds = withNew
    }
    root.saveConfig()
  }

  function removeFromDock(app) {
    if (!app) return
    var id = app.entry && app.entry.id ? app.entry.id : app.appId
    if (DockModel.isPinned(root.pinnedIds, id)) root.togglePin(id)
  }

  // -------------------------------------------------------------------- actions
  function launchApp(app) {
    if (!app || !app.desktopId) return false
    var id = String(app.desktopId).replace(/\.desktop$/, "")
    if (!id) return false
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
    root.dismiss()
    return true
  }

  // Click behaviour: focus the app if it is running, cycling through its
  // windows on repeated clicks, otherwise launch it.
  function activateApp(app) {
    if (!app) return false
    if (!app.windows || app.windows.length === 0) return root.launchApp(app)
    var current = -1
    for (var i = 0; i < app.windows.length; i++) {
      var w = app.windows[i].wayland
      if (w && w.activated) { current = i; break }
    }
    var target = app.windows[(current + 1) % app.windows.length]
    if (target && target.wayland && typeof target.wayland.activate === "function") {
      target.wayland.activate()
      root.dismiss()
      return true
    }
    return false
  }

  function closeApp(app) {
    if (!app || !app.windows) return
    for (var i = 0; i < app.windows.length; i++) {
      var w = app.windows[i].wayland
      if (w && typeof w.close === "function") w.close()
    }
  }

  function isFocused(app) {
    return DockModel.isFocused(app, root.activeAppId)
  }

  // Focus a specific window, switching to its workspace if needed. Hyprland's
  // address selector does the workspace jump reliably; the Wayland activate
  // request is the fallback when no address is known.
  function instanceAddress(inst) {
    if (!inst || !inst.window) return ""
    var addr = inst.window.address ? String(inst.window.address) : ""
    if (!addr) return ""
    return addr.indexOf("0x") === 0 ? addr : ("0x" + addr)
  }

  function focusInstance(inst) {
    if (!inst || !inst.window) return false
    var addr = root.instanceAddress(inst)
    if (addr) {
      Util.execArgv(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + addr + "\" })"])
      return true
    }
    if (inst.window.wayland && typeof inst.window.wayland.activate === "function") {
      inst.window.wayland.activate()
      return true
    }
    return false
  }

  // A flat list of every running window, grouped by app in dock order, so the
  // Super + A cursor visits each instance in turn rather than jumping between
  // apps. Windows keep their order for a stable walk.
  function runningInstances() {
    var list = []
    for (var i = 0; i < root.apps.length; i++) {
      var a = root.apps[i]
      if (!a.windows) continue
      for (var j = 0; j < a.windows.length; j++) list.push({ app: a, window: a.windows[j] })
    }
    return list
  }

  // A persistent cursor advances on every press (rather than re-reading the
  // focused window, which can lag a cross-workspace switch). The cursor
  // re-seeds from the focused window when the running set changes, so it stays
  // intuitive after windows open or close.
  property int cycleCursor: -1
  property int cycleSignature: 0

  function cycleApp(step) {
    var dir = step < 0 ? -1 : 1
    var list = root.runningInstances()
    if (list.length === 0) return false

    var sig = list.length
    for (var s = 0; s < list.length; s++) sig = (sig * 31 + root.instanceAddress(list[s]).length) % 1000000007
    if (root.cycleCursor < 0 || root.cycleCursor >= list.length || root.cycleSignature !== sig) {
      var activeIdx = -1
      for (var j = 0; j < list.length; j++) {
        var w = list[j].window.wayland
        if (w && w.activated) { activeIdx = j; break }
      }
      root.cycleCursor = activeIdx >= 0 ? activeIdx : (dir > 0 ? -1 : 0)
      root.cycleSignature = sig
    }

    var n = list.length
    root.cycleCursor = (((root.cycleCursor + dir) % n) + n) % n
    return root.focusInstance(list[root.cycleCursor])
  }

  function openMenu() { Util.execDetached("omarchy-menu toggle root") }
  function openTerminal() { Util.execDetached("xdg-terminal-exec") }

  function peek() { root.peekSerial++ }
  function dismiss() { root.dismissSerial++ }

  function refresh() {
    root.modelRevision++
    configFile.reload()
  }

  // ------------------------------------------------------------------------ ipc
  IpcHandler {
    target: "mushroom-dock"
    function toggle(): string {
      root.alwaysVisible = !root.alwaysVisible
      return root.alwaysVisible ? "pinned" : "auto"
    }
    function show(): string { root.alwaysVisible = true; return "ok" }
    function hide(): string { root.alwaysVisible = false; return "ok" }
    function peek(): string { root.peek(); return "ok" }
    function dismiss(): string { root.dismiss(); return "ok" }
    function cycle(step: string): string {
      root.cycleApp(Number(step) < 0 ? -1 : 1)
      return "ok"
    }
    function pin(id: string): string { root.togglePin(id); return "ok" }
    function refresh(): string { root.refresh(); return "ok" }
    function ping(): string { return "ok" }
  }

  // ------------------------------------------------------------------- surfaces
  Variants {
    model: Quickshell.screens
    DockWindow {
      dockRoot: root
    }
  }
}
