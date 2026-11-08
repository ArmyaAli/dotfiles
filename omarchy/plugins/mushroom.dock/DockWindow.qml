import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DockModel.js" as DockModel

// One screen's dock. It stays mapped and only hides its contents, so switching
// to a floating workspace does not wait on a fresh layer surface. While hidden the
// mask is empty and clicks fall through to the windows below.
PanelWindow {
  id: window
  // Right-to-left languages read this window mirrored.
  Binding { target: window.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
  Binding { target: window.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }


  property var dock: null

  readonly property string position: dock ? dock.position : "bottom"
  readonly property bool vertical: dock ? dock.vertical : false
  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property var workspace: monitor ? monitor.activeWorkspace : null
  readonly property int workspaceId: workspace ? workspace.id : -1
  // The most fullscreen window on the workspace, as Hyprland counts it: 1 is
  // maximized, and 2 or 3 fullscreen.
  readonly property int fullscreenMode: {
    var mode = 0
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var toplevel = toplevels[i]
      if (!toplevel.workspace || toplevel.workspace.id !== workspaceId) continue
      var ipc = toplevel.lastIpcObject
      mode = Math.max(mode, ipc && ipc.fullscreen ? ipc.fullscreen : 0)
    }
    return mode
  }
  // The dock calls itself up: automatically on a floating workspace, when
  // pinned open with the IPC toggle, for a moment after a peek, and while the
  // pointer holds its edge.
  readonly property bool pinnedOpen: !!dock && dock.alwaysVisible
  readonly property bool floatingShown: !!dock && dock.isFloating(workspaceId) && fullscreenMode < 2
  property bool peekRevealed: false
  readonly property bool shown: floatingShown || pinnedOpen || peekRevealed || revealed
  // With auto-hide on, the dock waits off screen until the pointer reaches its
  // edge, and stays while the pointer, a menu, or a drag still needs it. A
  // maximized window hides the dock the same way, so it can still be called up.
  readonly property bool autohide: !!dock && (dock.autohide || fullscreenMode === 1)
  property bool revealed: false
  readonly property bool menuOpen: menuItem !== null || settingsMenu
  readonly property bool revealHold: revealed || menuOpen || dragging || insertIndex >= 0 || pinnedOpen || peekRevealed
  // Off a floating workspace the dock is tucked away by default, so it reads
  // as an on-demand dock rather than a permanent slab.
  readonly property bool tucked: !revealHold && (autohide || !floatingShown)
  readonly property bool contentShown: shown && !tucked

  readonly property int padH: Style.spacing.xxl
  readonly property int padV: Style.spacing.lg
  readonly property int pillRadius: Math.round(window.slotSize * 0.5)
  readonly property color pillBase: Commons.Color.bar.background
  readonly property color pillAccent: Commons.Color.accent
  readonly property color pillSkin: Commons.Color.foreground
  // The hovered app's label, shared by the disc row's one tooltip.
  property string hoverName: ""
  property int hoverCount: 0
  property Item hoverSlot: null
  // Proximity magnification: discs grow toward the pointer along the dock.
  // The scale is read from the unmagnified slot grid so a growing disc cannot
  // feed back into its own scale.
  readonly property real maxScale: 1.5
  readonly property real influence: 118
  readonly property int indicatorHeight: Style.space(3)
  readonly property int indicatorGap: Style.space(5)
  property real pointerX: -100000
  property bool pointerInDock: false
  readonly property bool magnifyEnabled: contentShown && !dragging && !hoverStale && insertIndex < 0

  function slotCenter(index) {
    return window.padH + index * window.slotSize + window.slotSize / 2
  }

  function scaleFor(index) {
    if (!magnifyEnabled || pointerX < -50000) return 1
    var distance = Math.abs(pointerX - slotCenter(index))
    var falloff = Math.max(0, 1 - distance / influence)
    return 1 + (maxScale - 1) * falloff * falloff
  }

  function peekIn() {
    peekTimer.stop()
    hideTimer.stop()
    window.peekRevealed = true
  }

  function dismissPeek() {
    peekTimer.stop()
    hideTimer.stop()
    window.peekRevealed = false
    window.revealed = false
  }

  function updateReveal() {
    if (window.pinnedOpen || window.peekRevealed) {
      hideTimer.stop()
      return
    }
    if (bodyHover.hovered || edgeHover.hovered || window.menuOpen || window.dragging) hideTimer.stop()
    else hideTimer.restart()
  }

  readonly property int gap: Style.spacing.xs
  readonly property int iconSize: Math.round(36 * Style.fontScale)
  // Each app has a square slot with its icon in the middle, and the slots run
  // straight to the edge of the dock.
  readonly property int iconInset: Style.spacing.md
  readonly property int slotSize: iconSize + iconInset * 2
  // A pinned app that is not running is drawn faded.
  readonly property real idleOpacity: 0.7
  // Room inward of the dock for its menus: the tallest, the apps button's,
  // has five rows.
  readonly property int popupRoom: Style.spacing.popupRowHeight * 5 + Style.spacing.sm * 2 + Style.normalBorderWidth * 2 + gap * 2
  // Icons pop away from the screen edge.
  readonly property int popOrigin: position === "top" ? Item.Top
    : position === "left" ? Item.Left
    : position === "right" ? Item.Right
    : Item.Bottom

  // The app being dragged along the dock, how far the pointer has taken it,
  // and the slot it would land in.
  property int dragIndex: -1
  property int dropIndex: -1
  property real dragOffset: 0
  readonly property bool dragging: dragIndex >= 0
  // Off while a drop resets the slots: they snap to where the reorder puts
  // them rather than sliding back from where they stepped aside. Set before
  // the drag state changes, so the slots never see the reset animated.
  property bool animateShifts: true
  // After a drop the slots have moved under a pointer that has not, so what
  // they think is hovered is stale until it moves again.
  property bool hoverStale: false
  property point dropPoint
  // Where an app dragged in from the app grid would land, or -1.
  property int insertIndex: -1

  // Where this window sits on its screen, which a point from the app grid's
  // fullscreen surface is given in: against its edge, clear of the space
  // other surfaces such as the bar reserve. Hyprland lists that space as
  // left, top, right, bottom.
  function origin() {
    var reserved = monitor && monitor.lastIpcObject && monitor.lastIpcObject.reserved ? monitor.lastIpcObject.reserved : [0, 0, 0, 0]
    var left = reserved[0] || 0, top = reserved[1] || 0, right = reserved[2] || 0, bottom = reserved[3] || 0
    var x = window.position === "right" ? screen.width - right - window.width : left
    var y = window.position === "bottom" ? screen.height - bottom - window.height : top
    return Qt.point(x, y)
  }

  // An app from the app grid lands where the pointer is, once it is over the
  // dock or close to it on the inward side.
  function moveExternalDrag(screenX, screenY) {
    var at = window.origin()
    var point = Qt.point(screenX - at.x - body.x - window.padH, screenY - at.y - body.y - window.padV)
    var reach = window.slotSize
    var along = window.vertical ? point.y : point.x
    var across = window.vertical ? point.x : point.y
    var length = window.vertical ? body.height : body.width
    var depth = window.vertical ? body.width : body.height
    var near = along >= -window.slotSize && along <= length + window.slotSize && across >= -reach && across <= depth + reach
    if (near) window.revealed = true
    window.insertIndex = near ? window.slotIndexAt(point) : -1
  }

  function dropExternalDrag(screenX, screenY, key) {
    window.moveExternalDrag(screenX, screenY)
    window.settleShifts()
    if (window.insertIndex >= 0 && key && window.dock) window.dock.pinAt(key, window.insertIndex)
    window.endExternalDrag()
  }

  function endExternalDrag() {
    window.insertIndex = -1
    if (window.autohide) hideTimer.restart()
  }

  // The slot a point along the dock falls before, counting from the first app.
  function slotIndexAt(point) {
    var along = window.vertical ? point.y : point.x
    var first = window.slotSize
    var count = window.dock ? window.dock.itemModel.count : 0
    return Math.max(0, Math.min(count, Math.round((along - first) / window.slotSize)))
  }
  property var menuItem: null
  property Item menuSlot: null
  // The apps button's menu: where the dock sits and whether it hides.
  property bool settingsMenu: false

  onWorkspaceIdChanged: {
    if (dock) dock.readMode(workspaceId)
    window.peekRevealed = false
    window.revealed = false
  }
  onShownChanged: {
    if (shown) return
    closeMenu()
    window.peekRevealed = false
    window.revealed = false
  }
  Component.onCompleted: if (dock) dock.readMode(workspaceId)

  Timer {
    id: peekTimer
    interval: 4200
    onTriggered: {
      if (bodyHover.hovered || edgeHover.hovered || window.menuOpen || window.dragging) return
      window.peekRevealed = false
    }
  }

  Connections {
    target: window.dock
    function onPeekSerialChanged() { window.peekIn() }
    function onDismissSerialChanged() { window.dismissPeek() }
    function onAlwaysVisibleChanged() {
      if (window.dock && window.dock.alwaysVisible) {
        peekTimer.stop()
        hideTimer.stop()
      }
      window.updateReveal()
    }
  }

  function openMenu(item, slot) {
    window.settingsMenu = false
    window.menuItem = item
    window.menuSlot = slot
  }

  function openSettingsMenu(slot) {
    window.menuItem = null
    window.settingsMenu = true
    window.menuSlot = slot
  }

  function settleShifts() {
    window.animateShifts = false
    Qt.callLater(function() { window.animateShifts = true })
  }

  function endDrag() {
    window.settleShifts()
    window.hoverStale = true
    window.dragIndex = -1
    window.dropIndex = -1
    window.dragOffset = 0
  }

  function closeMenu() {
    window.menuItem = null
    window.settingsMenu = false
    window.menuSlot = null
    if (window.autohide) hideTimer.restart()
  }

  // Places the menu inward of the dock, centered on a slot.
  function popupX(slot, popup) {
    if (!slot) return 0
    var center = slot.mapToItem(window.contentItem, slot.width / 2, 0).x
    if (window.position === "left") return body.x + body.width + window.gap
    if (window.position === "right") return body.x - window.gap - popup.width
    return Math.max(window.gap, Math.min(window.width - popup.width - window.gap, center - popup.width / 2))
  }

  function popupY(slot, popup) {
    if (!slot) return 0
    var center = slot.mapToItem(window.contentItem, 0, slot.height / 2).y
    if (window.position === "top") return body.y + body.height + window.gap
    if (window.position === "bottom") return body.y - window.gap - popup.height
    return Math.max(window.gap, Math.min(window.height - popup.height - window.gap, center - popup.height / 2))
  }

  visible: !remapGuard.remapping
  color: "transparent"
  WlrLayershell.namespace: "omarchy-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Kept clear of the bar's reserved edge, without reserving one of its own:
  // floating windows go where they are put.
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  anchors {
    top: window.position !== "bottom"
    bottom: window.position !== "top"
    left: window.position !== "right"
    right: window.position !== "left"
  }

  implicitWidth: window.vertical ? window.gap + window.slotSize + window.padH * 2 + window.popupRoom : 0
  implicitHeight: window.vertical ? 0 : window.gap + window.slotSize + window.padV * 2 + window.popupRoom

  mask: Region {
    item: window.contentShown ? body : null

    // While the pill is tucked away only its edge strip takes input, so the
    // rest of the screen stays click-through.
    Region { item: window.contentShown ? null : edgeTrigger }
    Region { item: menu.visible ? menu : null }
  }

  onAutohideChanged: window.revealed = false

  Timer {
    id: hideTimer
    // Long enough to cross a gap between the edge and the icons, no longer.
    interval: 150
    onTriggered: {
      if (window.pinnedOpen || window.peekRevealed) return
      if (!bodyHover.hovered && !edgeHover.hovered && !window.menuOpen && !window.dragging) window.revealed = false
    }
  }

  // The strip along the screen edge that brings an auto-hidden dock back.
  Item {
    id: edgeTrigger

    readonly property int depth: window.gap + Style.spacing.xxs

    x: window.position === "left" ? 0 : window.position === "right" ? window.width - depth : body.x
    y: window.position === "top" ? 0 : window.position === "bottom" ? window.height - depth : body.y
    width: window.vertical ? depth : body.width
    height: window.vertical ? body.height : depth

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) {
          peekTimer.stop()
          window.revealed = true
        } else {
          hideTimer.restart()
        }
      }
    }
  }

  ScreenMoveRemap {
    id: remapGuard
    window: window
  }

  HyprlandFocusGrab {
    active: window.menuOpen
    windows: [window]
    onCleared: window.closeMenu()
  }

  Item {
    id: body

    // The strip keeps its order in every language, like the bar: drags and
    // drops reckon slots along x from the first app. Only the menu mirrors.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    width: slots.implicitWidth + window.padH * 2
    height: slots.implicitHeight + window.padV * 2
    // How far the dock is tucked past its edge. It slides fully off, so only
    // the edge strip stays reachable while it is hidden.
    property real tuck: window.tucked ? height + window.gap : 0

    // Tucking away is quicker than coming back. A gentler curve than
    // Style.easeOut, which crosses the short slide in a frame or two.
    Behavior on tuck {
      id: tuckMotion
      NumberAnimation {
        duration: Style.duration(tuckMotion.targetValue > 0 ? 140 : 200)
        easing.type: Easing.OutCubic
      }
    }

    x: window.position === "left" ? window.gap - tuck
      : window.position === "right" ? window.width - width - window.gap + tuck
      : Math.round((window.width - width) / 2)
    y: window.position === "top" ? window.gap - tuck
      : window.position === "bottom" ? window.height - height - window.gap + tuck
      : Math.round((window.height - height) / 2)
    // Hidden by opacity rather than visibility, so the icons keep their
    // textures and are drawn on the first frame back instead of being uploaded
    // again.
    opacity: window.contentShown ? 1 : 0

    // Soft grounding shadow: the dock floats on its own depth (Hyprland blur
    // is off for layer surfaces).
    RectangularShadow {
      anchors.fill: pill
      radius: pill.radius
      blur: 30
      spread: 0
      offset: Qt.vector2d(window.vertical ? (window.position === "right" ? 10 : -10) : 0,
                          window.vertical ? 0 : (window.position === "top" ? -10 : 10))
      color: Util.alpha(Commons.Color.background, 0.6)
    }

    // Borderless translucent mushroom-grove glass, tinted by the active theme.
    Rectangle {
      id: pill
      anchors.fill: parent
      radius: window.pillRadius
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha(Qt.lighter(window.pillBase, 1.20), 0.93) }
        GradientStop { position: 0.5; color: Util.alpha(window.pillBase, 0.89) }
        GradientStop { position: 1.0; color: Util.alpha(Qt.darker(window.pillBase, 1.16), 0.93) }
      }
    }

    HoverHandler {
      id: bodyHover
      onHoveredChanged: {
        window.pointerInDock = hovered
        if (!hovered) window.pointerX = -100000
        if (hovered) window.revealed = true
        window.updateReveal()
      }
      // Only a real move clears it: the release itself reports the pointer too.
      onPointChanged: {
        window.pointerX = (window.vertical ? point.position.y : point.position.x) - (window.vertical ? window.padV : window.padH)
        if (!window.hoverStale || window.dragging) return
        var at = point.position
        if (Math.hypot(at.x - window.dropPoint.x, at.y - window.dropPoint.y) > Style.space(4)) window.hoverStale = false
      }
    }

    Grid {
      id: slots
      x: window.padH
      y: window.padV
      columns: window.vertical ? 1 : appRepeater.count + 1

      AppsSlot {}

      Repeater {
        id: appRepeater
        model: window.dock ? window.dock.itemModel : null

        delegate: AppSlot {}
      }
    }

    // One label for the hovered app, drawn inward of the dock.
    Rectangle {
      id: tooltip

      readonly property var slot: window.hoverSlot

      visible: opacity > 0
      opacity: window.contentShown && slot !== null ? 1 : 0
      width: label.implicitWidth + Style.spacing.xxl
      height: label.implicitHeight + Style.spacing.md
      radius: Style.cornerRadius
      color: Util.alpha(Commons.Color.background, 0.94)
      border.width: Math.max(1, Style.space(1))
      border.color: Util.alpha(window.pillAccent, 0.45)
      z: 1000

      x: {
        if (!slot) return 0
        if (window.position === "left") return body.width + window.gap
        if (window.position === "right") return -width - window.gap
        var center = slot.mapToItem(body, slot.width / 2, 0).x
        return Math.max(window.gap, Math.min(body.width - width - window.gap, center - width / 2))
      }
      y: {
        if (window.position === "top") return body.height + window.gap
        if (window.position === "bottom") return -height - window.gap
        var center = slot ? slot.mapToItem(body, 0, slot.height / 2).y : 0
        return Math.max(window.gap, Math.min(body.height - height - window.gap, center - height / 2))
      }

      Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

      Text {
        id: label
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: window.hoverName + (window.hoverCount > 1 ? "  ·  " + window.hoverCount + " windows" : "")
        color: window.pillSkin
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  component Slot: Item {
    id: slot

    // Only the dragged icon is lifted while a drag is on; none of the others
    // pop as it passes over them.
    property bool hovered: mouse.containsMouse && !window.hoverStale && !window.dragging
    property bool pressed: mouse.pressed
    property alias mouse: mouse

    width: window.slotSize
    height: window.slotSize

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    }
  }

  component AppsSlot: Slot {
    id: appsSlot

    property real displayedShift: window.insertIndex >= 0 ? -window.slotSize / 2 : 0

    Behavior on displayedShift {
      enabled: window.animateShifts
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    transform: Translate {
      x: window.vertical ? 0 : appsSlot.displayedShift
      y: window.vertical ? appsSlot.displayedShift : 0
    }

    mouse.onClicked: function(event) {
      // Launcher: left summons the Omarchy menu, right a terminal, middle the
      // app grid. Shift+left keeps the stock dock settings menu reachable.
      if (event.modifiers & Qt.ShiftModifier) {
        window.openSettingsMenu(appsSlot)
        return
      }
      window.closeMenu()
      if (event.button === Qt.RightButton) {
        if (window.dock) window.dock.openTerminal()
      } else if (event.button === Qt.MiddleButton) {
        if (window.dock) window.dock.openApps()
      } else if (window.dock) {
        window.dock.openMenu()
      }
    }

    // The mushroom mark, sized like an app icon so the disc row stays even.
    Image {
      source: Qt.resolvedUrl("icons/mushroom.svg")
      sourceSize: Qt.size(window.iconSize * 3, window.iconSize * 3)
      width: Math.round(window.iconSize * 1.05)
      height: width
      anchors.centerIn: parent
      smooth: true
      mipmap: true
      fillMode: Image.PreserveAspectFit
      transform: Translate {
        x: window.vertical ? 0 : appsSlot.displayedShift
        y: window.vertical ? appsSlot.displayedShift : 0
      }
      scale: appsSlot.hovered ? 1.14 : 1
      transformOrigin: window.popOrigin

      Behavior on scale { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
    }
  }

  component AppSlot: Slot {
    id: appSlot

    required property int index
    required property string key
    readonly property var modelData: window.dock ? window.dock.itemFor(key) : null
    readonly property bool launching: !!window.dock && window.dock.isLaunching(key)
    readonly property bool lifted: window.dragIndex === index
    property point pressPoint
    property bool dragged: false
    readonly property int windowCount: modelData ? modelData.windows.length : 0
    property real pulse: 1

    // Proximity magnification reads the pointer's place along the dock; the
    // slot widens as its disc grows so neighbours make room.
    readonly property real magnify: window.scaleFor(index + 1)
    readonly property bool running: windowCount > 0
    readonly property bool focused: {
      if (!modelData) return false
      for (var i = 0; i < modelData.windows.length; i++) {
        var toplevel = modelData.windows[i].toplevel
        if (toplevel && toplevel.activated) return true
      }
      return false
    }
    readonly property var entry: window.dock ? window.dock.entryFor(modelData) : null
    property real bounce: 0

    width: window.slotSize + (magnify - 1) * window.iconSize

    Behavior on width {
      NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
    }

    mouse.onEntered: {
      window.hoverName = appSlot.entry && appSlot.entry.name ? appSlot.entry.name : String(appSlot.key)
      window.hoverCount = appSlot.windowCount
      window.hoverSlot = appSlot
    }

    mouse.onExited: {
      if (window.hoverSlot === appSlot) window.hoverSlot = null
    }

    // Slots between where the dragged app was and where it would land step
    // aside to make room; the dragged one follows the pointer.
    readonly property real shift: window.insertIndex >= 0 ? (index >= window.insertIndex ? 1 : -1) * window.slotSize / 2
      : !window.dragging ? 0
      : lifted ? window.dragOffset
      : (window.dragIndex < index && index <= window.dropIndex) ? -window.slotSize
      : (window.dropIndex <= index && index < window.dragIndex) ? window.slotSize
      : 0
    property real displayedShift: shift

    // Only while dragging: once the drop reorders the slots, they are already
    // where they were shown.
    Behavior on displayedShift {
      enabled: window.animateShifts && ((window.dragging && !appSlot.lifted) || window.insertIndex >= 0)
      NumberAnimation { duration: Style.duration(150); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }

    z: lifted ? 1 : 0

    // The slot, and the pointer handling in it, stays where it is; only the
    // icon moves. Reading the pointer through a slot that moves with it would
    // feed each move back into the next.
    function bodyPoint(event) {
      return appSlot.mapToItem(body, event.x, event.y)
    }

    mouse.onPressed: function(event) {
      appSlot.dragged = false
      if (event.button === Qt.LeftButton) appSlot.pressPoint = appSlot.bodyPoint(event)
    }

    mouse.onPositionChanged: function(event) {
      if (!(appSlot.mouse.pressedButtons & Qt.LeftButton)) return
      var point = appSlot.bodyPoint(event)
      var delta = window.vertical ? point.y - appSlot.pressPoint.y : point.x - appSlot.pressPoint.x
      // A press that wanders is a drag in the making, not a click.
      if (Math.hypot(point.x - appSlot.pressPoint.x, point.y - appSlot.pressPoint.y) > Style.space(4)) appSlot.dragged = true
      if (!window.dragging) {
        if (Math.abs(delta) < Style.space(6)) return
        window.closeMenu()
        // The landing slot first: with the dragged slot set and no landing
        // slot yet, every slot before it would count as in between and step
        // aside for a moment.
        window.dropIndex = appSlot.index
        window.dragIndex = appSlot.index
      }
      if (!appSlot.lifted) return
      window.dragOffset = delta
      window.dropIndex = DockModel.dropIndex(appSlot.index, delta, window.slotSize, appRepeater.count)
    }

    mouse.onReleased: function(event) {
      if (!appSlot.lifted) return
      window.dropPoint = appSlot.mapToItem(body, event.x, event.y)
      var from = window.dragIndex
      var to = window.dropIndex
      appSlot.dragged = true
      window.endDrag()
      window.dock.moveItem(from, to)
    }

    mouse.onCanceled: if (appSlot.lifted) window.endDrag()

    mouse.onClicked: function(event) {
      // A drag ends in a release over the app, which is not a click on it.
      if (appSlot.dragged) {
        appSlot.dragged = false
        return
      }
      if (event.button === Qt.RightButton) {
        window.openMenu(appSlot.modelData, appSlot)
        return
      }
      window.closeMenu()
      if (event.button === Qt.MiddleButton) window.dock.launch(appSlot.modelData)
      else window.dock.activate(appSlot.modelData)
      bounceAnim.restart()
    }

    // The icon chrome: a circular disc tinted from the bar, its icon inside,
    // the instance badge, and the running indicator. The disc grows toward the
    // pointer and the slot widens around it.
    Item {
      id: chrome
      width: window.slotSize
      height: window.slotSize

      transform: Translate {
        x: window.vertical ? 0 : appSlot.displayedShift
        y: window.vertical ? appSlot.displayedShift : 0
      }

      Item {
        id: chromeBody

        width: window.slotSize
        height: window.slotSize

        y: appSlot.bounce

        // Soft accent bloom behind the focused app's disc.
        Rectangle {
          anchors.centerIn: disc
          width: disc.width + Style.space(10)
          height: width
          radius: width / 2
          color: Util.alpha(window.pillAccent, appSlot.focused ? 0.16 : 0)
          z: -1

          Behavior on color { ColorAnimation { duration: 220 } }
        }

        BorderSurface {
          id: disc

          readonly property real diameter: window.iconSize * appSlot.magnify

          width: diameter
          height: diameter
          radius: diameter / 2
          x: Math.round((window.slotSize - width) / 2)
          // Horizontal docks keep the disc clear of the indicator below it;
          // vertical docks center it in the slot.
          y: window.vertical
            ? Math.round((window.slotSize - height) / 2)
            : window.slotSize - window.indicatorGap - window.indicatorHeight - Math.round(window.iconSize * 0.10) - height
          color: Qt.rgba(window.pillBase.r, window.pillBase.g, window.pillBase.b,
            appSlot.focused ? 0.72 : (appSlot.hovered ? 0.86 : 0.56))
          borderSpec: Border.flat(
            appSlot.focused ? window.pillAccent : Util.alpha(window.pillSkin, appSlot.hovered ? 0.55 : 0.20),
            appSlot.focused ? 2 : 1)

          Behavior on color { ColorAnimation { duration: 150 } }
        }

        Image {
          id: appIcon

          width: Math.round(disc.width * 0.58)
          height: width
          anchors.centerIn: disc
          source: window.dock && appSlot.modelData ? window.dock.iconFor(appSlot.modelData) : ""
          sourceSize: Qt.size(Math.round(window.iconSize * window.maxScale * 2), Math.round(window.iconSize * window.maxScale * 2))
          asynchronous: true
          smooth: true
          mipmap: true
          fillMode: Image.PreserveAspectFit
          opacity: appSlot.launching ? appSlot.pulse : (appSlot.running ? 1 : window.idleOpacity)
        }

        // Instance count badge, shown when an app has more than one window.
        Rectangle {
          id: countBadge

          readonly property int count: appSlot.windowCount

          visible: count > 1
          width: Math.max(16, Math.round(Style.font.bodySmall * 1.4))
          height: width
          radius: width / 2
          x: disc.x + disc.width - width * 0.55
          y: disc.y - height * 0.35
          z: 20
          color: window.pillAccent
          border.width: Math.max(1, Style.space(1.5))
          border.color: Util.alpha(window.pillBase, 0.92)

          Text {
            anchors.centerIn: parent
            text: countBadge.count
            color: Commons.Color.background
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

        // Running indicator: a dot under horizontal docks, a bar against the
        // inner edge of vertical ones.
        Rectangle {
          id: appIndicator

          readonly property real dotWidth: appSlot.focused ? Math.round(window.iconSize * 0.42) : Math.round(window.iconSize * 0.15)

          visible: appSlot.running
          width: window.vertical ? window.indicatorHeight : dotWidth
          height: window.vertical ? Math.round(window.iconSize * 0.42) : window.indicatorHeight
          radius: Math.min(width, height) / 2
          x: window.vertical
            ? (window.position === "left" ? window.slotSize - width - 1 : 1)
            : Math.round((window.slotSize - width) / 2)
          y: window.vertical
            ? Math.round((window.slotSize - height) / 2)
            : window.slotSize - height - 1
          color: appSlot.focused ? window.pillAccent : Util.alpha(window.pillSkin, 0.62)

          Behavior on color { ColorAnimation { duration: 200 } }
        }
      }
    }

    // With animations off it holds still rather than spinning through
    // zero-length steps.
    SequentialAnimation {
      running: appSlot.launching && !Style.reduceMotion
      loops: Animation.Infinite
      onRunningChanged: if (!running) appSlot.pulse = 1

      NumberAnimation { target: appSlot; property: "pulse"; from: 1; to: window.idleOpacity; duration: Style.duration(500); easing.type: Easing.InOutSine }
      NumberAnimation { target: appSlot; property: "pulse"; to: 1; duration: Style.duration(500); easing.type: Easing.InOutSine }
    }

    SequentialAnimation {
      id: bounceAnim
      NumberAnimation { target: appSlot; property: "bounce"; to: -9; duration: 130; easing.type: Easing.OutQuad }
      NumberAnimation { target: appSlot; property: "bounce"; to: 0; duration: 300; easing.type: Easing.OutBounce }
    }
  }

  BorderSurface {
    id: menu

    readonly property var item: window.menuItem
    readonly property bool hasEntry: !!item && !!window.dock && !!window.dock.entryFor(item)
    readonly property bool running: !!item && item.windows.length > 0

    visible: window.contentShown && (!!item || window.settingsMenu)
    width: Math.max(Style.space(140), menuColumn.implicitWidth) + padding * 2
    height: menuColumn.implicitHeight + padding * 2
    x: window.popupX(window.menuSlot, menu)
    y: window.popupY(window.menuSlot, menu)
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
    padding: Style.spacing.sm

    Column {
      id: menuColumn
      x: menu.contentLeftInset
      y: menu.contentTopInset
      width: menu.width - menu.contentLeftInset - menu.contentRightInset

      Repeater {
        model: [["top", Commons.I18n.t("dock.positionTop")], ["bottom", Commons.I18n.t("dock.positionBottom")], ["left", Commons.I18n.t("dock.positionLeft")], ["right", Commons.I18n.t("dock.positionRight")]]

        delegate: MenuRow {
          required property var modelData

          visible: window.settingsMenu
          text: modelData[1]
          checked: window.position === modelData[0]
          onTriggered: Util.execDetached("omarchy-dock position " + modelData[0])
        }
      }

      MenuRow {
        visible: window.settingsMenu
        text: Commons.I18n.t("dock.autoHide")
        checked: window.autohide
        onTriggered: Util.execDetached("omarchy-dock autohide " + (window.autohide ? "off" : "on"))
      }

      MenuRow {
        visible: menu.hasEntry && menu.running
        text: Commons.I18n.t("dock.newWindow")
        onTriggered: window.dock.launch(menu.item)
      }

      MenuRow {
        visible: menu.hasEntry
        text: menu.item && menu.item.pinned ? Commons.I18n.t("dock.removeFromDock") : Commons.I18n.t("dock.keepInDock")
        onTriggered: window.dock.setPinned(menu.item.key, !menu.item.pinned)
      }

      MenuRow {
        visible: menu.running
        text: Commons.I18n.t("dock.quit")
        onTriggered: window.dock.quit(menu.item)
      }
    }
  }

  component MenuRow: Rectangle {
    id: row

    property string text: ""
    property bool checked: false
    signal triggered()

    width: parent ? parent.width : 0
    height: visible ? Style.spacing.popupRowHeight : 0
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Style.hoverFill : "transparent"

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: row.text
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      visible: row.checked
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: "✓"
      color: Commons.Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        row.triggered()
        window.closeMenu()
      }
    }
  }
}
