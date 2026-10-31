import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Sci-fi seven-segment clock. The digits are drawn, not typeset: each glyph
// is seven polygons in a Shape, lit in the theme accent, with the unlit
// channels left as dim ghost segments the way a real display shows its dead
// ones. A tick ring right of the digits sweeps one notch per second.
BarWidget {
  id: root
  moduleName: "virtuoso.clock"

  // Per-entry settings ride the injected settings object (the host only ever
  // sets `settings`, never widget properties), with the same defaults the
  // panel reads. "Follows Omarchy settings": day and month names come from
  // the Omarchy language via I18n's format locale.
  readonly property bool use24h: typeof settings === "object" && settings !== null ? settings.use24h !== false : true
  readonly property bool showSecondsRing: typeof settings === "object" && settings !== null ? settings.showSecondsRing !== false : true
  readonly property bool blinkColons: typeof settings === "object" && settings !== null ? settings.blinkColons !== false : true
  readonly property bool ghostSegments: typeof settings === "object" && settings !== null ? settings.ghostSegments !== false : true
  readonly property bool showDate: typeof settings === "object" && settings !== null ? settings.showDate !== false : true

  // Day and month names follow the Omarchy language, not the system locale,
  // which only catches up at the next login — the same as the stock clock.
  readonly property var formatLocale: Qt.locale(I18n.formatLocale)
  property date displayDate: clock.date

  readonly property string timeText: Qt.formatDateTime(displayDate, use24h ? "HH:mm" : "hh:mm")
  readonly property string hourText: timeText.substring(0, 2)
  readonly property string minuteText: timeText.substring(3, 5)
  readonly property int seconds: displayDate.getSeconds()
  readonly property string tooltipText: displayDate.toLocaleDateString(formatLocale, "dddd, d MMMM yyyy")

  // ---- Calendar popup. Left click asks "what is the date", right click
  //      flips 24h. Same shape contract the stock clock keeps for the bar's
  //      summon/toggle routing: open/close/opened on the widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = clockButton
    if ("hostWidget" in target) target.hostWidget = root
  }

  // Right click flips the 24h setting. Applied locally first so the digits
  // change on the click itself; the shell.json write comes back as the same
  // value. The entry facade is allowed to write its own entry.
  function toggle24h() {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry["use24h"] = !(root.settings ? root.settings.use24h !== false : true)

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // The clock fills more slot than it paints: the open-panel dot takes the
  // seconds ring's width where there is one, else a notch of the digits.
  readonly property real openPanelIndicatorWidth: showSecondsRing && !vertical ? ringSize : digitW
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Geometry. The digits stay a little over half the bar high, so the drawn
  // segments read as an instrument rather than as the whole bar.
  readonly property real digitH: Math.round(barSize * 0.55)
  readonly property real digitW: Math.round(digitH * 0.62)
  readonly property real segThickness: Math.max(2, Math.round(digitW * 0.24))
  readonly property real segGap: Math.max(1, Math.round(segThickness * 0.45))
  readonly property real cellGap: Math.max(2, Math.round(digitH * 0.18))
  readonly property real dotSize: Math.max(2, Math.round(segThickness * 1.2))
  readonly property real ringOuter: Math.max(4, Math.round(digitH * 0.46))
  readonly property real ringSize: ringOuter * 2
  readonly property real ringTickLength: Math.max(2, Math.round(digitH * 0.13))
  readonly property real trailingGap: vertical ? 0 : Style.spaceReal(1.5)

  // Colors. Lit segments take the theme accent; ghosts are the bar's own
  // foreground far down, so unlit channels stay readable as structure.
  readonly property color litColor: Commons.Color.accent
  readonly property color ghostColor: ghostSegments ? Util.alpha(Commons.Color.bar.text, 0.12) : "transparent"
  readonly property color ringLitColor: Util.alpha(Commons.Color.accent, 0.8)

  // Seven-segment bit patterns, bit 0 = a (top) through bit 6 = g (middle),
  // the standard 0x3F/0x06/... table. An unknown character renders blank.
  readonly property var patterns: ({
    "0": 0x3F, "1": 0x06, "2": 0x5B, "3": 0x4F, "4": 0x66,
    "5": 0x6D, "6": 0x7D, "7": 0x07, "8": 0x7F, "9": 0x6F
  })

  // Corner points of every segment, drawn as hexagons with beveled ends
  // shortened by the gap, so adjacent segments approach the shared corner
  // without touching it. Index order matches the bit patterns: a b c d e f g.
  readonly property var segmentShapes: {
    var t = segThickness
    var g = segGap
    var xL = t / 2
    var xR = digitW - t / 2
    var yT = t / 2
    var yM = digitH / 2
    var yB = digitH - t / 2

    var across = function(y) {
      return [
        { x: xL + g, y: y },
        { x: xL + g + t / 2, y: y - t / 2 },
        { x: xR - g - t / 2, y: y - t / 2 },
        { x: xR - g, y: y },
        { x: xR - g - t / 2, y: y + t / 2 },
        { x: xL + g + t / 2, y: y + t / 2 }
      ]
    }

    var upright = function(x, top, bottom) {
      return [
        { x: x, y: top + g },
        { x: x + t / 2, y: top + g + t / 2 },
        { x: x + t / 2, y: bottom - g - t / 2 },
        { x: x, y: bottom - g },
        { x: x - t / 2, y: bottom - g - t / 2 },
        { x: x - t / 2, y: top + g + t / 2 }
      ]
    }

    return [
      across(yT),
      upright(xR, yT, yM),
      upright(xR, yM, yB),
      across(yB),
      upright(xL, yM, yB),
      upright(xL, yT, yM),
      across(yM)
    ]
  }

  function segmentSvg(index) {
    var points = segmentShapes[index]
    var path = "M " + points[0].x + " " + points[0].y
    for (var i = 1; i < points.length; i++) path += " L " + points[i].x + " " + points[i].y
    return path + " Z"
  }

  // One drawn digit, reused by every repeater below.
  Component {
    id: digitDelegate

    Item {
      id: digit
      required property string modelData
      readonly property int pattern: root.patterns[modelData] || 0

      width: root.digitW
      height: root.digitH

      function isLit(index) { return (digit.pattern & (1 << index)) !== 0 }

      Shape {
        anchors.fill: parent
        antialiasing: true

        ShapePath { // a — top
          strokeColor: "transparent"
          fillColor: digit.isLit(0) ? root.litColor : root.ghostColor
          PathSvg { path: root.segmentSvg(0) }
        }

        ShapePath { // b — upper right
          strokeColor: "transparent"
          fillColor: digit.isLit(1) ? root.litColor : root.ghostColor
          PathSvg { path: root.segmentSvg(1) }
        }

        ShapePath { // c — lower right
          strokeColor: "transparent"
          fillColor: digit.isLit(2) ? root.litColor : root.ghostColor
          PathSvg { path: root.segmentSvg(2) }
        }

        ShapePath { // d — bottom
          strokeColor: "transparent"
          fillColor: digit.isLit(3) ? root.litColor : root.ghostColor
          PathSvg { path: root.segmentSvg(3) }
        }

        ShapePath { // e — lower left
          strokeColor: "transparent"
          fillColor: digit.isLit(4) ? root.litColor : root.ghostColor
          PathSvg { path: root.segmentSvg(4) }
        }

        ShapePath { // f — upper left
          strokeColor: "transparent"
          fillColor: digit.isLit(5) ? root.litColor : root.ghostColor
          PathSvg { path: root.segmentSvg(5) }
        }

        ShapePath { // g — middle
          strokeColor: "transparent"
          fillColor: digit.isLit(6) ? root.litColor : root.ghostColor
          PathSvg { path: root.segmentSvg(6) }
        }
      }
    }
  }

  implicitWidth: vertical ? stack.implicitWidth : row.implicitWidth + trailingGap
  implicitHeight: vertical ? stack.implicitHeight : barSize

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  ShellIpc {
    target: "virtuoso.clock"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // The drawn digits sit over the button: shapes do not grab the pointer, so
  // presses and hovers land on the button under them.
  WidgetButton {
    id: clockButton
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.tooltipText
    pressFeedbackButtons: Qt.NoButton

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggle24h()
      else root.togglePanel()
    }
  }

  // Horizontal: HH:MM, colon between, seconds ring right of the digits.
  Row {
    id: row
    visible: !root.vertical
    anchors.centerIn: parent
    spacing: root.cellGap

    Repeater {
      model: [root.hourText.charAt(0), root.hourText.charAt(1)]
      delegate: digitDelegate
    }

    Item {
      id: colon
      width: root.dotSize
      height: root.digitH

      // The blink rides its own phase, so the dots fall back to steady
      // whenever blinking is off or reduced motion stills the animation.
      property real blinkPhase: 1

      SequentialAnimation on blinkPhase {
        running: root.blinkColons && !Style.reduceMotion
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { from: 1; to: 0.2; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.2; to: 1; duration: 500; easing.type: Easing.InOutSine }
      }

      Rectangle {
        x: (parent.width - width) / 2
        y: parent.height * 0.30 - height / 2
        width: root.dotSize
        height: root.dotSize
        radius: width / 2
        color: root.litColor
        opacity: root.blinkColons && !Style.reduceMotion ? colon.blinkPhase : 1
      }

      Rectangle {
        x: (parent.width - width) / 2
        y: parent.height * 0.70 - height / 2
        width: root.dotSize
        height: root.dotSize
        radius: width / 2
        color: root.litColor
        opacity: root.blinkColons && !Style.reduceMotion ? colon.blinkPhase : 1
      }
    }

    Repeater {
      model: [root.minuteText.charAt(0), root.minuteText.charAt(1)]
      delegate: digitDelegate
    }

    // Seconds sweep: sixty ticks around a ring, the elapsed ones lit, so the
    // arc grows one notch each second.
    Item {
      visible: root.showSecondsRing && !root.vertical
      width: root.ringSize
      height: root.ringSize

      Repeater {
        model: 60

        Rectangle {
          required property int index
          x: parent.width / 2 - width / 2
          y: parent.height / 2 - root.ringOuter
          width: 1
          height: root.ringTickLength
          radius: 0.5
          color: index <= root.seconds ? root.ringLitColor : root.ghostColor
          transform: Rotation { origin.x: width / 2; origin.y: root.ringOuter; angle: index * 6 }
        }
      }
    }

    // The date, as a small two-line readout beside the digits: the weekday
    // over the day and month. Names follow the Omarchy language, the same
    // locale the rest of the shell formats with. The wrapper gives the Row a
    // digit-sized cell; the column centers itself inside it, since children
    // of a Row may not anchor.
    Item {
      visible: root.showDate && !root.vertical
      width: dateColumn.implicitWidth
      height: root.digitH

      Column {
        id: dateColumn
        anchors.centerIn: parent
        spacing: Math.max(1, Math.round(root.digitH * 0.10))

        Text {
          text: root.displayDate.toLocaleDateString(root.formatLocale, "ddd").toUpperCase()
          color: Commons.Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Math.max(8, Math.round(root.digitH * 0.34))
          font.letterSpacing: 0.8
          renderType: Text.NativeRendering
        }

        Text {
          text: root.displayDate.toLocaleDateString(root.formatLocale, "d MMM").toUpperCase()
          color: Qt.rgba(Commons.Color.bar.text.r, Commons.Color.bar.text.g, Commons.Color.bar.text.b, 0.85)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Math.max(8, Math.round(root.digitH * 0.34))
          font.letterSpacing: 0.8
          renderType: Text.NativeRendering
        }
      }
    }
  }

  // Vertical: HH over MM. The two-row stack already spends the height budget,
  // so the seconds ring is skipped rather than squeezed in.
  Column {
    id: stack
    visible: root.vertical
    anchors.centerIn: parent
    spacing: root.cellGap

    Repeater {
      model: [root.hourText.charAt(0), root.hourText.charAt(1)]
      delegate: digitDelegate
    }

    Repeater {
      model: [root.minuteText.charAt(0), root.minuteText.charAt(1)]
      delegate: digitDelegate
    }
  }

  // Hover and clicks are the button's; no bare MouseArea here.

  // The ring is the only per-second reader, so the clock only ticks that
  // fast when the ring is shown.
  SystemClock {
    id: clock
    precision: root.showSecondsRing && !root.vertical ? SystemClock.Seconds : SystemClock.Minutes
    onDateChanged: {
      root.displayDate = date
      if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
    }
  }
}




