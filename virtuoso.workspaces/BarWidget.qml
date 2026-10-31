import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "virtuoso.workspaces"

  // Every monitor has workspaces 1-10 of its own, which Hyprland numbers in a
  // block of ten per monitor: 1-10, 11-20, and so on (see
  // default/hypr/monitor-workspaces.lua). Each bar shows its own monitor's block,
  // numbered 1-10, and the one that monitor shows, whichever monitor has focus.
  readonly property int slots: 10

  // Pill look, from the entry's settings ("pillStyle"): digits keeps the
  // shipped number-with-underglow row; the others borrow Shibumi's
  // presentations — numbers (chips), halo (pill and marker), kanji (一..十),
  // rings (numbered circles), aurora (stretching bars) and pacman (a hungry
  // traveller that runs to the workspace it is sent to).
  readonly property var kanjiDigits: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
  readonly property string pillStyle: {
    var styles = ["digits", "numbers", "halo", "kanji", "rings", "aurora", "pacman"]
    var wanted = typeof settings === "object" && settings !== null ? String(settings.pillStyle || "") : ""
    return styles.indexOf(wanted) >= 0 ? wanted : "digits"
  }
  readonly property bool textualPill: root.pillStyle === "digits" || root.pillStyle === "kanji"
  readonly property int pillWidth: root.pillStyle === "aurora" ? 38
    : root.pillStyle === "pacman" ? 24 : 20

  // The direction the active slot last moved along the row, for the ion trail
  // the underglow throws when a switch lands.
  property int trailDirection: 0
  property int lastActiveId: -1

  // Bumped whenever Hyprland's outputs re-register, so the monitor binding
  // below re-resolves. Without this a bar spawned mid-registration pins the
  // wrong monitor forever, and every click lands on the wrong screen.
  property int monitorEpoch: 0

  readonly property var monitor: {
    root.monitorEpoch
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  // Connector -> block, from the file Hyprland keeps them in.
  property var blocks: ({})

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  function blockOf(id) {
    return Math.floor((id - 1) / root.slots)
  }

  function slotOf(id) {
    return (id - 1) % root.slots + 1
  }

  function activeWorkspaceId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  // Until Hyprland has written the file, the workspace a monitor shows is in
  // its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    var active = root.activeWorkspaceId()
    return active > 0 ? root.blockOf(active) : 0
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // The first five of the monitor's own, and any of the rest that exist. After
  // them come workspaces that are only visiting: those of a monitor that is
  // unplugged, which had no room to join this one's.
  function workspaceIds() {
    var base = root.block * root.slots
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  function focusWorkspace(id) {
    if (root.blockOf(id) === root.block) {
      root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")")
    } else {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
  }

  // A wheel notch moves one entry along the row, and a touchpad adds up its
  // smaller deltas until they make a notch's worth.
  property real wheelAccumulator: 0

  function scrollWorkspaces(delta) {
    var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
    root.wheelAccumulator = wheel.remainder
    if (wheel.steps === 0) return

    // Holds at either end rather than wrapping, so a touchpad swipe that runs
    // long stops on the last workspace.
    var ids = root.workspaceIds()
    var index = ids.indexOf(root.activeWorkspaceId())
    if (index === -1) return
    var target = ids[Util.clamp(index - wheel.steps, 0, ids.length - 1)]
    if (target !== ids[index]) root.focusWorkspace(target)
  }

  // The workspace each monitor shows carries its layout: a square tiles, a
  // circle scrolls, and a triangle floats. Clicking it cycles to the next one,
  // as Super + L does.
  property string activeMode: "dwindle"
  property bool modeStale: false

  // The pacman's run from the slot it left to the one it landed on, in grid
  // coordinates. The runner is a child of the grid, drawn over the row.
  property bool pacmanTraveling: false
  property int pacmanTargetId: -1
  property real pacmanFromX: 0
  property real pacmanToX: 0
  property real pacmanProgress: 0
  property real pacmanDirection: 1

  function pacmanSlotX(id) {
    var index = root.workspaceIds().indexOf(id)
    var cell = cellRepeater.itemAt(index)
    if (!cell) return -1
    var point = cell.mapToItem(grid, 0, 0)
    return point.x + cell.width / 2
  }

  function beginPacmanTravel(previousId, nextId) {
    if (root.pillStyle !== "pacman" || previousId < 1 || nextId < 1 || previousId === nextId) return
    if (Style.reduceMotion) return
    var from = root.pacmanSlotX(previousId)
    var to = root.pacmanSlotX(nextId)
    if (from < 0 || to < 0) return
    root.pacmanFromX = from
    root.pacmanToX = to
    root.pacmanTargetId = nextId
    root.pacmanDirection = to >= from ? 1 : -1
    root.pacmanProgress = 0
    root.pacmanTraveling = true
  }

  // The shown workspace carries its layout as a drawn mark, not a font
  // glyph: a tile grid for dwindle, a ring for scrolling, a triangle for
  // floating. Rendered below in the modeIcon item, in the theme accent.

  // A layout only changes through the layout commands, which ask for a refresh,
  // or a config reload, so each workspace's mode is read once and cached rather
  // than running the script on every workspace switch.
  property var modeCache: ({})
  property int modeGeneration: 0
  property int modeProcWorkspace: -1
  property int modeProcGeneration: 0

  function showActiveMode() {
    var mode = root.modeCache[root.activeWorkspaceId()]
    if (mode !== undefined) root.activeMode = mode
    else readMode()
  }

  function readMode() {
    if (modeProc.running) {
      root.modeStale = true
      return
    }
    var id = root.activeWorkspaceId()
    if (id === -1) return
    root.modeProcWorkspace = id
    root.modeProcGeneration = root.modeGeneration
    modeProc.command = ["omarchy-hyprland-workspace-layout-current", String(id)]
    modeProc.running = true
  }

  function refresh() {
    root.modeCache = ({})
    root.modeGeneration++
    readMode()
  }

  // The layout commands act on the focused workspace, so a click on another
  // monitor's bar focuses that monitor first.
  Timer {
    id: cycleReread
    interval: 400
    onTriggered: root.readMode()
  }

  function cycleLayout() {
    if (!root.bar) return
    var command = "omarchy-hyprland-workspace-layout-toggle"
    if (root.monitor && !root.monitor.focused) {
      command = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ monitor = \"" + root.monitorName + "\" })") + " >/dev/null && " + command
    }
    root.bar.run(command)
    // The toggle applies async; re-read after it lands so the icon follows
    // even if the refresh broadcast arrives before Hyprland settles.
    cycleReread.restart()
  }

  Component.onCompleted: refresh()
  onMonitorChanged: root.showActiveMode()

  Connections {
    target: root.monitor
    function onActiveWorkspaceChanged() {
      var next = root.activeWorkspaceId()
      // The trail throws toward where the row moved; the pacman runs the same
      // way, from the slot it left to the one it landed on.
      if (root.lastActiveId > 0 && next > 0) {
        root.trailDirection = next > root.lastActiveId ? 1 : next < root.lastActiveId ? -1 : 0
        root.beginPacmanTravel(root.lastActiveId, next)
      }
      root.lastActiveId = next
      root.showActiveMode()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "configreloaded") {
        root.refresh()
        root.monitorEpoch++
      }
      if (name.indexOf("monitor") === 0) root.monitorEpoch++
      // Quickshell credits every workspace switch to the focused monitor, as
      // the event doesn't say which one switched, and misses the workspace a
      // monitor falls back to when its own is moved away. Moving workspaces
      // between monitors switches the others, so ask Hyprland for the truth.
      // A workspace that changes number is only learned by asking too. Every
      // bar shares what Hyprland answers, so one asks after a plain switch.
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  Process {
    id: modeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var mode = text.trim()
        // A read that started before a refresh may predate the change.
        if (!mode || root.modeProcGeneration !== root.modeGeneration) return
        root.modeCache[root.modeProcWorkspace] = mode
        if (root.modeProcWorkspace === root.activeWorkspaceId()) root.activeMode = mode
      }
    }
    onExited: {
      if (!root.modeStale) return
      root.modeStale = false
      // Deferred: the process still reports running while it signals exit.
      Qt.callLater(root.showActiveMode)
    }
  }

  // Super + L and the default layout change the mode without a focus change,
  // so they ask every bar to read it again.
  ShellIpc {
    target: "virtuoso.workspaces"

    function refresh(): void { root.broadcast("refresh") }
  }

  ShellIpc {
    // Stock target: the layout toggle broadcasts refresh to omarchy.workspaces,
    // which this widget replaced. Without squatting it, mode icons go stale on
    // every Super+L. Removed automatically with the widget on uninstall.
    target: "omarchy.workspaces"

    function refresh(): void { root.broadcast("refresh") }
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      id: cellRepeater
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
        readonly property int slot: root.slotOf(modelData)
        readonly property bool firstGuest: root.blockOf(modelData) !== root.block && index > 0 && root.blockOf(root.workspaceIds()[index - 1]) === root.block
        required property int index

        readonly property string slotLabel: slot === root.slots ? "0" : String(slot)

        // A switch landing on this slot throws the ion trail from its
        // underglow, toward where the row came from.
        onShownChanged: if (shown && root.trailDirection !== 0
          && !root.vertical && !Style.reduceMotion) trailAnim.restart()

        // A gap sets visiting workspaces apart from the monitor's own.
        Layout.leftMargin: firstGuest && !root.vertical ? Style.space(6) : 0
        Layout.topMargin: firstGuest && root.vertical ? Style.space(6) : 0

        bar: root.bar
        text: root.textualPill && !shown ? (root.pillStyle === "kanji" ? root.kanjiDigits[slot - 1] : slotLabel) : ""
        labelVisible: root.textualPill && !shown
        hasVisualContent: true
        fontSize: root.pillStyle === "kanji" ? Style.font.body * 0.86 : Style.font.body
        tooltipText: shown ? ("Layout: " + root.activeMode + " — click to cycle")
          : ("Go to workspace " + slot)
        opacity: occupied || shown ? 1 : 0.5
        active: shown
        // Stock paints active in urgent red; the shown workspace follows the
        // theme accent instead, matching the underglow below.
        activeColor: Commons.Color.accent
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(root.pillWidth)
        fixedHeight: root.barSize
        onPressed: function() {
          if (shown) root.cycleLayout()
          else root.focusWorkspace(modelData)
        }
        onWheelMoved: function(delta) { root.scrollWorkspaces(delta) }

        // ---- Numbers: a rounded chip carrying the slot number.
        Item {
          id: chipItem
          visible: root.pillStyle === "numbers" && !shown
          anchors.centerIn: parent
          width: Style.space(20)
          height: Style.space(20)

          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g,
              Commons.Color.accent.b, shown ? 0.3 : occupied ? 0.12 : 0.05)
            border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g,
              Commons.Color.accent.b, shown ? 0.55 : 0.14)
            border.width: 1
          }

          Text {
            anchors.centerIn: parent
            text: slotLabel
            color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g,
              Commons.Color.accent.b, shown ? 1 : occupied ? 0.75 : 0.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body * 0.8
            renderType: Text.NativeRendering
          }
        }

        // ---- Halo: a soft pill behind a small center marker.
        Item {
          id: haloItem
          visible: root.pillStyle === "halo"
          anchors.centerIn: parent
          width: Style.space(shown ? 32 : 18)
          height: Style.space(16)

          Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

          Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            radius: height / 2
            color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g,
              Commons.Color.accent.b, shown ? 0.22 : occupied ? 0.14 : 0.06)
          }

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(shown ? 10 : occupied ? 6 : 4)
            height: Style.space(8)
            radius: height / 2
            color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g,
              Commons.Color.accent.b, shown ? 1 : occupied ? 0.7 : 0.25)

            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          }
        }

        // ---- Rings: a circle with the slot number inside.
        Item {
          id: ringsItem
          visible: root.pillStyle === "rings" && !shown
          anchors.centerIn: parent
          width: Style.space(20)
          height: Style.space(20)

          Text {
            anchors.centerIn: parent
            text: slotLabel
            color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g,
              Commons.Color.accent.b, occupied ? 0.85 : 0.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body * 0.8
            renderType: Text.NativeRendering
            z: 1
          }

          Shape {
            anchors.fill: parent
            asynchronous: false

            ShapePath {
              fillColor: "transparent"
              strokeColor: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g,
                Commons.Color.accent.b, occupied ? 0.8 : 0.35)
              strokeWidth: 1.5

              PathAngleArc {
                centerX: ringsItem.width / 2
                centerY: ringsItem.height / 2
                radiusX: ringsItem.width / 2 - 1
                radiusY: radiusX
                startAngle: 0
                sweepAngle: 360
              }
            }
          }
        }

        // ---- Aurora: a bar that stretches wide over the shown slot.
        Item {
          id: auroraItem
          visible: root.pillStyle === "aurora"
          anchors.centerIn: parent
          width: Style.space(shown ? 34 : 12)
          height: Style.space(16)

          Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(shown ? 28 : occupied ? 6 : 4)
            height: Style.space(shown ? 3 : occupied ? 6 : 4)
            radius: height / 2
            opacity: shown ? 0.92 : occupied ? 0.62 : 0.18
            color: Commons.Color.accent
            antialiasing: true

            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          }
        }

        // ---- Pacman: the marker glyph sits in the row; the runner below
        // carries the eating travel between slots.
        Text {
          visible: root.pillStyle === "pacman" && !(root.pacmanTraveling && root.pacmanTargetId === modelData)
          anchors.centerIn: parent
          text: "󰮯"
          color: shown ? Commons.Color.accent
            : Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g,
              Commons.Color.accent.b, occupied ? 0.62 : 0.26)
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: Style.space(13)
          renderType: Text.NativeRendering
        }

        // Layout mark for the shown workspace: drawn shapes in the theme
        // accent, one silhouette per layout — tile grid, ring, triangle.
        // Shown in every style; in pacman it rides small under the glyph,
        // which already carries the accent.
        Item {
          id: modeIcon
          visible: shown
          anchors.centerIn: parent
          anchors.verticalCenterOffset: root.pillStyle === "pacman" ? Style.space(5) : 0
          scale: root.pillStyle === "pacman" ? 0.5 : 1
          width: 14
          height: 14

          // Dwindle: four tiles with hairline gaps.
          Item {
            anchors.fill: parent
            visible: root.activeMode !== "scrolling" && root.activeMode !== "floating"

            Repeater {
              model: 4

              Rectangle {
                required property int index
                x: (index % 2) * 8
                y: Math.floor(index / 2) * 8
                width: 6
                height: 6
                radius: 1.5
                color: Commons.Color.accent
              }
            }
          }

          // Scrolling: a ring.
          Shape {
            anchors.fill: parent
            visible: root.activeMode === "scrolling"

            ShapePath {
              fillColor: "transparent"
              strokeColor: Commons.Color.accent
              strokeWidth: 2
              PathMove { x: 12; y: 7 }
              PathArc { radiusX: 5; radiusY: 5; x: 2; y: 7 }
              PathArc { radiusX: 5; radiusY: 5; x: 12; y: 7 }
            }
          }

          // Floating: a filled triangle, point up.
          Shape {
            anchors.fill: parent
            visible: root.activeMode === "floating"

            ShapePath {
              fillColor: Commons.Color.accent
              strokeColor: "transparent"
              PathMove { x: 7; y: 1.5 }
              PathLine { x: 12.5; y: 12 }
              PathLine { x: 1.5; y: 12 }
              PathLine { x: 7; y: 1.5 }
            }
          }
        }

        // Neon underglow on the shown workspace, in the digits look. A switch
        // throws an ion trail: the glow stretches out of the trailing edge and
        // snaps back. Stilled when reduced motion is on.
        Rectangle {
          id: underglow
          visible: shown && root.pillStyle === "digits"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 2
          width: 16
          height: 3
          radius: 1.5
          color: Commons.Color.accent

          transform: Scale {
            id: trailScale
            origin.x: root.trailDirection >= 0 ? underglow.width : 0
            xScale: 1
          }

          SequentialAnimation {
            id: trailAnim
            NumberAnimation { target: trailScale; property: "xScale"; from: 2.4; to: 1; duration: 460; easing.type: Easing.OutCubic }
          }

          SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: shown && !Style.reduceMotion
            NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
          }
        }
      }
    }
  }

  // The pacman's run along the row, drawn over it. A sibling of the grid so
  // the layout leaves it alone; it shares the grid's coordinates.
  Item {
    id: pacmanRunner
    visible: root.pacmanTraveling && root.pillStyle === "pacman"
    z: 4
    anchors.fill: parent
    x: root.pacmanFromX + (root.pacmanToX - root.pacmanFromX) * root.pacmanProgress - Style.space(11)
    y: (grid.height - Style.space(16)) / 2
    width: Style.space(22)
    height: Style.space(16)

    transform: Scale {
      origin.x: pacmanRunner.width / 2
      origin.y: pacmanRunner.height / 2
      xScale: root.pacmanDirection
    }

    Text {
      anchors.centerIn: parent
      text: "󰮯"
      color: Commons.Color.accent
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: Style.space(13)
      renderType: Text.NativeRendering
    }

    SequentialAnimation {
      running: root.pacmanTraveling && !Style.reduceMotion
      NumberAnimation { target: root; property: "pacmanProgress"; from: 0; to: 1; duration: 380; easing.type: Easing.InOutQuad }
      onFinished: root.pacmanTraveling = false
    }
  }
}


