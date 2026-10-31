import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui

// Virtuoso Reactor: the battery as a small reactor core. A 270° charge ring
// (starting at 135°, gap at the bottom) around a core dot that breathes —
// slowly on battery, quickly on AC, and a sharper double-blink when the
// charge runs low. Reads /sys/class/power_supply/BAT0/uevent through a
// FileView, with a timer as a fallback refresh because battery sysfs does
// not always notify. No BAT0 on first load means no widget at all. The
// theme's accent and urgent colors, nothing hardcoded.
BarWidget {
  id: root
  moduleName: "virtuoso.reactor"

  // Per-entry settings, injected by property name: the charge percentage at
  // which the core starts blinking, and the sysfs fallback refresh period.
  readonly property int warnLevel: Math.max(0, Math.min(100, Math.round(Number(setting("warnLevel", 20)))))
  readonly property int pollIntervalMs: Math.max(5000, Math.round(Number(setting("pollIntervalMs", 30000))))

  // -1 until the uevent says otherwise.
  property int capacity: -1
  property string status: ""
  property bool present: false

  readonly property bool charging: root.status === "Charging"
  readonly property bool full: root.status === "Full"
  readonly property bool urgent: root.capacity >= 0 && !root.charging && !root.full && root.capacity <= root.warnLevel

  function readUevent(text) {
    var capacity = -1
    var status = ""
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var pair = lines[i].split("=")
      if (pair.length < 2) continue
      if (pair[0].trim() === "POWER_SUPPLY_CAPACITY") capacity = parseInt(pair[1], 10)
      else if (pair[0].trim() === "POWER_SUPPLY_STATUS") status = pair[1].trim()
    }
    if (isNaN(capacity) || capacity < 0 || capacity > 100) capacity = -1
    root.status = status
    root.capacity = capacity
    // One sighting is enough: a battery present at first load keeps the
    // widget alive even if sysfs hiccups on a later read.
    if (capacity >= 0) root.present = true
  }

  function statusLabel() {
    if (root.status === "Charging") return "charging"
    if (root.status === "Full") return "full"
    if (root.status === "Discharging" || root.status === "Not charging") return "discharging"
    return "idle"
  }

  visible: root.present && root.capacity >= 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Ring geometry, centered in the bar's thickness.
  readonly property real ringSize: Math.max(14, root.barSize - 6)
  readonly property real ringCenter: root.ringSize / 2
  readonly property real ringRadius: root.ringCenter - 1.5
  readonly property int strokeWidth: 2

  // The tiny percent label only fits on a horizontal bar of standard height;
  // vertical bars skip it and show just the core.
  readonly property bool showText: !root.vertical && root.barSize >= 24 && root.capacity >= 0

  readonly property color ringColor: root.urgent ? Commons.Color.bar.active : Commons.Color.accent
  readonly property color trackColor: {
    var c = Commons.Color.bar.text
    return Qt.rgba(c.r, c.g, c.b, 0.16)
  }

  // Angles in degrees, screen convention: 0° points right and positive runs
  // clockwise. The gauge starts at 135° and sweeps 270° clockwise, so its
  // gap sits at the bottom.
  readonly property real chargeSweep: root.capacity > 0 ? 270 * root.capacity / 100 : 0
  readonly property real leadStart: Math.min(135 + root.chargeSweep + 3, 404)
  readonly property real leadEnd: Math.min(root.leadStart + 22, 405)

  function arcX(angleDeg) {
    var rad = angleDeg * Math.PI / 180
    return root.ringCenter + root.ringRadius * Math.cos(rad)
  }

  function arcY(angleDeg) {
    var rad = angleDeg * Math.PI / 180
    return root.ringCenter + root.ringRadius * Math.sin(rad)
  }

  WidgetButton {
    id: button
    bar: root.bar
    fixedWidth: root.barSize
    fixedHeight: root.barSize
    hasVisualContent: true
    pressable: false
    tooltipText: root.capacity >= 0
      ? "Battery " + root.capacity + "% — " + root.statusLabel()
      : "Battery"

    Item {
      id: reactor
      anchors.centerIn: parent
      width: root.ringSize
      height: root.ringSize

      Shape {
        anchors.fill: parent
        antialiasing: true

        // Track: the full 270°, faint.
        ShapePath {
          fillColor: "transparent"
          strokeColor: root.trackColor
          strokeWidth: root.strokeWidth
          capStyle: ShapePath.Round

          PathMove { x: root.arcX(135); y: root.arcY(135) }
          PathArc { radiusX: root.ringRadius; radiusY: root.ringRadius; x: root.arcX(315); y: root.arcY(315) }
          PathArc { radiusX: root.ringRadius; radiusY: root.ringRadius; x: root.arcX(405); y: root.arcY(405) }
        }

        // Charge arc: the sweep follows the capacity, split into two arcs
        // because no single PathArc may pass its own halfway point.
        ShapePath {
          fillColor: "transparent"
          strokeColor: root.chargeSweep > 0 ? root.ringColor : "transparent"
          strokeWidth: root.strokeWidth
          capStyle: ShapePath.Round

          PathMove { x: root.arcX(135); y: root.arcY(135) }
          PathArc { radiusX: root.ringRadius; radiusY: root.ringRadius; x: root.arcX(135 + root.chargeSweep / 2); y: root.arcY(135 + root.chargeSweep / 2) }
          PathArc { radiusX: root.ringRadius; radiusY: root.ringRadius; x: root.arcX(135 + root.chargeSweep); y: root.arcY(135 + root.chargeSweep) }
        }

        // While charging, a faint arc rides just ahead of the charge arc,
        // like a leading edge reaching into the track's empty part.
        ShapePath {
          fillColor: "transparent"
          strokeColor: root.charging && root.chargeSweep > 0
            ? Qt.rgba(root.ringColor.r, root.ringColor.g, root.ringColor.b, 0.3)
            : "transparent"
          strokeWidth: root.strokeWidth
          capStyle: ShapePath.Round

          PathMove { x: root.arcX(root.leadStart); y: root.arcY(root.leadStart) }
          PathArc { radiusX: root.ringRadius; radiusY: root.ringRadius; x: root.arcX(root.leadEnd); y: root.arcY(root.leadEnd) }
        }
      }

      // The core: a dot whose breath drives its opacity and size. Slow
      // breathing on battery, a quicker one on AC, and a sharper
      // double-blink when the charge runs low — all stilled when reduced
      // motion is on. Two phases, breath and blink, so no animation ever
      // writes a property another one is watching.
      Rectangle {
        id: core
        property real breath: 1
        property real blink: 1

        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.showText ? -Math.round(root.ringSize * 0.16) : 0
        width: root.showText ? Math.max(3, Math.round(root.ringSize * 0.2)) : Math.max(5, Math.round(root.ringSize * 0.34))
        height: width
        radius: width / 2
        color: root.ringColor
        opacity: root.urgent ? blink : 0.45 + 0.45 * breath
        scale: root.urgent ? 1 : 0.86 + 0.14 * breath

        SequentialAnimation {
          id: idlePulse
          running: !Commons.Style.reduceMotion && !root.charging && !root.urgent
          loops: Animation.Infinite

          NumberAnimation { target: core; property: "breath"; from: 1; to: 0; duration: 1600; easing.type: Easing.InOutSine }
          NumberAnimation { target: core; property: "breath"; from: 0; to: 1; duration: 1600; easing.type: Easing.InOutSine }

          onStopped: core.breath = 1
        }

        SequentialAnimation {
          id: chargePulse
          running: !Commons.Style.reduceMotion && root.charging && !root.urgent
          loops: Animation.Infinite

          NumberAnimation { target: core; property: "breath"; from: 1; to: 0; duration: 600; easing.type: Easing.InOutSine }
          NumberAnimation { target: core; property: "breath"; from: 0; to: 1; duration: 600; easing.type: Easing.InOutSine }

          onStopped: core.breath = 1
        }

        SequentialAnimation {
          id: urgentBlink
          running: !Commons.Style.reduceMotion && root.urgent
          loops: Animation.Infinite

          NumberAnimation { target: core; property: "blink"; from: 1; to: 0.15; duration: 130; easing.type: Easing.InQuad }
          NumberAnimation { target: core; property: "blink"; from: 0.15; to: 1; duration: 130; easing.type: Easing.OutQuad }
          NumberAnimation { target: core; property: "blink"; from: 1; to: 0.15; duration: 130; easing.type: Easing.InQuad }
          NumberAnimation { target: core; property: "blink"; from: 0.15; to: 1; duration: 130; easing.type: Easing.OutQuad }
          PauseAnimation { duration: 620 }

          onStopped: core.blink = 1
        }
      }

      // Tiny percentage inside the ring, when the bar has room for it.
      Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.round(root.ringSize * 0.17)
        visible: root.showText
        textFormat: Text.PlainText
        text: String(root.capacity)
        color: {
          var c = Commons.Color.bar.text
          return Qt.rgba(c.r, c.g, c.b, 0.85)
        }
        font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Commons.Style.font.family
        font.pixelSize: Math.max(6, Math.round(Commons.Style.font.caption * 0.7))
        renderType: Text.NativeRendering
      }
    }
  }

  FileView {
    id: batteryFile
    path: "/sys/class/power_supply/BAT0/uevent"
    watchChanges: true
    printErrors: false
    onLoaded: root.readUevent(text())
    onLoadFailed: root.readUevent("")
    onFileChanged: reload()
  }

  // Fallback refresh: battery sysfs does not always notify, so poll anyway.
  Timer {
    interval: root.pollIntervalMs
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: batteryFile.reload()
  }
}