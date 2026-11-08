import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // The `home` workspace (the weather + news dashboard) is shown as a mushroom
  // tab before the numbered workspaces.
  readonly property bool homeFocused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.name === "home"

  function focusHome() {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"name:home\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : (root.workspaceIds().length + 1)
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    // Dashboard tab.
    Item {
      id: dashboardButton

      readonly property bool active: root.homeFocused
      property bool hovered: false

      implicitWidth: Style.space(24)
      implicitHeight: root.barSize

      Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) - Style.space(4)
        height: width
        radius: width / 2
        color: Util.alpha(Color.bar.background, dashboardButton.active ? 0.72 : (dashboardButton.hovered ? 0.5 : 0))
        border.width: 1
        border.color: dashboardButton.active ? Color.accent : Util.alpha(Color.foreground, dashboardButton.hovered ? 0.45 : 0)

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
      }

      Image {
        anchors.centerIn: parent
        source: Qt.resolvedUrl("mushroom.svg")
        sourceSize.width: 64
        sourceSize.height: 64
        width: 18
        height: 18
        smooth: true
        fillMode: Image.PreserveAspectFit
        opacity: dashboardButton.active ? 1 : (dashboardButton.hovered ? 1 : 0.75)
        scale: dashboardButton.hovered ? 1.12 : 1

        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
      }

      HoverHandler {
        id: dashboardHover
        onHoveredChanged: {
          dashboardButton.hovered = hovered
          if (!root.bar) return
          if (hovered) root.bar.showTooltip(dashboardButton, "Dashboard")
          else root.bar.hideTooltip(dashboardButton)
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.focusHome()
      }
    }

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
