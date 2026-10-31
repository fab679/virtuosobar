import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui

// Virtuoso Stream: live network throughput as a small waveform in the bar,
// companion to Virtuoso Wave. A Timer reloads /proc/net/dev through a
// FileView; rx+tx bytes are summed over every interface except lo, deltas
// become per-interval rates, and the last few dozen plot as a filled
// silhouette in the theme accent with a hairline top edge. Rates print
// beside it in the bar foreground — nothing hardcoded.
BarWidget {
  id: root
  moduleName: "virtuoso.stream"

  // Per-entry settings, read by property name from the widget's shell.json
  // entry through the base's setting() helper. Item.width cannot be
  // redeclared, so the "width" setting lands on graphWidth.
  readonly property int pollIntervalMs: Number(setting("pollIntervalMs", 1000))
  readonly property int history: Math.max(2, Number(setting("history", 40)))
  readonly property bool showRates: setting("showRates", true) !== false
  readonly property int graphWidth: Math.max(24, Number(setting("width", 72)))

  readonly property real graphHeight: Math.max(8, root.barSize * 0.5)
  readonly property bool showText: root.showRates && !root.vertical

  property var lastSample: null
  property var samples: []
  property real rxRate: 0
  property real txRate: 0

  // Zero traffic flattens the line and settles the whole widget at reduced
  // opacity; traffic resumes it. Reduced motion skips the easing only.
  readonly property bool idle: {
    var data = root.samples
    return data.length === 0 || data[data.length - 1] <= 0
  }
  opacity: root.idle ? 0.35 : 1.0

  Behavior on opacity {
    enabled: !Commons.Style.reduceMotion
    NumberAnimation { duration: Commons.Style.duration(400); easing.type: Easing.OutCubic }
  }

  function parseTotals(text) {
    var lines = String(text || "").split("\n")
    var rx = 0
    var tx = 0
    for (var i = 2; i < lines.length; i++) {
      var sep = lines[i].indexOf(":")
      if (sep === -1) continue
      if (lines[i].substring(0, sep).trim() === "lo") continue
      var fields = lines[i].substring(sep + 1).trim().split(/\s+/)
      if (fields.length < 9) continue
      var rxBytes = parseInt(fields[0], 10)
      var txBytes = parseInt(fields[8], 10)
      if (isFinite(rxBytes)) rx += rxBytes
      if (isFinite(txBytes)) tx += txBytes
    }
    return { rx: rx, tx: tx }
  }

  function sample(text) {
    var now = Date.now()
    var totals = root.parseTotals(text)

    if (root.lastSample) {
      var seconds = Math.max(1, now - root.lastSample.at) / 1000
      // Counters restart when an interface bounces; a negative delta is
      // dropped rather than drawn as a hole.
      root.rxRate = Math.max(0, totals.rx - root.lastSample.rx) / seconds
      root.txRate = Math.max(0, totals.tx - root.lastSample.tx) / seconds
    } else {
      root.rxRate = 0
      root.txRate = 0
    }

    var next = root.samples.concat([root.rxRate + root.txRate])
    while (next.length > root.history) next.shift()
    root.samples = next
    root.lastSample = { rx: totals.rx, tx: totals.tx, at: now }
    wave.requestPaint()
  }

  function fmtRate(bytesPerSec) {
    var bits = bytesPerSec * 8
    if (bits >= 1000000) return (bits / 1000000).toFixed(1) + "Mb"
    if (bits >= 1000) return (bits / 1000).toFixed(1) + "Kb"
    return Math.round(bits) + "b"
  }

  readonly property string rateText: "\u2193" + root.fmtRate(root.rxRate) + " \u2191" + root.fmtRate(root.txRate)

  visible: true
  implicitWidth: root.graphWidth + (root.showText ? ratesLabel.implicitWidth + Commons.Style.space(5) : 0)
  implicitHeight: root.barSize

  RowLayout {
    anchors.centerIn: parent
    spacing: Commons.Style.space(5)

    Item {
      Layout.alignment: Qt.AlignVCenter
      Layout.preferredWidth: root.vertical ? Math.min(root.graphWidth, root.barSize) : root.graphWidth
      Layout.preferredHeight: root.graphHeight

      Canvas {
        id: wave
        anchors.fill: parent
        antialiasing: true

        onWidthChanged: wave.requestPaint()

        onPaint: {
          var ctx = wave.getContext("2d")
          ctx.clearRect(0, 0, wave.width, wave.height)

          var data = root.samples
          if (data.length === 0) return

          var accent = Commons.Color.accent
          var fill = "rgba(" + Math.round(accent.r * 255) + "," + Math.round(accent.g * 255) + "," + Math.round(accent.b * 255) + ",0.3)"
          var edge = "rgba(" + Math.round(accent.r * 255) + "," + Math.round(accent.g * 255) + "," + Math.round(accent.b * 255) + ",1)"

          var peak = 0
          for (var i = 0; i < data.length; i++) peak = Math.max(peak, data[i])
          if (peak <= 0) peak = 1

          var w = wave.width
          var h = wave.height
          var step = w / Math.max(1, root.history - 1)
          var points = []
          for (var j = 0; j < data.length; j++) {
            points.push({
              x: w - (data.length - 1 - j) * step,
              y: h - Math.min(1, data[j] / peak) * (h - 1)
            })
          }

          // Silhouette: the rate line closed against the bottom edge.
          ctx.beginPath()
          ctx.moveTo(points[0].x, points[0].y)
          for (var k = 1; k < points.length; k++) ctx.lineTo(points[k].x, points[k].y)
          ctx.lineTo(points[points.length - 1].x, h)
          ctx.lineTo(points[0].x, h)
          ctx.closePath()
          ctx.fillStyle = fill
          ctx.fill()

          // Hairline top edge at full accent.
          ctx.beginPath()
          ctx.moveTo(points[0].x, points[0].y)
          for (var m = 1; m < points.length; m++) ctx.lineTo(points[m].x, points[m].y)
          ctx.strokeStyle = edge
          ctx.lineWidth = 1
          ctx.stroke()
        }
      }
    }

    Text {
      id: ratesLabel
      visible: root.showText
      Layout.alignment: Qt.AlignVCenter
      textFormat: Text.PlainText
      text: root.rateText
      color: Commons.Color.bar.text
      opacity: 0.75
      font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
    }
  }

  // /proc/net/dev never signals changes; a timer drives the reads and the
  // deltas carry the timing, so a slow or skipped poll stays truthful.
  FileView {
    id: netDev
    path: "/proc/net/dev"
    printErrors: false
    onLoaded: root.sample(text())
    onLoadFailed: root.sample("")
  }

  Timer {
    id: pollTimer
    interval: Math.max(200, root.pollIntervalMs)
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: netDev.reload()
  }
}