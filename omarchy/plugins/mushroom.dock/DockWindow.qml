import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// One dock surface per screen.
//
// The layer-shell window stays mapped for its whole lifetime; showing is a
// position change, never a surface remap. Its input region is masked to an
// invisible hit area (the pill plus the magnification overflow and the strip to
// the screen edge) and a hair-thin bottom reveal strip, so the rest of the
// screen stays click-through.
PanelWindow {
  id: win

  required property var modelData
  property var dockRoot: null

  screen: modelData
  visible: true
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "mushroom-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // ---------------------------------------------------------------- geometry
  readonly property int iconSize: dockRoot ? dockRoot.iconSize : 40
  readonly property int iconGap: dockRoot ? dockRoot.iconGap : 8
  readonly property int appSlot: iconSize + iconGap
  readonly property int logoSlot: 48
  readonly property int sepSlot: 16
  readonly property int padH: 12
  readonly property int padV: 8
  readonly property int indicatorH: 3
  readonly property int indicatorGap: 5
  readonly property int pillRadius: 26
  readonly property int bottomMargin: 12
  readonly property int revealZonePx: Math.max(3, dockRoot ? dockRoot.revealZone : 5)
  readonly property real maxScale: dockRoot ? dockRoot.maxScale : 1.5
  readonly property real influence: dockRoot ? dockRoot.influence : 118
  readonly property real maxIcon: iconSize * maxScale

  // The resting pill is sized for unmagnified discs; magnified discs grow past
  // its top edge (the surface does not clip), keeping the dock slim while the
  // hover effect still has somewhere to go.
  readonly property real pillContentHeight: iconSize + indicatorGap + indicatorH
  readonly property real pillHeight: pillContentHeight + padV * 2
  readonly property real discBottom: pillHeight - padV + 1 - indicatorH - Math.round(iconSize * 0.16)
  readonly property real iconTopMax: discBottom - maxIcon
  readonly property real overflow: Math.max(0, Math.round(maxIcon - discBottom))
  readonly property real ready: dockRoot !== null && width > 0 && height > 0

  readonly property color skin: dockRoot ? dockRoot.skin : Color.foreground
  readonly property color accent: dockRoot ? dockRoot.accent : Color.accent
  readonly property color pillBase: Color.bar.background

  // ------------------------------------------------------------- reveal state
  property real pointerX: -100000
  property bool pointerInDock: false
  property bool pointerInTrigger: false
  property bool dockShown: false
  property bool hoverVisible: false
  property string hoverName: ""
  property int hoverCount: 0
  property real hoverOffsetX: 0

  readonly property bool pinnedOpen: dockRoot !== null && dockRoot.alwaysVisible
  readonly property bool shown: pinnedOpen || dockShown
  readonly property var apps: dockRoot ? dockRoot.apps : []

  // ---- derived geometry shared by the mask and the hit area ----------------
  // pill.x/pill.width are read live so the input region tracks magnification.
  readonly property real hitFullHeight: pillHeight + overflow + bottomMargin
  readonly property real hitY: shown ? (height - hitFullHeight) : (height + 6)

  function updateReveal() {
    if (pointerInDock || pointerInTrigger) {
      hideTimer.stop()
      dockShown = true
    } else {
      hideTimer.restart()
    }
  }

  // Summon: show, and stay up until the pointer leaves or the peek times out.
  function peekIn() {
    hideTimer.stop()
    peekTimer.stop()
    dockShown = true
    peekTimer.restart()
  }

  function dismiss() {
    hideTimer.stop()
    peekTimer.stop()
    dockShown = false
    hoverVisible = false
  }

  Timer {
    id: hideTimer
    interval: dockRoot ? dockRoot.hideDelay : 600
    onTriggered: if (!win.pointerInDock && !win.pointerInTrigger) win.dockShown = false
  }

  Timer {
    id: peekTimer
    interval: 4200
    onTriggered: if (!win.pointerInDock && !win.pointerInTrigger) win.dismiss()
  }

  Connections {
    target: dockRoot
    function onPeekSerialChanged() { win.peekIn() }
    function onDismissSerialChanged() { win.dismiss() }
    function onAlwaysVisibleChanged() { win.updateReveal() }
  }

  // --------------------------------------------------------------- geometry
  function slotBaseWidth(i) {
    if (i === 0) return logoSlot
    if (i === 1) return sepSlot
    return appSlot
  }

  function totalBaseWidth() {
    return logoSlot + sepSlot + win.apps.length * appSlot
  }

  // Centre of slot i in the *unmagnified* grid, relative to the row centre.
  // Computing magnification against this fixed grid means a growing slot can
  // never feed back into its own scale.
  function slotBaseOffset(i) {
    var off = 0
    for (var k = 0; k < i; k++) off += slotBaseWidth(k)
    return off + slotBaseWidth(i) / 2 - totalBaseWidth() / 2
  }

  function scaleFor(i) {
    if (!shown || pointerX < -50000) return 1
    var d = Math.abs((pointerX - width / 2) - slotBaseOffset(i))
    var t = Math.max(0, 1 - d / influence)
    return 1 + (maxScale - 1) * t * t
  }

  // Explicit input rectangles (rather than item references) so the region can
  // never go stale when the hit area moves on or off screen.
  mask: Region {
    Region { x: 0; y: win.height - win.revealZonePx; width: win.width; height: win.revealZonePx }
    Region { x: pill.x; y: win.hitY; width: pill.width; height: win.hitFullHeight }
  }

  // ------------------------------------------------------------- reveal strip
  Item {
    id: triggerZone
    x: 0
    y: win.height - win.revealZonePx
    width: win.width
    height: win.revealZonePx

    HoverHandler {
      id: triggerHover
      onHoveredChanged: {
        win.pointerInTrigger = hovered
        win.updateReveal()
      }
    }
  }

  // ------------------------------------------------------------------- pill
  Item {
    id: pill
    width: rowWidth + padH * 2
    height: win.pillHeight
    x: Math.round((win.width - width) / 2)
    y: win.shown ? Math.max(0, win.height - height - bottomMargin) : win.height + 6
    opacity: win.ready ? 1 : 0

    readonly property real rowWidth: {
      var w = logoSlot + sepSlot
      for (var i = 0; i < appRepeater.count; i++) {
        var it = appRepeater.itemAt(i)
        w += it ? it.width : appSlot
      }
      return w
    }

    Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    // Soft grounding shadow: the dock floats on its own depth (Hyprland blur is
    // off for layer surfaces).
    RectangularShadow {
      anchors.fill: parent
      radius: pillRadius
      blur: 30
      spread: 0
      offset: Qt.vector2d(0, 10)
      color: Util.alpha("#0b0908", 0.6)
    }

    // Borderless translucent mushroom-grove glass.
    Rectangle {
      anchors.fill: parent
      radius: pillRadius
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha(Qt.lighter(win.pillBase, 1.20), 0.93) }
        GradientStop { position: 0.5; color: Util.alpha(win.pillBase, 0.89) }
        GradientStop { position: 1.0; color: Util.alpha(Qt.darker(win.pillBase, 1.16), 0.93) }
      }
    }

    Row {
      id: row
      anchors.left: parent.left
      anchors.leftMargin: padH
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      // Mushroom launcher.
      Item {
        width: win.logoSlot
        height: win.pillHeight

        Image {
          id: logoImage
          source: Qt.resolvedUrl("icons/mushroom.svg")
          sourceSize.width: 96
          sourceSize.height: 96
          width: 36
          height: 36
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          smooth: true
          fillMode: Image.PreserveAspectFit
          scale: logoHover.hovered ? 1.14 : 1
          Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }

        HoverHandler { id: logoHover }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (!dockRoot) return
            if (mouse.button === Qt.RightButton) dockRoot.openTerminal()
            else dockRoot.openMenu()
          }
        }
      }

      // Hairline between launcher and apps.
      Item {
        width: win.sepSlot
        height: win.pillHeight

        Rectangle {
          width: 1
          height: Math.round(win.pillContentHeight * 0.5)
          anchors.centerIn: parent
          color: Util.alpha(win.skin, 0.14)
        }
      }

      Repeater {
        id: appRepeater
        model: win.apps

        Item {
          id: appButton

          required property int index
          required property var modelData

          readonly property var app: modelData
          readonly property int slotIndex: 2 + index
          readonly property bool running: app.windows !== undefined && app.windows.length > 0
          readonly property bool focused: dockRoot ? dockRoot.isFocused(app) : false

          property bool hovered: false
          property real magnify: win.scaleFor(slotIndex)
          property real bounce: 0

          width: win.appSlot + (magnify - 1) * win.iconSize
          height: win.pillHeight
          z: Math.round(magnify * 100)

          Behavior on magnify { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

          Item {
            id: appContent
            width: appButton.width
            height: appButton.height
            y: appButton.bounce

            // Soft accent bloom behind the focused app's disc.
            Rectangle {
              anchors.centerIn: disc
              width: disc.width + 10
              height: width
              radius: width / 2
              color: Util.alpha(win.accent, appButton.focused ? 0.16 : 0)
              z: -1
              Behavior on color { ColorAnimation { duration: 220 } }
            }

            // Circular chrome, matching the bar's top-right controls.
            BorderSurface {
              id: disc
              readonly property real diameter: win.iconSize * appButton.magnify
              width: diameter
              height: diameter
              radius: diameter / 2
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: appIndicator.top
              anchors.bottomMargin: Math.round(win.iconSize * 0.16)
              color: Qt.rgba(win.pillBase.r, win.pillBase.g, win.pillBase.b,
                appButton.focused ? 0.72 : (appButton.hovered ? 0.86 : 0.56))
              borderSpec: Border.flat(
                appButton.focused ? win.accent : Util.alpha(win.skin, appButton.hovered ? 0.55 : 0.20),
                appButton.focused ? 2 : 1)

              Behavior on color { ColorAnimation { duration: 150 } }
            }

            Image {
              id: appIcon
              width: Math.round(disc.width * 0.58)
              height: width
              anchors.centerIn: disc
              source: dockRoot ? dockRoot.iconSource(appButton.app.icon, appButton.app.appId) : ""
              sourceSize.width: 128
              sourceSize.height: 128
              smooth: true
              mipmap: true
              asynchronous: true
              fillMode: Image.PreserveAspectFit
            }

            // Instance count badge, shown when an app has more than one window.
            Rectangle {
              id: countBadge
              readonly property int count: appButton.app.windows ? appButton.app.windows.length : 0
              visible: count > 1
              width: Math.max(16, badgeText.implicitWidth + 9)
              height: 16
              radius: height / 2
              x: disc.x + disc.width - width * 0.55
              y: disc.y - height * 0.35
              color: win.accent
              border.width: 1.5
              border.color: Util.alpha(win.pillBase, 0.92)
              z: 20
              scale: visible ? 1 : 0.3
              Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

              Text {
                id: badgeText
                anchors.centerIn: parent
                text: countBadge.count
                color: "#171310"
                font.family: Style.font.family
                font.pixelSize: 10
                font.bold: true
              }
            }

            Rectangle {
              id: appIndicator
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: win.padV - 1
              height: win.indicatorH
              radius: height / 2
              width: !appButton.running ? 0 : (appButton.focused ? win.iconSize * 0.42 : win.iconSize * 0.15)
              color: appButton.focused ? win.accent : Util.alpha(win.skin, 0.62)
              Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
              Behavior on color { ColorAnimation { duration: 200 } }
            }
          }

          MouseArea {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height + win.overflow
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor

            onEntered: {
              appButton.hovered = true
              win.hoverName = appButton.app.name
              win.hoverCount = appButton.app.windows ? appButton.app.windows.length : 0
              win.hoverOffsetX = row.x + appButton.x + appButton.width / 2
              win.hoverVisible = true
            }
            onExited: {
              appButton.hovered = false
              win.hoverVisible = false
            }
            onClicked: function(mouse) {
              if (!dockRoot) return
              if (mouse.button === Qt.RightButton) {
                dockRoot.removeFromDock(appButton.app)
              } else if (mouse.button === Qt.MiddleButton) {
                dockRoot.launchApp(appButton.app)
                bounceAnim.restart()
              } else {
                if (dockRoot.activateApp(appButton.app)) bounceAnim.restart()
              }
            }
          }

          SequentialAnimation {
            id: bounceAnim
            NumberAnimation { target: appButton; property: "bounce"; to: -9; duration: 130; easing.type: Easing.OutQuad }
            NumberAnimation { target: appButton; property: "bounce"; to: 0; duration: 300; easing.type: Easing.OutBounce }
          }
        }
      }
    }

    // Shared label for the hovered app.
    Rectangle {
      id: tooltip

      visible: opacity > 0
      opacity: (win.hoverVisible && win.shown && win.pointerInDock) ? 1 : 0
      x: Math.max(6, Math.min(pill.width - width - 6, win.hoverOffsetX - width / 2))
      y: Math.round(win.iconTopMax - height - 8)
      width: tooltipLabel.implicitWidth + 22
      height: tooltipLabel.implicitHeight + 12
      radius: 8
      color: Util.alpha("#0b0908", 0.94)
      border.width: 1
      border.color: Util.alpha(accent, 0.45)
      z: 1000

      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      Text {
        id: tooltipLabel
        anchors.centerIn: parent
        text: win.hoverCount > 1 ? (win.hoverName + "  ·  " + win.hoverCount + " windows") : win.hoverName
        color: win.skin
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  // Invisible interaction cover, kept in sync with the mask's second region.
  Item {
    id: hitArea
    x: pill.x
    y: win.hitY
    width: pill.width
    height: win.hitFullHeight

    HoverHandler {
      id: pillHover
      onPointChanged: win.pointerX = hitArea.x + point.position.x
      onHoveredChanged: {
        win.pointerInDock = hovered
        if (!hovered) win.pointerX = -100000
        win.updateReveal()
      }
    }
  }
}
