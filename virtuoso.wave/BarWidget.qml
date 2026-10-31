import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons as Commons
import qs.Ui

// Virtuoso Wave: spectrum bars plus transport controls. Bars stream from
// cava (raw ASCII to stdout); when cava is missing the bars stay hidden
// and the transport still works. Transport follows the first MPRIS player
// and hides with no player; clicking the bars drops down the full player
// panel (art, progress, seek, transport). Bars use the theme accent,
// controls the theme foreground — nothing hardcoded.
Panel {
  id: root
  moduleName: "virtuoso.wave"
  ipcTarget: "virtuoso.wave"

  readonly property int barCount: 12
  property var levels: []
  property bool cavaLive: false

  readonly property var player: {
    var vals = Mpris.players.values
    return vals && vals.length > 0 ? vals[0] : null
  }
  readonly property bool hasPlayer: player !== null
  readonly property bool playing: player !== null && player.isPlaying === true

  readonly property string trackTitle: player && player.metadata ? String(player.metadata["xesam:title"] || "") : ""
  readonly property string trackArtist: {
    if (!player || !player.metadata) return ""
    var artist = player.metadata["xesam:artist"]
    if (Array.isArray(artist)) artist = artist.join(", ")
    return String(artist || "")
  }
  readonly property string trackAlbum: player && player.metadata ? String(player.metadata["xesam:album"] || "") : ""
  readonly property string trackArtUrl: player && player.metadata ? String(player.metadata["mpris:artUrl"] || "") : ""

  readonly property string trackLabel: {
    if (trackTitle !== "" && trackArtist !== "") return trackArtist + " — " + trackTitle
    if (trackTitle !== "") return trackTitle
    if (trackArtist !== "") return trackArtist
    return player ? String(player.identity || "") : ""
  }

  // Length in seconds, from the player when it reports one, else from the
  // MPRIS metadata (microseconds). Position mirrors the same unit.
  readonly property real trackLength: {
    if (!player) return 0
    if (player.length) return Number(player.length)
    var micros = player.metadata ? Number(player.metadata["mpris:length"] || 0) : 0
    return micros > 0 ? micros / 1000000 : 0
  }
  readonly property bool canSeek: !!player && player.canSeek !== false && trackLength > 0
  readonly property bool hasProgress: trackLength > 0

  // Mirrored, not bound: Quickshell only refreshes MprisPlayer.position when
  // asked, so a timer drives it while the panel is open.
  property real livePosition: 0
  property bool seeking: false

  function fmtTime(seconds) {
    var s = Math.max(0, Math.floor(Number(seconds) || 0))
    return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
  }

  function syncPosition() {
    if (seeking) return
    livePosition = player ? Number(player.position || 0) : 0
  }

  function seekTo(seconds) {
    if (!canSeek || !player) return
    player.position = seconds
    // Guarded: restart() assigns running, which would snap the running
    // binding and leave the timer on forever after a seek while paused.
    if (positionTimer.running) positionTimer.restart()
  }

  onOpenedChanged: if (opened) syncPosition()
  onPlayerChanged: syncPosition()

  visible: root.hasPlayer || root.cavaLive
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  function cavaConfigPath() {
    return String(Qt.resolvedUrl("cava.config")).replace(/^file:\/\//, "")
  }

  function readFrame(line) {
    var cols = String(line || "").split(";")
    if (cols.length < 2) return
    var next = []
    for (var i = 0; i < root.barCount; i++) {
      var v = parseFloat(cols[i % cols.length])
      if (!isFinite(v)) v = 0
      next.push(Math.max(0, Math.min(1, v / 100)))
    }
    if (!root.cavaLive) root.cavaLive = true
    root.levels = next
  }

  function togglePlay() {
    if (root.player) root.player.togglePlaying()
  }

  Component.onCompleted: {
    cavaProc.running = true
    cavaWatchdog.restart()
  }

  Process {
    id: cavaProc
    command: ["cava", "-p", root.cavaConfigPath()]
    stdout: SplitParser {
      onRead: data => root.readFrame(data)
    }
    onExited: {
      root.levels = []
      root.cavaLive = false
    }
  }

  // No frames in 4s means cava is missing or broken: stop it and run
  // transport-only instead of respawning forever.
  Timer {
    id: cavaWatchdog
    interval: 4000
    onTriggered: {
      if (!root.cavaLive) cavaProc.running = false
    }
  }

  Timer {
    id: positionTimer
    interval: 1000
    repeat: true
    running: root.opened && root.hasPlayer && root.playing && root.hasProgress
    triggeredOnStart: true
    onTriggered: root.syncPosition()
  }

  RowLayout {
    id: row
    anchors.fill: parent
    spacing: Commons.Style.space(4)

    Row {
      id: transport
      Layout.alignment: Qt.AlignVCenter
      visible: root.hasPlayer
      spacing: 0

      WidgetButton {
        bar: root.bar
        visible: !root.player || root.player.canGoPrevious !== false
        text: "\udb81\udcae"
        tooltipText: "Previous"
        horizontalMargin: 2
        onPressed: function() { if (root.player) root.player.previous() }
      }

      WidgetButton {
        bar: root.bar
        visible: !root.player || root.player.canGoNext !== false
        text: "\udb81\udcad"
        tooltipText: "Next"
        horizontalMargin: 2
        onPressed: function() { if (root.player) root.player.next() }
      }
    }

    // Bars live in fixed-height cells with bottom-anchored fills: children
    // of a Row may not use anchors at all ("Row will not function"), so each
    // bar gets an Item cell it can anchor inside.
    Item {
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredWidth: barsRow.implicitWidth
      Layout.preferredHeight: 14
      visible: root.cavaLive

      Row {
        id: barsRow
        anchors.fill: parent
        spacing: 2

        Repeater {
          model: root.barCount

          Item {
            required property int index
            width: 3
            height: 14

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1 + (root.levels[index] || 0) * 13
              radius: 1.5
              color: Commons.Color.accent

              Behavior on height { NumberAnimation { duration: Commons.Style.duration(90) } }
            }
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: root.hasPlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.hasPlayer) root.toggle()
      }
    }
  }

  // Player dropdown, mirroring the media-panel structure: art hero, seekable
  // progress, transport. All anchors sit on Item children — nothing anchors
  // inside a Row or Column.
  readonly property color panelForeground: bar && bar.barForeground ? bar.barForeground : Commons.Color.foreground
  readonly property string panelFontFamily: bar && bar.fontFamily ? bar.fontFamily : Commons.Style.font.family

  function focusPlayer() {
    if (!player) return
    if (player.canRaise) {
      player.raise()
      root.close()
      return
    }
    var url = player.metadata ? String(player.metadata["xesam:url"] || "") : ""
    if (url !== "" && root.bar) {
      root.bar.run("xdg-open " + Commons.Util.shellQuote(url))
      root.close()
    }
  }

  KeyboardPanel {
    id: playerPanel
    anchorItem: row
    owner: root
    bar: root.bar
    open: root.opened && root.hasPlayer
    focusTarget: keyCatcher
    contentWidth: playerPanel.fittedContentWidth(Commons.Style.space(320))
    contentHeight: playerPanel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (!root.player) return
        if (dx > 0) root.player.next()
        else if (dx < 0) root.player.previous()
      }
      onActivateRequested: root.togglePlay()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Commons.Style.space(12)

        Item {
          width: parent.width
          height: Commons.Style.space(96)

          Rectangle {
            id: artTile
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height
            height: parent.height
            radius: Commons.Style.space(6)
            color: {
              var c = root.panelForeground
              return Qt.rgba(c.r, c.g, c.b, 0.08)
            }

            Image {
              id: art
              anchors.fill: parent
              anchors.margins: Commons.Style.space(2)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: true
              source: root.trackArtUrl
              visible: status === Image.Ready
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
            }

            Text {
              anchors.centerIn: parent
              visible: art.status !== Image.Ready
              textFormat: Text.PlainText
              text: "\u266a"
              color: {
                var c = root.panelForeground
                return Qt.rgba(c.r, c.g, c.b, 0.5)
              }
              font.pixelSize: Commons.Style.space(28)
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.player && (root.player.canRaise || root.trackArtUrl !== "") ? Qt.PointingHandCursor : Qt.ArrowCursor
              onClicked: root.focusPlayer()
            }
          }

          Column {
            anchors.left: artTile.right
            anchors.leftMargin: Commons.Style.space(12)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Commons.Style.space(3)

            Text {
              textFormat: Text.PlainText
              text: root.trackTitle !== "" ? root.trackTitle : root.trackLabel
              color: root.panelForeground
              font.family: root.panelFontFamily
              font.pixelSize: Commons.Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
              maximumLineCount: 2
              wrapMode: Text.WordWrap
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.trackArtist
              color: Qt.darker(root.panelForeground, 1.3)
              font.family: root.panelFontFamily
              font.pixelSize: Commons.Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }

            Text {
              textFormat: Text.PlainText
              text: root.trackAlbum
              color: Qt.darker(root.panelForeground, 1.6)
              font.family: root.panelFontFamily
              font.pixelSize: Commons.Style.font.caption
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }
          }
        }

        Column {
          width: parent.width
          spacing: Commons.Style.space(2)
          visible: root.hasProgress

          PanelSlider {
            id: seekBar
            width: parent.width
            bar: root.bar
            minimum: 0
            maximum: Math.max(1, root.trackLength)
            step: Math.max(1, root.trackLength / 200)
            value: root.livePosition
            fillColor: Commons.Color.accent
            enabled: root.canSeek

            onDraggingChanged: root.seeking = dragging
            onMoved: function(v) { root.livePosition = v }
            onReleased: function(v) { root.seekTo(v) }
          }

          Item {
            width: parent.width
            implicitHeight: elapsedLabel.implicitHeight

            Text {
              id: elapsedLabel
              anchors.left: parent.left
              textFormat: Text.PlainText
              text: root.fmtTime(root.livePosition)
              color: Qt.darker(root.panelForeground, 1.5)
              font.family: root.panelFontFamily
              font.pixelSize: Commons.Style.font.caption
            }

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.fmtTime(root.trackLength)
              color: Qt.darker(root.panelForeground, 1.5)
              font.family: root.panelFontFamily
              font.pixelSize: Commons.Style.font.caption
            }
          }
        }

        Item {
          width: parent.width
          implicitHeight: transportRow.implicitHeight

          Row {
            id: transportRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Commons.Style.space(4)

            Button {
              iconText: "\udb81\udcae"
              tooltipText: "Previous"
              foreground: root.panelForeground
              accent: Commons.Color.accent
              horizontalPadding: Commons.Style.spacing.controlPaddingX
              verticalPadding: Commons.Style.spacing.controlPaddingY
              enabled: !!root.player && root.player.canGoPrevious !== false
              opacity: enabled ? 1.0 : 0.4
              onClicked: if (root.player) root.player.previous()
            }

            Button {
              iconText: root.playing ? "\udb80\udfe4" : "\udb81\udc0a"
              tooltipText: root.playing ? "Pause" : "Play"
              foreground: root.panelForeground
              accent: Commons.Color.accent
              iconSize: Commons.Style.font.iconLarge
              horizontalPadding: Commons.Style.spacing.panelGap
              verticalPadding: Commons.Style.spacing.controlPaddingY
              onClicked: root.togglePlay()
            }

            Button {
              iconText: "\udb81\udcad"
              tooltipText: "Next"
              foreground: root.panelForeground
              accent: Commons.Color.accent
              horizontalPadding: Commons.Style.spacing.controlPaddingX
              verticalPadding: Commons.Style.spacing.controlPaddingY
              enabled: !!root.player && root.player.canGoNext !== false
              opacity: enabled ? 1.0 : 0.4
              onClicked: if (root.player) root.player.next()
            }
          }
        }
      }
    }
  }
}
