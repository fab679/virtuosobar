import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// A gear on the bar that opens the settings popout. The widget is the icon
// only: every write and read happens in the panel through the plugin facades,
// so this file stays a loader plus a button, the way lxp.vitals shapes its
// widget/panel pair.
BarWidget {
  id: root
  moduleName: "virtuoso.settings"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  // The panel needs the bar facade, the layout settings, the button to hang
  // its card from, and this widget as its popout identity. Injection re-runs
  // whenever the host hands over a new facade or settings object.
  function injectPanel() {
    var panel = panelLoader.item
    if (!panel) return
    panel.bar = root.bar
    panel.settings = root.settings
    panel.anchorItem = button
    panel.hostWidget = root
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The cog out of the FontAwesome block, the same range the stock
    // SystemUpdate widget draws its refresh arrow from.
    text: "\uf013"
    tooltipText: "Bar settings"
    active: root.opened
    useActiveColor: false
    onPressed: function(mouseButton) {
      if (panelLoader.item) panelLoader.item.toggle()
    }
  }

  // A CLI door into the panel, so its write path can be driven (and checked)
  // without pointing at the gear. The panel instance is per monitor; whichever
  // instance claims the target acts on the shared config, so it does not
  // matter which one answers.
  ShellIpc {
    target: "virtuoso.settings"

    function toggle(key: string): void {
      var panel = panelLoader.item
      if (panel) panel.toggleEffect(String(key || ""))
    }

    function effect(key: string, value: string): void {
      var panel = panelLoader.item
      if (panel) panel.writeVirtuosoKey(String(key || ""), String(value || "on") === "on")
    }

    function surface(style: string): void {
      var panel = panelLoader.item
      if (panel) panel.setSurfaceStyle(String(style || ""))
    }

    function pill(style: string): void {
      var panel = panelLoader.item
      if (panel) panel.setPillStyle(String(style || ""))
    }

    function name(value: string): void {
      var panel = panelLoader.item
      if (panel) panel.writeWordmark(String(value || ""))
    }

    function open(): void { root.open() }

    function debug(): string {
      var panel = panelLoader.item
      if (!panel) return "no panel"
      return JSON.stringify({
        background: panel.liveBackground,
        style: panel.liveStyle,
        pill: panel.livePillStyle,
        wordmark: panel.liveWordmark
      })
    }
  }
}

