import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "DockModel.js" as DockModel

// An app dock that shows on floating workspaces. A floating workspace has no
// tiles to hand the apps out, so the dock gives back a place to find them:
// pinned apps, running apps, and a grid of every app.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var appLibrary: shell ? shell.appLibrary : null

  // A cloned (third-party) plugin gets a scoped shell API with no shellConfig,
  // so the dock reads its own config from disk and watches it. Writes still go
  // through `omarchy-dock`, which commits shell.json and triggers the watch.
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "") + "/.config")
  readonly property string userConfigPath: root.configHome + "/omarchy/shell.json"
  readonly property string defaultsPath: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/config/omarchy/shell.json"
  property var dockConfig: ({})
  property var defaultDockConfig: ({})

  FileView {
    id: dockConfigFile
    path: root.userConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyDockConfig(text())
    onFileChanged: reload()
    onLoadFailed: {}
  }

  FileView {
    id: defaultsConfigFile
    path: root.defaultsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyDefaultsConfig(text())
    onFileChanged: reload()
    onLoadFailed: {}
  }

  function applyDockConfig(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      root.dockConfig = data && data.dock ? data.dock : ({})
    } catch (e) {
      console.warn("mushroom.dock: could not parse shell.json:", e)
    }
  }

  function applyDefaultsConfig(raw) {
    try {
      var data = JSON.parse(String(raw || "{}"))
      root.defaultDockConfig = data && data.dock ? data.dock : ({})
    } catch (e) {
      console.warn("mushroom.dock: could not parse default shell.json:", e)
    }
  }
  readonly property string position: DockModel.normalizePosition(dockConfig.position)
  readonly property bool vertical: DockModel.isVertical(position)
  readonly property bool autohide: dockConfig.autohide === true

  // Peek state shared by every screen's dock. The dock is normally tucked off
  // the edge; a peek brings it up for a moment, and the IPC toggle pins it
  // open until toggled back.
  property bool alwaysVisible: false
  property int peekSerial: 0
  property int dismissSerial: 0

  // The dock's order for the session, as desktop ids, set when the user moves
  // an app: a drag moves it, and keeping it in the dock puts it at the end. An
  // app the order does not know yet goes at the end. Pins are saved in this
  // order.
  property var order: []

  // A reorder shows at once rather than when the saved config comes back.
  property var pendingPins: null
  onDockConfigChanged: pendingPins = null

  // Entries that can claim a terminal app's window: those run in a terminal,
  // and those that hand the terminal an app id of their own.
  readonly property var terminalEntries: {
    var values = DesktopEntries.applications.values
    var out = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (entry.runInTerminal || String(entry.execString || "").indexOf("--app-id=") >= 0)
        out.push({ id: entry.id, execString: entry.execString, command: entry.command, runInTerminal: entry.runInTerminal })
    }
    return out
  }

  function entryForAppId(appId) {
    var entry = DesktopEntries.heuristicLookup(appId)
    if (entry) return entry
    var id = DockModel.claimingEntryId(appId, root.terminalEntries)
    return id ? DesktopEntries.byId(id) : null
  }

  // A pinned app that is not installed has nothing to launch, so it is left
  // out until it is. Windows are matched to the desktop entry that claims them.
  readonly property var items: {
    var appsRevision = DesktopEntries.applications.values.length
    var pinned = (root.pendingPins || DockModel.pinnedIds(dockConfig, defaultDockConfig)).filter(function(id) {
      return !!DesktopEntries.byId(id)
    })

    var windows = []
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i].wayland
      if (!toplevel || !toplevel.appId || toplevel.parent) continue
      var entry = root.entryForAppId(toplevel.appId)
      var workspace = toplevels[i].workspace
      windows.push({
        key: entry ? entry.id : toplevel.appId,
        hasEntry: !!entry && !entry.noDisplay,
        workspaceId: workspace ? workspace.id : -1,
        minimized: !!workspace && DockModel.isMinimizedWorkspace(workspace.name),
        address: toplevels[i].address,
        toplevel: toplevel
      })
    }

    return DockModel.orderItems(DockModel.buildItems(pinned, windows), root.order)
  }

  readonly property var itemsByKey: {
    var byKey = {}
    for (var i = 0; i < root.items.length; i++) byKey[root.items[i].key] = root.items[i]
    return byKey
  }

  function itemFor(key) {
    return root.itemsByKey[key] || null
  }

  // The dock's slots follow this model rather than the items list itself, so
  // a slot survives a window opening or closing instead of being rebuilt
  // under the pointer, and a reorder moves slots rather than replacing them.
  property alias itemModel: itemModel

  ListModel { id: itemModel }

  onItemsChanged: syncItemModel()

  function shownKeys() {
    return root.items.map(function(item) { return item.key })
  }

  function syncItemModel() {
    var keys = root.items.map(function(item) { return item.key })
    for (var i = 0; i < keys.length; i++) {
      if (i < itemModel.count && itemModel.get(i).key === keys[i]) continue
      var found = -1
      for (var j = i + 1; j < itemModel.count; j++) {
        if (itemModel.get(j).key === keys[i]) { found = j; break }
      }
      if (found >= 0) itemModel.move(found, i, 1)
      else itemModel.insert(i, { key: keys[i] })
    }
    if (itemModel.count > keys.length) itemModel.remove(keys.length, itemModel.count - keys.length)
    root.settleLaunches()
  }

  // An app launched from the dock pulses its dot until a new window of it
  // shows up, or for ten seconds if none does.
  property var launches: ({})
  readonly property int launchTimeout: 10000

  function isLaunching(key) {
    return root.launches[key] !== undefined
  }

  function settleLaunches() {
    var next = {}
    var changed = false
    var now = Date.now()
    for (var key in root.launches) {
      var launch = root.launches[key]
      var item = root.itemsByKey[key]
      var windows = item ? item.windows.length : 0
      if (windows > launch.windows || now - launch.at > root.launchTimeout) changed = true
      else next[key] = launch
    }
    if (changed) root.launches = next
  }

  Timer {
    interval: 1000
    repeat: true
    running: Object.keys(root.launches).length > 0
    onTriggered: root.settleLaunches()
  }

  function entryFor(item) {
    return item ? DesktopEntries.byId(item.key) : null
  }

  function iconFor(item) {
    var entry = entryFor(item)
    var icon = entry && entry.icon ? entry.icon : (item ? item.key : "")
    return root.iconSource(icon)
  }

  function launch(item) {
    var entry = entryFor(item)
    if (!entry) return
    var next = Object.assign({}, root.launches)
    next[item.key] = { at: Date.now(), windows: item.windows.length }
    root.launches = next
    root.launchEntry(entry)
  }

  // A cloned plugin's scoped shell API has no appLibrary (only menu-kind
  // plugins get one), so the dock carries its own app-list, launch, and
  // uninstall paths. They mirror AppLibrary's behavior.
  function entryName(entry) {
    if (root.appLibrary) return root.appLibrary.entryName(entry)
    return String((entry && entry.name) || (entry && entry.id) || "")
  }

  function entrySubtext(entry) {
    if (root.appLibrary) return root.appLibrary.entrySubtext(entry)
    return String((entry && entry.genericName) || "")
  }

  function iconSource(icon) {
    if (root.appLibrary) return root.appLibrary.iconSource(icon)
    var value = String(icon || "")
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    if (value.length > 0) {
      var themed = Quickshell.iconPath(value, true)
      if (themed && themed.length > 0) return themed
    }
    return Quickshell.iconPath("application-x-executable", true)
  }

  function refreshIcons() {
    if (root.appLibrary) root.appLibrary.refreshIcons()
  }

  function sortedEntries(query) {
    if (root.appLibrary) return root.appLibrary.sortedEntries(query)
    var terms = String(query || "").toLowerCase().trim().split(/\s+/)
    var rows = []
    var values = DesktopEntries.applications.values
    for (var i = 0; i < values.length; i++) {
      var entry = values[i]
      if (!entry || entry.noDisplay) continue
      var name = root.entryName(entry)
      if (!name) continue
      var haystack = [name, entry.genericName, entry.comment, entry.id].join(" ").toLowerCase()
      var matches = true
      for (var j = 0; j < terms.length; j++) {
        if (terms[j] && haystack.indexOf(terms[j]) < 0) { matches = false; break }
      }
      if (!matches) continue
      rows.push({ entry: entry, name: name.toLowerCase() })
    }
    rows.sort(function(a, b) {
      if (a.name < b.name) return -1
      if (a.name > b.name) return 1
      return 0
    })
    return rows
  }

  function removeEntry(entry) {
    if (!entry) return
    if (root.appLibrary) {
      root.appLibrary.remove(entry.id, root.appLibrary.entryName(entry))
      return
    }
    var id = String(entry.id || "")
    if (!id) return
    Util.execDetached("omarchy-remove-launcher-entry " + Util.shellQuote(id) + " " + Util.shellQuote(root.entryName(entry)))
  }

  function launchEntry(entry) {
    if (!entry) return
    if (root.appLibrary) {
      root.appLibrary.launch(entry.id, entry.name)
      return
    }
    var id = String(entry.id || "")
    if (!id) return
    // A terminal entry goes through Omarchy's TUI launcher so its window can
    // be named after the command; everything else resolves through
    // gtk-launch inside a uwsm scope, keeping ids like org.telegram.desktop.
    var command = entry.runInTerminal
      ? (entry.command || []).filter(function(word) { return !/^%[a-zA-Z]$/.test(String(word)) })
      : []
    if (command.length > 0) {
      Util.execDetached("omarchy-launch-tui " + command.map(function(word) { return Util.shellQuote(word) }).join(" "))
      return
    }
    var desktopId = id.slice(-8) === ".desktop" ? id : id + ".desktop"
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(desktopId))
  }

  function activate(item) {
    if (!item) return
    if (item.windows.length === 0) {
      root.launch(item)
      return
    }
    var monitor = Hyprland.focusedMonitor
    var workspaceId = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    var index = DockModel.pickWindow(item.windows.map(function(window) {
      return { workspaceId: window.workspaceId, minimized: window.minimized, activated: window.toplevel.activated }
    }), workspaceId)
    root.bringForward(item.windows[index])
  }

  // A window the dock brings forward lands on top of the others, focused; a
  // minimized one first comes back to the workspace in front of the user.
  function bringForward(window) {
    var address = String(window.address || "")
    if (!address) {
      window.toplevel.activate()
      return
    }
    if (address.indexOf("0x") !== 0) address = "0x" + address
    var target = "window = \"address:" + address + "\""
    var steps = []
    var after = []
    if (window.minimized) {
      var monitor = Hyprland.focusedMonitor
      var workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
      if (!(workspace >= 1)) return
      // A restored window is simply there again, without animating in.
      steps.push("hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"1\", " + target + " })")
      steps.push("hl.dsp.window.move({ workspace = \"" + workspace + "\", " + target + " })")
      after.push("hl.dsp.window.set_prop({ prop = \"no_anim\", value = \"unset\", " + target + " })")
    }
    steps.push("hl.dsp.focus({ " + target + " })")
    steps.push("hl.dsp.window.alter_zorder({ mode = \"top\", " + target + " })")
    var dispatch = function(step) { return "hyprctl dispatch " + Util.shellQuote(step) }
    var command = steps.map(dispatch).join(" && ")
    if (after.length > 0) command += "; sleep 0.4; " + after.map(dispatch).join("; ")
    Util.execDetached(command)
  }

  function quit(item) {
    if (!item) return
    var windows = item.windows.slice()
    for (var i = 0; i < windows.length; i++) windows[i].toplevel.close()
  }

  function openApps() {
    appGrid.open()
  }

  // The launcher disc opens the Omarchy menu, a terminal, or the app grid.
  function openMenu() {
    Util.execDetached("omarchy-menu toggle root")
  }

  function openTerminal() {
    Util.execDetached("xdg-terminal-exec")
  }

  function peek() {
    root.peekSerial++
  }

  function dismiss() {
    root.dismissSerial++
  }

  // A flat list of every running window, grouped by app in dock order, so the
  // Super+A cursor visits each instance in turn rather than jumping between
  // apps.
  readonly property var runningWindows: {
    var list = []
    for (var i = 0; i < root.items.length; i++) {
      var item = root.items[i]
      for (var j = 0; j < item.windows.length; j++) list.push(item.windows[j])
    }
    return list
  }

  // A persistent cursor advances on every press rather than re-reading the
  // focused window, which can lag a cross-workspace switch. It re-seeds from
  // the focused window when the running set changes, so it stays intuitive
  // after windows open or close.
  property int cycleCursor: -1
  property int cycleSignature: 0

  function cycleApp(step) {
    var dir = step < 0 ? -1 : 1
    var list = root.runningWindows
    if (list.length === 0) return false

    var sig = list.length
    for (var s = 0; s < list.length; s++) sig = (sig * 31 + String(list[s].address || "").length) % 1000000007
    if (root.cycleCursor < 0 || root.cycleCursor >= list.length || root.cycleSignature !== sig) {
      var activeIndex = -1
      for (var j = 0; j < list.length; j++) {
        var toplevel = list[j].toplevel
        if (toplevel && toplevel.activated) { activeIndex = j; break }
      }
      root.cycleCursor = activeIndex >= 0 ? activeIndex : (dir > 0 ? -1 : 0)
      root.cycleSignature = sig
    }

    var count = list.length
    root.cycleCursor = (((root.cycleCursor + dir) % count) + count) % count
    root.bringForward(list[root.cycleCursor])
    return true
  }

  readonly property var pinnedKeys: root.pendingPins || DockModel.pinnedIds(root.dockConfig, root.defaultDockConfig)

  function isPinned(key) {
    return root.pinnedKeys.indexOf(key) >= 0
  }

  // Moves an app to a slot in the dock's order, pinning it there; the pins are
  // saved in the new order. The index counts the slots once the app has left
  // its own.
  function placeAt(key, index) {
    if (!key) return
    root.order = DockModel.orderWithKeyAt(root.shownKeys(), key, index)
    var pinned = {}
    root.pinnedKeys.forEach(function(other) { pinned[other] = true })
    pinned[key] = true
    root.savePins(DockModel.pinsInOrder(root.order, pinned, root.pinnedKeys))
  }

  // A reorder shows at once; the saved config catches up after.
  function savePins(pins) {
    root.pendingPins = pins
    Util.execDetached("omarchy-dock pinned " + pins.map(function(id) { return Util.shellQuote(id) }).join(" "))
  }

  function moveItem(fromIndex, toIndex) {
    if (fromIndex !== toIndex) root.placeAt(root.shownKeys()[fromIndex], toIndex)
  }

  // An app dropped before the slot at index, counted as the slots stand.
  function pinAt(key, index) {
    var from = root.shownKeys().indexOf(key)
    root.placeAt(key, from >= 0 && from < index ? index - 1 : index)
  }

  // Keeping an app in the dock puts it at the end; taking one out leaves it in
  // its slot while it still runs.
  function setPinned(key, pinned) {
    if (!key) return
    if (pinned) {
      root.placeAt(key, root.shownKeys().length)
    } else {
      root.pendingPins = root.pinnedKeys.filter(function(other) { return other !== key })
      Util.execDetached("omarchy-dock unpin " + Util.shellQuote(key))
    }
  }

  // Each workspace's layout is read once and cached. It only changes through
  // the layout commands, which ask the dock to refresh, or a config reload.
  property var modes: ({})
  property var pendingModes: []
  property int modeGeneration: 0
  property int modeProcWorkspace: -1
  property int modeProcGeneration: 0

  function isFloating(workspaceId) {
    return root.modes[workspaceId] === "floating"
  }

  function readMode(workspaceId) {
    if (!(workspaceId >= 1) || root.modes[workspaceId] !== undefined) return
    if (root.pendingModes.indexOf(workspaceId) === -1) root.pendingModes.push(workspaceId)
    root.readNextMode()
  }

  function readNextMode() {
    if (modeProc.running || root.pendingModes.length === 0) return
    root.modeProcWorkspace = root.pendingModes.shift()
    root.modeProcGeneration = root.modeGeneration
    modeProc.command = ["omarchy-hyprland-workspace-layout-current", String(root.modeProcWorkspace)]
    modeProc.running = true
  }

  function refresh() {
    root.modes = ({})
    root.pendingModes = []
    root.modeGeneration++
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].activeWorkspace) root.readMode(monitors[i].activeWorkspace.id)
    }
    // Read the rest ahead of time, so the dock shows or hides the moment the
    // user switches to one.
    var workspaces = Hyprland.workspaces.values
    for (var j = 0; j < workspaces.length; j++) root.readMode(workspaces[j].id)
  }

  Component.onCompleted: {
    refresh()
    syncItemModel()
  }

  Process {
    id: modeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var mode = text.trim()
        // A read that started before a refresh may predate the change.
        if (!mode || root.modeProcGeneration !== root.modeGeneration) return
        var next = Object.assign({}, root.modes)
        next[root.modeProcWorkspace] = mode
        root.modes = next
      }
    }
    // Deferred: the process still reports running while it signals exit.
    onExited: Qt.callLater(root.readNextMode)
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") root.refresh()
      // Hyprland's window and workspace lists do not follow fullscreen on
      // their own.
      else if (name === "fullscreen") {
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
      }
    }
  }

  ShellIpc {
    target: "omarchy.dock"

    // The layout commands call this after changing a workspace's mode.
    function refresh(): void { root.refresh() }
    function apps(): void { appGrid.toggle() }
  }

  // Kept for the Hyprland bindings written for the original mushroom dock:
  // SUPER -> peek, SUPER+A -> cycle. Built-in callers keep using omarchy.dock.
  IpcHandler {
    target: "mushroom-dock"

    function toggle(): string {
      root.alwaysVisible = !root.alwaysVisible
      return root.alwaysVisible ? "pinned" : "auto"
    }
    function show(): string { root.alwaysVisible = true; return "ok" }
    function hide(): string {
      root.alwaysVisible = false
      root.dismiss()
      return "ok"
    }
    function peek(): string { root.peek(); return "ok" }
    function dismiss(): string { root.dismiss(); return "ok" }
    function cycle(step: string): string {
      return root.cycleApp(Number(step) < 0 ? -1 : 1) ? "ok" : "none"
    }
    function pin(id: string): string {
      root.setPinned(String(id), !root.isPinned(String(id)))
      return "ok"
    }
    function apps(): string { appGrid.toggle(); return "ok" }
    function refresh(): string { root.refresh(); return "ok" }
    function ping(): string { return "ok" }
  }

  // An app dragged out of the app grid: the grid holds the pointer and
  // reports where it is, and the dock on that screen shows where it would land.
  function dockOn(screen) {
    var windows = docks.instances
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].screen === screen) return windows[i]
    }
    return null
  }

  function moveExternalDrag(screen, x, y) {
    var windows = docks.instances
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].screen === screen) windows[i].moveExternalDrag(x, y)
      else windows[i].endExternalDrag()
    }
  }

  function dropExternalDrag(screen, x, y, key) {
    var target = root.dockOn(screen)
    if (target) target.dropExternalDrag(x, y, key)
    root.endExternalDrag()
  }

  function endExternalDrag() {
    var windows = docks.instances
    for (var i = 0; i < windows.length; i++) windows[i].endExternalDrag()
  }

  Variants {
    id: docks
    model: Quickshell.screens

    delegate: Component {
      DockWindow {
        required property var modelData

        screen: modelData
        dock: root
      }
    }
  }

  AppGrid {
    id: appGrid
    appLibrary: root.appLibrary
    dock: root
  }
}
