pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "DashboardModel.js" as Model

// Mushroom Grove Dashboard
//
// A weather + news home page on the `home` workspace. DashboardWindow.qml
// renders it per monitor; this root owns the data, the home-workspace
// tracking and the IPC.
Item {
  id: root

  // Injected by the omarchy-shell host for panel plugins.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property bool opened: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string homeWorkspace: "home"
  readonly property string hnScript: Qt.resolvedUrl("hn.py").toString().replace(/^file:\/\//, "")

  // ------------------------------------------------------------- mushroom palette
  readonly property color skin: Color.foreground
  readonly property color accent: Color.accent
  readonly property color gold: "#e5b65d"
  readonly property color moss: "#9dbb6d"
  readonly property color teal: "#72b39e"

  // ---------------------------------------------------------------------- state
  property bool homeFocused: false
  property bool idle: false
  property string homeMonitor: ""
  property string lastWorkspace: "1"
  property string wallpaperPath: ""
  property var weather: null
  property var news: []
  property string newsFilter: ""
  property var hnItems: []
  property var rssBatches: []
  property int pendingNews: 0
  property bool newsLoading: false
  property var locationState: ({ name: "", latitude: null, longitude: null })

  property string clockText: ""
  property string dateText: ""
  property string greeting: ""
  property int nowRevision: 0

  readonly property string locationQuery: Model.locationQuery(locationState)

  // Distinct sources, in first-appearance order (Hacker News first).
  readonly property var newsSources: {
    var seen = {}
    var out = []
    for (var i = 0; i < news.length; i++) {
      var s = news[i].source
      if (s && !seen[s]) { seen[s] = true; out.push(s) }
    }
    return out
  }
  readonly property var filterTiles: ["All"].concat(newsSources)
  readonly property var filteredNews: {
    if (!newsFilter) return news
    var out = []
    for (var i = 0; i < news.length; i++) {
      if (news[i].source === newsFilter) out.push(news[i])
    }
    return out
  }

  // "All" clears the filter; tapping the active source toggles it off.
  function setNewsFilter(source) {
    var wanted = (!source || source === "All") ? "" : String(source)
    root.newsFilter = (root.newsFilter === wanted) ? "" : wanted
  }

  // --------------------------------------------------------------- visibility
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      var ws = Hyprland.focusedWorkspace
      var isHome = !!(ws && ws.name === root.homeWorkspace)
      if (!isHome && ws) root.lastWorkspace = String(ws.name || ws.id)
      if (isHome) {
        var mon = Hyprland.focusedMonitor
        root.homeMonitor = mon ? mon.name : ""
      }
      if (root.homeFocused !== isHome) {
        root.homeFocused = isHome
        if (isHome) root.refresh()
      }
    }
  }

  // Startup read: if the shell comes up while home is already focused, no
  // change signal may arrive, so ask directly.
  Process {
    id: workspaceScan
    command: ["hyprctl", "activeworkspace", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text || "{}"))
          root.homeFocused = (d.name === root.homeWorkspace)
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 1200
    running: true
    repeat: false
    onTriggered: {
      workspaceScan.running = true
      root.refresh()
    }
  }

  // Safety net: correct the home state if a focus event is ever missed.
  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: workspaceScan.running = true
  }

  // -------------------------------------------------------------------- clock
  function updateClock() {
    var d = new Date()
    root.clockText = Qt.formatDateTime(d, "HH:mm")
    root.dateText = Qt.formatDateTime(d, "dddd d MMMM")
    var h = d.getHours()
    root.greeting = h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.updateClock()
  }
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowRevision++
  }

  // 15s of no input hides the dashboard chrome and lets the wallpaper take
  // over (DashboardWindow speeds the swirl up too). Inhibitors are ignored so
  // a background video does not keep the chrome awake.
  IdleMonitor {
    id: idleMonitor
    enabled: true
    timeout: 15
    respectInhibitors: false
    onIsIdleChanged: root.idle = isIdle
  }

  Component.onCompleted: root.updateClock()

  function relativeTime(timestamp) {
    nowRevision
    return Model.relativeTime(timestamp, Date.now())
  }

  // ---------------------------------------------------------------- wallpaper
  Process {
    id: wallpaperProc
    command: ["readlink", "-f", root.home + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p) root.wallpaperPath = p
      }
    }
  }

  // ------------------------------------------------------------------ location
  FileView {
    id: locationFile
    path: root.home + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.locationState = Model.parseLocation(text()); root.refreshWeather() }
    onLoadFailed: { root.locationState = Model.parseLocation(""); root.refreshWeather() }
  }

  // ------------------------------------------------------------------- weather
  Process {
    id: weatherProc
    command: ["curl", "-fsS", "--max-time", "12", "https://wttr.in/" + root.locationQuery + "?format=j1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || ""))
          var parsed = Model.weatherFromReport(data, root.locationState.name)
          if (parsed) root.weather = parsed
        } catch (e) {}
      }
    }
  }

  function refreshWeather() {
    if (!weatherProc.running) weatherProc.running = true
  }

  // ---------------------------------------------------------------------- news
  function newsScript() {
    // Fetch feeds in parallel into a scratch dir, then emit each labelled
    // section in order so parsing stays simple and startup stays quick.
    var dir = "/tmp/mushroom-dashboard-feeds"
    var s = "d=" + Util.shellQuote(dir) + "; mkdir -p \"$d\"; "
    for (var i = 0; i < Model.feeds.length; i++) {
      s += "curl -fsS --max-time 8 " + Util.shellQuote(Model.feeds[i].url) + " > \"$d/" + i + "\" 2>/dev/null & "
    }
    s += "wait; "
    for (var j = 0; j < Model.feeds.length; j++) {
      s += "echo '@@FEED:" + j + "@@'; cat \"$d/" + j + "\"; "
    }
    s += "rm -rf \"$d\""
    return s
  }

  Process {
    id: hnProc
    command: ["python3", root.hnScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.hnItems = Model.parseHn(text)
        root.finishNews()
      }
    }
  }

  Process {
    id: newsProc
    command: ["bash", "-c", root.newsScript()]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.applyNews(text)
        root.finishNews()
      }
    }
  }

  function applyNews(raw) {
    var text = String(raw || "")
    var parts = text.split(/@@FEED:(\d+)@@/)
    var batches = []
    for (var i = 1; i + 1 < parts.length; i += 2) {
      var idx = parseInt(parts[i], 10)
      var feed = Model.feeds[idx] || { name: "News" }
      batches.push(Model.parseFeed(parts[i + 1], feed.name, 12))
    }
    root.rssBatches = batches
  }

  // Hacker News (in site order) first, then the RSS sources, interleaved so
  // every source keeps its own order.
  function finishNews() {
    root.pendingNews = Math.max(0, root.pendingNews - 1)
    if (root.pendingNews === 0) root.newsLoading = false
    root.news = Model.mergeNews([root.hnItems].concat(root.rssBatches), 40)
  }

  function refresh() {
    root.refreshWeather()
    wallpaperProc.running = true
    root.pendingNews = 2
    root.newsLoading = true
    if (!hnProc.running) hnProc.running = true
    if (!newsProc.running) newsProc.running = true
  }

  Timer {
    interval: 15 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // -------------------------------------------------------------------- actions
  function focusHome() {
    Util.execArgv(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"name:" + root.homeWorkspace + "\" })"])
  }
  function focusWorkspace(name) {
    if (!name) return
    Util.execArgv(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = \"" + name + "\" })"])
  }
  function toggleHome() {
    if (root.homeFocused) root.focusWorkspace(root.lastWorkspace)
    else root.focusHome()
  }

  // ------------------------------------------------------------------------ ipc
  IpcHandler {
    target: "mushroom-dashboard"
    function toggle(): string { root.toggleHome(); return "ok" }
    function show(): string { root.focusHome(); return "ok" }
    function hide(): string { if (root.homeFocused) root.toggleHome(); return "ok" }
    function refresh(): string { root.refresh(); return "ok" }
    function ping(): string { return "ok" }
  }

  // ------------------------------------------------------------------- surfaces
  Variants {
    model: Quickshell.screens
    DashboardWindow {
      dash: root
    }
  }
}
