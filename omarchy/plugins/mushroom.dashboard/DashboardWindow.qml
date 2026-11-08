import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// One dashboard surface per screen. It is only mapped while the `home`
// workspace is focused on that monitor.
PanelWindow {
  id: win

  required property var modelData
  property var dash: null

  screen: modelData
  visible: dash !== null && dash.homeFocused
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "mushroom-dashboard"
  // Sits above the wallpaper but below the bar and normal windows, so the
  // animated background is seamless under the bar.
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  readonly property color skin: dash ? dash.skin : Color.foreground
  readonly property color accent: dash ? dash.accent : Color.accent
  readonly property var weather: dash ? dash.weather : null
  // Dashboard chrome fades away when idle so only the artwork is left.
  readonly property real contentOpacity: (dash && dash.idle) ? 0.0 : 0.88

  // Quiet single-tone card edge so the cards sit on the artwork without a
  // colourful rim competing with it.
  readonly property var cardBorderSpec: Border.flat(Util.alpha(win.skin, 0.10), 1)

  // ------------------------------------------------------------- wallpaper
  // The theme wallpaper, warped by a slow swirl (vortex) on the home workspace.
  Item {
    anchors.fill: parent
    clip: true

    Image {
      id: wallpaper
      anchors.fill: parent
      source: dash && dash.wallpaperPath ? Util.fileUrl(dash.wallpaperPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      smooth: true
      cache: false
    }

    ShaderEffectSource {
      id: wallpaperTexture
      sourceItem: wallpaper
      anchors.fill: parent
      live: true
      hideSource: true
      smooth: true
    }

    ShaderEffect {
      id: vortexEffect
      anchors.fill: parent
      property var source: wallpaperTexture
      property real time: 0
      property real strength: 0.8

      fragmentShader: Qt.resolvedUrl("vortex.frag.qsb")

      Timer {
        interval: 33
        running: true
        repeat: true
        onTriggered: vortexEffect.time += (dash && dash.idle ? 0.10 : 0.033)
      }
    }
  }

  // Gentle wash for legibility; light enough to keep the artwork visible.
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: Util.alpha(Color.background, 0.52) }
      GradientStop { position: 0.45; color: Util.alpha(Color.background, 0.22) }
      GradientStop { position: 1.0; color: Util.alpha(Color.background, 0.60) }
    }
  }

  // ---------------------------------------------------------------- header
  Item {
    id: header
    opacity: win.contentOpacity
    Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutCubic } }
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: 56
    height: 76

    Image {
      id: logo
      source: Qt.resolvedUrl("icons/mushroom.svg")
      sourceSize.width: 128
      sourceSize.height: 128
      width: 60
      height: 60
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      smooth: true
      fillMode: Image.PreserveAspectFit
    }

    Column {
      anchors.left: logo.right
      anchors.leftMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2

      Text {
        text: "Mushroom Grove"
        color: win.skin
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
      }
      Text {
        text: dash ? dash.greeting : ""
        color: Util.alpha(win.skin, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    Column {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        anchors.right: parent.right
        text: dash ? dash.clockText : ""
        color: win.skin
        font.family: Style.font.family
        font.pixelSize: 46
        font.bold: true
      }
      Text {
        anchors.right: parent.right
        text: dash ? dash.dateText : ""
        color: Util.alpha(win.skin, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
      }
    }
  }

  // ---------------------------------------------------------------- content
  Row {
    id: content
    anchors.top: header.bottom
    anchors.topMargin: 30
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: 56
    anchors.rightMargin: 56
    anchors.bottomMargin: 56
    spacing: 24

    // -------------------------------------------------------- weather card
    Item {
      id: weatherWrap
      width: Math.min(440, Math.round(content.width * 0.38))
      height: content.height

      RectangularShadow {
        anchors.fill: parent
        radius: 4
        blur: 34
        spread: 0
        offset: Qt.vector2d(0, 12)
        color: Util.alpha("#0b0908", 0.55)
      }

      BorderSurface {
        id: weatherCard
        opacity: win.contentOpacity
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutCubic } }
        anchors.fill: parent
        radius: 4
        borderSpec: win.cardBorderSpec
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(Qt.lighter(Color.background, 1.16), 0.30) }
          GradientStop { position: 1.0; color: Util.alpha(Qt.darker(Color.background, 1.15), 0.38) }
        }

        // Glassy top light.
        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: 1
          anchors.leftMargin: 14
          anchors.rightMargin: 14
          height: 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Util.alpha(win.skin, 0.16) }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }

        Column {
          anchors.fill: parent
          anchors.margins: 24
          spacing: 18

          Text {
            text: win.weather ? ("WEATHER · " + String(win.weather.location || "").toUpperCase()) : "WEATHER"
            color: Util.alpha(win.skin, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.5
          }

          Row {
            width: parent.width
            spacing: 18

            Text {
              text: win.weather ? win.weather.icon : ""
              color: win.accent
              font.family: Style.font.family
              font.pixelSize: 72
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: 0

              Text {
                text: win.weather ? (win.weather.tempC + "°") : "—"
                color: win.skin
                font.family: Style.font.family
                font.pixelSize: 64
                font.bold: true
              }
              Text {
                text: win.weather ? win.weather.desc : "Loading…"
                color: Util.alpha(win.skin, 0.85)
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                elide: Text.ElideRight
                width: weatherWrap.width - 24 - 90 - 18 - 24
              }
              Text {
                text: win.weather ? ("Feels like " + win.weather.feelsC + "°") : ""
                color: Util.alpha(win.skin, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Row {
            width: parent.width
            spacing: 10

            Repeater {
              model: win.weather ? [
                { label: "Humidity", value: win.weather.humidity + "%" },
                { label: "Wind", value: win.weather.windKmph + " km/h" },
                { label: "Pressure", value: win.weather.pressure + " hPa" }
              ] : []

              Rectangle {
                required property var modelData
                width: (weatherWrap.width - 48 - 20) / 3
                height: 54
                radius: 4
                color: Util.alpha(Color.background, 0.22)
                border.width: 0

                Column {
                  anchors.centerIn: parent
                  spacing: 1
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.value
                    color: win.skin
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label
                    color: Util.alpha(win.skin, 0.55)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          Text {
            text: "NEXT DAYS"
            color: Util.alpha(win.skin, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.5
          }

          Row {
            width: parent.width
            spacing: 8

            Repeater {
              model: win.weather ? win.weather.days : []

              Rectangle {
                required property var modelData
                width: (weatherWrap.width - 48 - 24) / 4
                height: 116
                radius: 4
                color: Util.alpha(Color.background, 0.22)
                border.width: 0

                Column {
                  anchors.centerIn: parent
                  spacing: 3
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.name
                    color: Util.alpha(win.skin, 0.65)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.icon
                    color: win.accent
                    font.family: Style.font.family
                    font.pixelSize: 26
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.maxC + "°"
                    color: win.skin
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.minC + "°"
                    color: Util.alpha(win.skin, 0.5)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }

          Item { width: 1; height: 1 }
        }
      }
    }

    // ----------------------------------------------------------- news card
    Item {
      id: newsWrap
      width: content.width - weatherWrap.width - 24
      height: content.height

      RectangularShadow {
        anchors.fill: parent
        radius: 4
        blur: 34
        spread: 0
        offset: Qt.vector2d(0, 12)
        color: Util.alpha("#0b0908", 0.55)
      }

      BorderSurface {
        id: newsCard
        opacity: win.contentOpacity
        Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutCubic } }
        anchors.fill: parent
        radius: 4
        borderSpec: win.cardBorderSpec
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(Qt.lighter(Color.background, 1.16), 0.30) }
          GradientStop { position: 1.0; color: Util.alpha(Qt.darker(Color.background, 1.15), 0.38) }
        }

        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: 1
          anchors.leftMargin: 14
          anchors.rightMargin: 14
          height: 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Util.alpha(win.skin, 0.16) }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }

        Item {
          anchors.fill: parent
          anchors.margins: 24

          Item {
            id: newsHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 22

            Text {
              text: "NEWS"
              color: Util.alpha(win.skin, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.5
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: dash && dash.newsLoading ? "updating…" : (dash ? (dash.filteredNews.length + " stories") : "")
              color: Util.alpha(win.skin, 0.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          // Source filter tiles.
          Row {
            id: newsFilters
            anchors.top: newsHeader.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            height: 26
            spacing: 6

            Repeater {
              model: dash ? dash.filterTiles : []

              Rectangle {
                required property var modelData

                readonly property bool active: dash && (modelData === "All" ? dash.newsFilter === "" : dash.newsFilter === modelData)

                width: filterLabel.implicitWidth + 20
                height: 26
                radius: 4
                color: active
                  ? Util.alpha(win.accent, 0.22)
                  : (filterHover.hovered ? Util.alpha(win.skin, 0.10) : Util.alpha(Color.background, 0.35))
                border.width: 1
                border.color: active
                  ? Util.alpha(win.accent, 0.8)
                  : Util.alpha(win.skin, filterHover.hovered ? 0.28 : 0.14)

                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on border.color { ColorAnimation { duration: 140 } }

                Text {
                  id: filterLabel
                  anchors.centerIn: parent
                  text: modelData
                  color: active ? win.accent : Util.alpha(win.skin, 0.82)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: active
                }

                HoverHandler { id: filterHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: if (dash) dash.setNewsFilter(modelData) }
              }
            }
          }

          ListView {
            id: newsList
            anchors.top: newsFilters.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            spacing: 2
            model: dash ? dash.filteredNews : []
            boundsBehavior: Flickable.DragAndOvershootBounds
            flickDeceleration: 1000
            maximumFlickVelocity: 6000

            // Momentum settle timer. Pointer handlers are not Items and take no
            // children, so this lives beside the handler.
            Timer {
              id: settleTimer
              interval: 80
              repeat: false
              onTriggered: {
                if (Math.abs(newsWheel.contentVelocity) > 220)
                  newsList.flick(0, -newsWheel.contentVelocity)
                newsWheel.contentVelocity = 0
              }
            }

            // Touchpad scroll is scaled up and accelerates while a gesture
            // keeps going. When the gesture stops, the accumulated velocity is
            // handed to the Flickable so a quick flick coasts with momentum.
            WheelHandler {
              id: newsWheel
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

              property double lastTick: 0
              property real accel: 1
              // px/s in contentY terms (positive = content moving down).
              property real contentVelocity: 0

              onWheel: function(event) {
                var now = Date.now()
                var gap = newsWheel.lastTick > 0 ? (now - newsWheel.lastTick) : 9999
                var dt = newsWheel.lastTick > 0 ? Math.max(0.001, gap / 1000) : 0.016

                if (gap < 80) accel = Math.min(3.2, accel + 0.4)
                else if (gap > 160) accel = 1
                else accel = Math.max(1, accel - 0.5)

                var pixel = event.pixelDelta.y
                var dy = pixel !== 0 ? pixel : event.angleDelta.y / 2
                if (dy === 0) return

                // Touchpads report small per-event pixel deltas; mice report a
                // 120 step in angleDelta. Give the touchpad the bigger base.
                var base = pixel !== 0 ? 2.4 : 1.0
                var maxY = Math.max(0, newsList.contentHeight - newsList.height)
                var target = Math.max(0, Math.min(maxY, newsList.contentY - dy * base * accel))

                // A new scroll takes over from any in-flight momentum.
                if (newsList.flicking) newsList.cancelFlick()

                var applied = target - newsList.contentY
                newsList.contentY = target

                if (dt < 0.25) {
                  var instant = applied / dt
                  newsWheel.contentVelocity = newsWheel.contentVelocity * 0.55 + instant * 0.45
                } else {
                  newsWheel.contentVelocity = 0
                }
                newsWheel.lastTick = now
                settleTimer.restart()
                event.accepted = true
              }
            }

            delegate: Item {
              id: newsRow
              required property var modelData

              width: newsList.width
              height: newsBody.implicitHeight + 18

              HoverHandler { id: newsHover; cursorShape: Qt.PointingHandCursor }

              Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 4
                color: newsHover.hovered ? Util.alpha(win.skin, 0.10) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
              }

              Column {
                id: newsBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                Item {
                  width: parent.width
                  height: 18

                  Rectangle {
                    id: sourcePill
                    width: sourceLabel.implicitWidth + 14
                    height: 17
                    radius: 4
                    color: Util.alpha(win.accent, 0.20)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      id: sourceLabel
                      anchors.centerIn: parent
                      text: newsRow.modelData.source
                      color: win.accent
                      font.family: Style.font.family
                      font.pixelSize: 9
                      font.bold: true
                    }
                  }
                  Text {
                    anchors.left: sourcePill.right
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: dash ? dash.relativeTime(newsRow.modelData.timestamp) : ""
                    color: Util.alpha(win.skin, 0.45)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  width: parent.width
                  text: newsRow.modelData.title
                  color: newsHover.hovered ? win.accent : win.skin
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  Behavior on color { ColorAnimation { duration: 120 } }
                }
              }

              // A TapHandler (not a MouseArea) so drags and trackpad flicks
              // still reach the ListView instead of being swallowed.
              TapHandler {
                onTapped: {
                  if (!newsRow.modelData.link) return
                  Util.execDetached("omarchy-launch-browser " + Util.shellQuote(newsRow.modelData.link))
                }
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: newsList.count === 0
            text: dash && dash.newsLoading ? "Fetching the news…" : "No stories yet"
            color: Util.alpha(win.skin, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}
