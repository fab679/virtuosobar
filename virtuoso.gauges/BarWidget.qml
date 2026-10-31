import QtQuick
import QtQuick.Shapes
import QtQml.Models
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui

// Virtuoso Gauges: compact HUD ring gauges for CPU, memory and temperature.
// Every value comes from /proc or /sys through FileViews — no external
// processes. Each gauge is a 270° arc (opening at the bottom) in the theme
// accent over a faint track of the bar's text color, with the reading in
// the ring's center. Gauges can be shown, hidden, and retimed through the
// widget's per-entry settings.
BarWidget {
  id: root
  moduleName: "virtuoso.gauges"

  // Settings, read from the injected per-entry object the way lxp.vitals
  // reads its own: a missing or null value keeps the default.
  readonly property bool showCpu: root.setting("showCpu", true) !== false
  readonly property bool showMem: root.setting("showMem", true) !== false
  readonly property bool showTemp: root.setting("showTemp", true) !== false
  readonly property int pollIntervalMs: {
    var n = Number(root.setting("pollIntervalMs", 2000))
    return isFinite(n) && n >= 500 ? Math.round(n) : 2000
  }

  // ---------------------------------------------------------- CPU: /proc/stat

  property real cpuPercent: 0
  property bool cpuPrimed: false
  property real lastCpuIdle: 0
  property real lastCpuTotal: 0

  // Busy share is the delta of non-idle jiffies over the delta of all
  // jiffies between two polls. The first sample only primes the totals,
  // so the gauge starts at 0 rather than guessing.
  function readCpuStat(raw) {
    var fields = String(raw || "").split("\n")[0].split(/\s+/)
    if (fields.length < 5 || fields[0] !== "cpu") return

    var total = 0
    for (var i = 1; i < fields.length; i++) {
      var n = Number(fields[i])
      if (isFinite(n)) total += n
    }
    // Idle plus iowait both count as not-busy; short lines simply add 0.
    var idle = (Number(fields[4]) || 0) + (Number(fields[5]) || 0)

    if (!root.cpuPrimed) {
      root.lastCpuIdle = idle
      root.lastCpuTotal = total
      root.cpuPrimed = true
      return
    }

    var dTotal = total - root.lastCpuTotal
    var dIdle = idle - root.lastCpuIdle
    root.lastCpuIdle = idle
    root.lastCpuTotal = total
    if (dTotal > 0) {
      root.cpuPercent = Math.max(0, Math.min(100, (dTotal - dIdle) / dTotal * 100))
    }
  }

  // ---------------------------------------------------------- RAM: /proc/meminfo

  property real memTotalKb: 0
  property real memAvailableKb: 0

  readonly property real memPercent: root.memTotalKb > 0
    ? Math.max(0, Math.min(100, (root.memTotalKb - root.memAvailableKb) / root.memTotalKb * 100)) : 0

  function readMemInfo(raw) {
    var total = 0
    var available = 0
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^(MemTotal|MemAvailable):\s+(\d+)/)
      if (!match) continue
      if (match[1] === "MemTotal") total = Number(match[2])
      else available = Number(match[2])
    }
    // Keep the last good pair rather than blanking on a partial read.
    if (total > 0) {
      root.memTotalKb = total
      root.memAvailableKb = available
    }
  }

  // ---------------------------------------------------------- TEMP: thermal zones

  // Zones are probed 0-9; most machines have far fewer. Temps and type
  // names are kept per index, replaced wholesale so bindings re-evaluate.
  readonly property int zoneCount: 10
  property var zoneTemps: []
  property var zoneTypes: []

  // Prefer a zone whose type names the CPU package; otherwise the first
  // zone that actually reads. No readable zone means no temp gauge.
  readonly property int tempZoneIndex: {
    var fallback = -1
    for (var i = 0; i < root.zoneCount; i++) {
      if (root.zoneTemps[i] === undefined) continue
      if (fallback === -1) fallback = i
      var type = String(root.zoneTypes[i] || "").toLowerCase()
      if (type.indexOf("x86_pkg_temp") !== -1 || type.indexOf("cpu") !== -1) return i
    }
    return fallback
  }

  readonly property bool tempAvailable: root.tempZoneIndex >= 0
  readonly property real tempCelsius: root.tempAvailable && root.zoneTemps[root.tempZoneIndex] !== undefined
    ? root.zoneTemps[root.tempZoneIndex] : 0
  readonly property real tempPercent: Math.max(0, Math.min(100, root.tempCelsius))

  function recordZoneTemp(zone, raw) {
    var celsius = Number(String(raw || "").trim())
    var next = root.zoneTemps.slice()
    if (isFinite(celsius)) next[zone] = celsius / 1000
    else delete next[zone]
    root.zoneTemps = next
  }

  function recordZoneType(zone, raw) {
    var next = root.zoneTypes.slice()
    next[zone] = String(raw || "").trim()
    root.zoneTypes = next
  }

  function dropZoneTemp(zone) {
    var next = root.zoneTemps.slice()
    delete next[zone]
    root.zoneTemps = next
  }

  function dropZoneType(zone) {
    var next = root.zoneTypes.slice()
    delete next[zone]
    root.zoneTypes = next
  }

  function reloadZones() {
    for (var i = 0; i < root.zoneCount; i++) {
      var view = tempViews.objectAt(i)
      if (view) view.reload()
    }
  }

  // Millidegrees and type names, one FileView per zone. Zones that don't
  // exist fail quietly and stay absent from the dictionaries above.
  Instantiator {
    id: tempViews
    model: root.zoneCount

    delegate: FileView {
      required property int index
      readonly property int zone: index

      path: "/sys/class/thermal/thermal_zone" + zone + "/temp"
      watchChanges: false
      printErrors: false
      onLoaded: root.recordZoneTemp(zone, text())
      onLoadFailed: root.dropZoneTemp(zone)
    }
  }

  Instantiator {
    id: typeViews
    model: root.zoneCount

    delegate: FileView {
      required property int index
      readonly property int zone: index

      path: "/sys/class/thermal/thermal_zone" + zone + "/type"
      watchChanges: false
      printErrors: false
      onLoaded: root.recordZoneType(zone, text())
      onLoadFailed: root.dropZoneType(zone)
    }
  }

  // ---------------------------------------------------------- polling

  FileView {
    id: statFile
    path: "/proc/stat"
    watchChanges: false
    printErrors: false
    onLoaded: root.readCpuStat(text())
  }

  FileView {
    id: meminfoFile
    path: "/proc/meminfo"
    watchChanges: false
    printErrors: false
    onLoaded: root.readMemInfo(text())
  }

  Timer {
    interval: root.pollIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true

    onTriggered: {
      statFile.reload()
      meminfoFile.reload()
      root.reloadZones()
    }
  }

  // ---------------------------------------------------------- summary

  readonly property string tooltipSummary: {
    var parts = []
    if (root.showCpu) parts.push("CPU " + Math.round(root.cpuPercent) + "%")
    if (root.showMem) parts.push("RAM " + Math.round(root.memPercent) + "%")
    if (root.showTemp && root.tempAvailable) parts.push(Math.round(root.tempCelsius) + "\u00B0C")
    return parts.join(" \u00B7 ")
  }

  // ---------------------------------------------------------- gauge geometry

  readonly property real gaugeSize: Math.max(14, Math.round(root.barSize * 0.6))
  readonly property real gaugeGap: Commons.Style.space(2)
  readonly property real gaugeStride: root.gaugeSize + root.gaugeGap
  readonly property real strokeWidth: Math.max(1.5, root.gaugeSize * 0.125)
  readonly property real ringRadius: (root.gaugeSize - root.strokeWidth) / 2 - 0.5
  readonly property real numberFont: Math.max(6, Math.round(root.gaugeSize * 0.34))
  readonly property real unitFont: Math.max(4, Math.round(root.gaugeSize * 0.22))

  // Nothing hardcoded: faint track and labels tint the bar's text color,
  // the value arc carries the accent.
  readonly property color trackColor: Commons.Util.alpha(Commons.Color.bar.text, 0.16)
  readonly property color labelColor: Commons.Color.bar.text
  readonly property color unitColor: Commons.Util.alpha(Commons.Color.bar.text, 0.65)
  readonly property color arcColor: Commons.Util.alpha(Commons.Color.accent, 0.9)
  readonly property string fontFamily: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Commons.Style.font.family

  readonly property var visibleGauges: [cpuGauge, memGauge, tempGauge].filter(function(gauge) {
    return gauge.visible
  })

  function slot(gauge) {
    return root.visibleGauges.indexOf(gauge)
  }

  visible: root.visibleGauges.length > 0
  // Horizontal: gauges across, full bar thickness. Vertical: stacked
  // within the bar's width instead.
  implicitWidth: root.vertical
    ? root.barSize
    : root.visibleGauges.length * root.gaugeSize + Math.max(0, root.visibleGauges.length - 1) * root.gaugeGap
  implicitHeight: root.vertical
    ? root.visibleGauges.length * root.gaugeSize + Math.max(0, root.visibleGauges.length - 1) * root.gaugeGap
    : root.barSize

  // Tooltip and hover surface, above the drawing so it hears the pointer.
  WidgetButton {
    z: 1
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    keepSpace: true
    tooltipText: root.tooltipSummary
  }

  component Gauge: Item {
    id: gauge

    property real percent: 0
    property string number: "0"
    property string unit: "%"

    implicitWidth: root.gaugeSize
    implicitHeight: root.gaugeSize
    width: implicitWidth
    height: implicitHeight

    // Gentle ease when the value moves; Style.duration returns 0 under
    // reduced motion, so the change snaps instead.
    Behavior on percent {
      NumberAnimation {
        duration: Commons.Style.duration(300)
        easing.type: Easing.OutCubic
      }
    }

    Shape {
      anchors.fill: parent
      antialiasing: true

      // Track: the full 270° sweep, opening at the bottom.
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.trackColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap

        PathAngleArc {
          centerX: root.gaugeSize / 2
          centerY: root.gaugeSize / 2
          radiusX: root.ringRadius
          radiusY: root.ringRadius
          startAngle: 135
          sweepAngle: 270
          moveToStart: true
        }
      }

      // Value: the same sweep, cut to the reading.
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.arcColor
        strokeWidth: root.strokeWidth
        capStyle: ShapePath.RoundCap

        PathAngleArc {
          centerX: root.gaugeSize / 2
          centerY: root.gaugeSize / 2
          radiusX: root.ringRadius
          radiusY: root.ringRadius
          startAngle: 135
          sweepAngle: 270 * Math.max(0, Math.min(100, gauge.percent)) / 100
          moveToStart: true
        }
      }
    }

    // Reading in the ring: number just above the center, tiny unit below.
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.verticalCenter
      anchors.bottomMargin: 1
      text: gauge.number
      textFormat: Text.PlainText
      color: root.labelColor
      font.family: root.fontFamily
      font.pixelSize: root.numberFont
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.verticalCenter
      text: gauge.unit
      textFormat: Text.PlainText
      color: root.unitColor
      font.pixelSize: root.unitFont
    }
  }

  Gauge {
    id: cpuGauge
    visible: root.showCpu
    percent: root.cpuPercent
    number: String(Math.round(root.cpuPercent))
    unit: "%"
    x: root.vertical ? Math.round((root.barSize - root.gaugeSize) / 2) : root.slot(cpuGauge) * root.gaugeStride
    y: root.vertical ? root.slot(cpuGauge) * root.gaugeStride : Math.round((root.barSize - root.gaugeSize) / 2)
  }

  Gauge {
    id: memGauge
    visible: root.showMem
    percent: root.memPercent
    number: String(Math.round(root.memPercent))
    unit: "%"
    x: root.vertical ? Math.round((root.barSize - root.gaugeSize) / 2) : root.slot(memGauge) * root.gaugeStride
    y: root.vertical ? root.slot(memGauge) * root.gaugeStride : Math.round((root.barSize - root.gaugeSize) / 2)
  }

  Gauge {
    id: tempGauge
    visible: root.showTemp && root.tempAvailable
    percent: root.tempPercent
    number: String(Math.round(root.tempCelsius))
    unit: "\u00B0C"
    x: root.vertical ? Math.round((root.barSize - root.gaugeSize) / 2) : root.slot(tempGauge) * root.gaugeStride
    y: root.vertical ? root.slot(tempGauge) * root.gaugeStride : Math.round((root.barSize - root.gaugeSize) / 2)
  }
}