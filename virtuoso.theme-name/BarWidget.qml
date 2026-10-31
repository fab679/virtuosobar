import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Virtuoso theme name: the live theme in VIRTUOSO wordmark style, closing
// out the left section. Left click deals the Hearth card deck for themes
// and wallpapers; right click falls back to the system switcher.
BarWidget {
  id: root
  moduleName: "virtuoso.theme-name"

  property string themeName: ""

  // ---- Panel contract for shell.summon/hide/toggle routing.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  FileView {
    id: themeNameFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeName = String(text()).trim().replace(/[_-]+/g, " ").toUpperCase()
    onLoadFailed: root.themeName = ""
  }

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
    target: "virtuoso.theme-name"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: root.themeName !== ""
    fixedWidth: root.vertical ? -1 : mark.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? mark.implicitWidth + scaledHorizontalMargin * 2 : -1
    tooltipText: "Browse themes and wallpapers (right click: system switcher)"
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("s=$(omarchy-theme-switcher) && [ -n \"$s\" ] && omarchy-theme-set \"$s\"")
      else root.togglePanel()
    }

    Text {
      id: mark
      anchors.centerIn: parent
      rotation: root.vertical ? -90 : 0
      textFormat: Text.PlainText
      text: root.themeName
      font.family: button.fontFamily
      font.pixelSize: button.fontSize + 1
      font.weight: Font.DemiBold
      font.letterSpacing: 2
      color: button.foreground
    }
  }
}
