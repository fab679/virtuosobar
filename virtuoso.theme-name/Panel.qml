import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "HearthModel.js" as HearthModel

// Virtuoso Hearth: a fanned card-deck browser for themes and wallpapers.
// 16:9 cards dealt into a hand — arrow through them, Enter (or click)
// applies live without closing, so themes can be tried on directly.
Panel {
  id: root
  moduleName: "virtuoso.theme-name"
  ipcTarget: "virtuoso.theme-name"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string mode: "themes"
  property var entries: []
  property int selectedIndex: 0
  property bool loading: false
  property string currentThemeName: ""
  property string currentWallpaper: ""
  property string home: Quickshell.env("HOME")

  // Fan geometry. Cards are 16:9; the hand overlaps them like held cards.
  readonly property int cardWidth: 208
  readonly property int cardHeight: 117
  readonly property int stepX: 116
  readonly property int maxVisible: 2
  readonly property real spreadDegrees: 5
  readonly property real focusScale: 1.16
  readonly property real focusLift: 16

  // Deal: 0 → 1 on every fresh hand. Navigation animates only once settled.
  property real dealProgress: 0
  readonly property bool dealSettled: dealProgress >= 0.999

  readonly property color contentForeground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property color contentAccent: Commons.Color.accent
  readonly property color contentMuted: Qt.rgba(contentForeground.r, contentForeground.g, contentForeground.b, 0.6)
  readonly property color contentSurface: Commons.Color.popups.background
  readonly property color contentOnSurface: Commons.Color.popups.text
  readonly property color scrimColor: {
    var c = contentSurface
    return Qt.rgba(c.r, c.g, c.b, 0.88)
  }
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function fileUrl(path) {
    return path ? "file://" + String(path) : ""
  }

  function setMode(next) {
    if (next !== "themes" && next !== "wallpapers") return
    if (mode === next) return
    mode = next
    refresh()
  }

  function refresh() {
    loading = true
    if (mode === "themes") {
      themeProc.running = false
      themeProc.running = true
    } else {
      bgProc.reload()
    }
  }

  function snapToCurrent() {
    if (entries.length === 0) {
      selectedIndex = 0
      return
    }
    selectedIndex = mode === "themes"
      ? HearthModel.indexOfTheme(entries, currentThemeName)
      : HearthModel.indexOfPath(entries, currentWallpaper)
  }

  function moveSelection(dx) {
    if (entries.length === 0) return
    selectedIndex = HearthModel.clampIndex(selectedIndex + dx, entries.length)
  }

  function applySelected() {
    var entry = entries[selectedIndex]
    if (!entry) return
    if (mode === "themes") {
      currentThemeName = entry.slug
      applyProc.command = ["omarchy-theme-set", entry.slug]
    } else {
      currentWallpaper = entry.path
      applyProc.command = ["omarchy-theme-bg-set", entry.path]
      bgRefreshDelay.restart()
    }
    applyProc.startDetached()
    root.close()
  }

  function isApplied(entry) {
    if (!entry) return false
    if (mode === "themes") return HearthModel.normalKey(entry.slug) === HearthModel.normalKey(currentThemeName)
    return String(entry.path || "") !== "" && String(entry.path) === String(currentWallpaper)
  }

  function startDeal() {
    dealProgress = 0
    Qt.callLater(function() { root.dealProgress = 1 })
  }

  Behavior on dealProgress {
    NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic }
  }

  onOpenedChanged: {
    if (opened) {
      currentBgProc.running = false
      currentBgProc.running = true
      refresh()
    }
  }

  onEntriesChanged: startDeal()
  onModeChanged: startDeal()

  FileView {
    id: themeNameFile
    path: root.home + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.currentThemeName = String(text()).trim()
    onLoadFailed: root.currentThemeName = ""
  }

  Process {
    id: themeProc
    command: ["omarchy-theme-switcher", "--print-rows"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.entries = HearthModel.parseThemeRows(text)
        root.loading = false
        root.snapToCurrent()
      }
    }
    onExited: root.loading = false
  }

  Process {
    id: bgProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.entries = HearthModel.parseWallpaperRows(text)
        root.loading = false
        root.snapToCurrent()
      }
    }
    onExited: root.loading = false
    function reload() {
      var themeDir = root.home + "/.local/state/omarchy/current/theme/backgrounds"
      var userDir = root.home + "/.config/omarchy/backgrounds/" + root.currentThemeName.trim()
      command = ["omarchy-menu-images", "--print-rows", themeDir, userDir]
      running = false
      running = true
    }
  }

  Process {
    id: currentBgProc
    command: ["readlink", "-f", root.home + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      onStreamFinished: root.currentWallpaper = String(text).trim()
    }
  }

  Timer {
    id: bgRefreshDelay
    interval: 1500
    onTriggered: {
      currentBgProc.running = false
      currentBgProc.running = true
    }
  }

  Process {
    id: applyProc
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(700))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: hearthColumn.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveSelection(dx)
      }
      onActivateRequested: root.applySelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.setMode("themes")
        else if (t === "w" || t === "W") root.setMode("wallpapers")
      }

      Column {
        id: hearthColumn
        width: parent.width
        spacing: Style.space(6)

        Item {
          width: parent.width
          height: Math.max(headerLabel.implicitHeight, modeTabs.implicitHeight)

          Text {
            id: headerLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: (root.mode === "themes" ? "THEMES" : "WALLPAPERS")
              + "  " + Math.min(root.selectedIndex + 1, root.entries.length)
              + " / " + root.entries.length
            color: root.contentMuted
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.Medium
            font.letterSpacing: 1
          }

          Row {
            id: modeTabs
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Repeater {
              model: [
                { value: "themes", label: "Themes" },
                { value: "wallpapers", label: "Wallpapers" }
              ]

              delegate: Item {
                required property var modelData
                readonly property bool selected: root.mode === modelData.value
                width: tabLabel.implicitWidth + Style.space(8)
                height: tabLabel.implicitHeight + Style.space(5)

                Text {
                  id: tabLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: parent.modelData.label
                  color: parent.selected ? root.contentAccent : root.contentMuted
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.weight: parent.selected ? Font.DemiBold : Font.Normal
                }

                Rectangle {
                  visible: parent.selected
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: 2
                  radius: 1
                  color: root.contentAccent
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setMode(parent.modelData.value)
                }
              }
            }
          }
        }

        Item {
          id: hand
          width: parent.width
          // Headroom for the lifted, scaled, rotated focused card so its
          // top edge (and neighbors' swung corners) never clip.
          height: root.cardHeight + root.focusLift + Style.space(40)
          clip: true

          Repeater {
            id: handRepeater
            model: root.entries

            delegate: Item {
              id: card
              required property int index
              required property var modelData
              readonly property int relative: index - root.selectedIndex
              readonly property bool focused: relative === 0
              readonly property bool nearby: Math.abs(relative) <= root.maxVisible
              readonly property real shade: focused ? 0
                : Math.min(0.55, 0.28 + Math.abs(relative) * 0.05)

              visible: nearby
              width: root.cardWidth
              height: root.cardHeight
              transformOrigin: Item.Bottom
              x: (hand.width - width) / 2 + relative * root.stepX * root.dealProgress
              y: hand.height - height - Style.space(4) - (focused ? root.focusLift * root.dealProgress : 0)
              z: focused ? 1000 : 500 - Math.abs(relative)
              rotation: relative * root.spreadDegrees * root.dealProgress
              scale: focused ? 1 + (root.focusScale - 1) * root.dealProgress : 1
              opacity: root.dealProgress

              Behavior on x {
                enabled: root.dealSettled
                NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
              }
              Behavior on y {
                enabled: root.dealSettled
                NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
              }
              Behavior on rotation {
                enabled: root.dealSettled
                NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
              }
              Behavior on scale {
                enabled: root.dealSettled
                NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
              }

              Rectangle {
                id: cardFrame
                anchors.fill: parent
                radius: Style.space(6)
                color: root.contentSurface
                border.width: card.focused ? 2 : 1
                border.color: card.focused ? root.contentAccent
                  : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18)

                Image {
                  anchors.fill: parent
                  anchors.margins: 5
                  source: card.nearby ? root.fileUrl(card.modelData.thumb) : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                }

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.margins: 5
                  height: Style.space(30)
                  gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: root.scrimColor }
                  }
                }

                Text {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.margins: Style.space(8)
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  maximumLineCount: 1
                  textFormat: Text.PlainText
                  text: String(card.modelData.label || "")
                  color: root.contentOnSurface
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.weight: Font.DemiBold
                }

                Rectangle {
                  anchors.fill: parent
                  anchors.margins: 5
                  color: root.contentSurface
                  opacity: card.shade
                  Behavior on opacity { NumberAnimation { duration: Style.duration(180) } }
                }

                Rectangle {
                  visible: root.isApplied(card.modelData)
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.margins: Style.space(8)
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: root.contentAccent
                  border.color: root.contentMuted
                  border.width: 1
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: card.focused
                  ? root.applySelected()
                  : root.selectedIndex = card.index
              }
            }
          }

          Text {
            visible: root.loading || root.entries.length === 0
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.loading ? "Loading…" : "Nothing here yet"
            color: root.contentMuted
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "← → browse · Enter apply + close · T themes · W wallpapers"
          color: root.contentMuted
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
