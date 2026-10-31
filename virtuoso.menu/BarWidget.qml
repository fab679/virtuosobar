import QtQuick
import qs.Ui

// VIRTUOSO wordmark: opens the stock Omarchy menu, exactly like the stock
// menu button (left click menu, right click terminal). The overlay stays
// stock omarchy.menu; only the bar mark is ours.
BarWidget {
  id: root
  moduleName: "virtuoso.menu"

  // Handed to us by the bar host from our shell.json entry (same mechanism
  // as stock widgets). Carries the optional user wordmark.
  property var settings

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return (value === undefined || value === null || value === "") ? fallback : value
  }

  // Custom wordmark: always uppercased into the letterspaced house style,
  // capped so a long string can't blow out the bar. PlainText below keeps
  // markup-shaped input inert.
  readonly property string wordmark: String(setting("wordmark", "VIRTUOSO")).toUpperCase().slice(0, 24)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : mark.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? mark.implicitWidth + scaledHorizontalMargin * 2 : -1
    tooltipText: "Omarchy menu"
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }

    Text {
      id: mark
      anchors.centerIn: parent
      rotation: root.vertical ? -90 : 0
      textFormat: Text.PlainText
      text: root.wordmark
      font.family: button.fontFamily
      font.pixelSize: button.fontSize + 1
      font.weight: Font.DemiBold
      font.letterSpacing: 3
      color: button.foreground
    }
  }
}
