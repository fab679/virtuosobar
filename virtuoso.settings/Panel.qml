import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui

// Virtuoso Settings: a gear on the bar opening a popout that shapes the bar
// itself — surface, effects and the workspace pills — without a terminal.
// Reads ride bar.shell.barConfig (the live bar subtree of shell.json) and
// every write goes back through bar.shell.mutateShellConfig, so the host
// keeps owning the file and the bar re-applies whatever lands.
Ui.Panel {
  id: root
  moduleName: "virtuoso.settings"
  manageIpc: false

  // Set by the bar widget when it injects this panel.
  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // The settings facade. Without it the panel still shows the shape of the
  // controls, but every control is disabled and nothing can be written.
  readonly property var shellApi: bar ? bar.shell : null
  readonly property bool shellReady: shellApi !== null

  readonly property string workspacesModule: "virtuoso.workspaces"

  // ---- live reads ---------------------------------------------------------
  // Recomputed whenever the host re-injects barConfig, so the panel follows
  // config changes made underneath it (another widget, the CLI, a reload).

  readonly property var liveBarConfig: root.shellReady ? root.shellApi.barConfig : ({})
  readonly property var barOptions: Util.isPlainObject(liveBarConfig) && Util.isPlainObject(liveBarConfig.bar) ? liveBarConfig.bar : ({})
  readonly property var virtuosoOptions: Util.isPlainObject(barOptions.virtuoso) ? barOptions.virtuoso : ({})

  readonly property var surfaceStyleChoices: ["notch", "fit", "dock", "full"]
  readonly property var backgroundChoices: ["opaque", "glassy", "none"]
  readonly property var positionChoices: ["top", "bottom", "left", "right"]
  readonly property var pillStyleChoices: ["digits", "numbers", "halo", "kanji", "rings", "aurora", "pacman"]

  // Effect rows are gone from the panel, but the effect keys stay writable
  // through the IPC door and the script, so power users keep the control.

  function normalizeChoice(choices, raw, fallback) {
    var value = String(raw || "")
    return choices.indexOf(value) >= 0 ? value : fallback
  }

  // Effect flags read straight off bar.virtuoso. Absent and null mean on.
  function effectOn(key) {
    var value = virtuosoOptions[key]
    return value === undefined || value === null ? true : value === true
  }

  readonly property string liveStyle: normalizeChoice(surfaceStyleChoices, virtuosoOptions.style, "notch")
  readonly property string liveBackground: normalizeChoice(backgroundChoices, barOptions.background, "opaque")
  readonly property string livePosition: normalizeChoice(positionChoices, barOptions.position, "top")

  // The pill style lives on the virtuoso.workspaces layout entry, which may
  // sit in any section of the bar or inside a group's nested items. The
  // search walks the whole layout so the entry keeps its key wherever it
  // moves; an entry that is not on the bar at all reads as "digits".
  function findModuleEntry(config, moduleId) {
    var bar = Util.isPlainObject(config) ? config.bar : null
    var layout = Util.isPlainObject(bar) && Util.isPlainObject(bar.layout) ? bar.layout : null
    if (!layout) return null
    var sections = ["left", "centerBegin", "center", "centerEnd", "right", "tray"]

    function search(list) {
      if (!list || typeof list.length !== "number") return null
      for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        if (!Util.isPlainObject(entry)) continue
        if (String(entry.id || "") === moduleId) return entry
        var nested = search(entry.items)
        if (nested) return nested
      }
      return null
    }

    for (var s = 0; s < sections.length; s++) {
      var found = search(layout[sections[s]])
      if (found) return found
    }
    return null
  }

  function findWorkspacesEntry(config) {
    return findModuleEntry(config, root.workspacesModule)
  }

  readonly property var liveWorkspacesEntry: findWorkspacesEntry(liveBarConfig)
  readonly property string livePillStyle: normalizeChoice(pillStyleChoices,
    liveWorkspacesEntry ? liveWorkspacesEntry.pillStyle : "", "digits")

  // The name is the wordmark on the virtuoso.menu entry, found the same way.
  readonly property var liveMenuEntry: findModuleEntry(liveBarConfig, "virtuoso.menu")
  readonly property string liveWordmark: liveMenuEntry ? String(liveMenuEntry.wordmark || "") : ""

  // ---- writes -------------------------------------------------------------
  // The entry shell facade can read barConfig but cannot mutate it — the
  // host only hands the full-bar facade the config-mutator callback. Writes
  // therefore go through the sanctioned CLI and the plugin's own
  // virtuoso-style.sh, run detached on the bar. Rapid successive rewrites of
  // shell.json outrun the shell's config watcher, so writes are queued and
  // drained one every 300ms; the facade's barConfig re-injection corrects
  // every read once each write lands.

  readonly property string styleScript: {
    var url = Qt.resolvedUrl("scripts/virtuoso-style.sh")
    return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
  }

  property var pendingWrites: []
  Timer {
    id: writeDrain
    interval: 300
    onTriggered: root.drainWrite()
  }

  function queueWrite(command) {
    root.pendingWrites.push(command)
    writeDrain.restart()
  }

  function drainWrite() {
    if (root.pendingWrites.length === 0) return
    var command = root.pendingWrites.shift()
    if (root.bar && typeof root.bar.run === "function") root.bar.run(command)
    if (root.pendingWrites.length > 0) writeDrain.restart()
  }

  function writeVirtuosoKey(key, value) {
    queueWrite(styleScript + " " + key + " " + (value === true ? "on" : "off"))
  }

  function writeSurfaceStyle(style) {
    queueWrite(styleScript + " " + Util.shellQuote(String(style || "notch")))
  }

  // "digits" is the pill style's default; the script stores it explicitly,
  // which reads back identically, so one command shape covers every choice.
  function writePillStyle(style) {
    queueWrite(styleScript + " pill " + Util.shellQuote(String(style || "digits")))
  }

  // The wordmark is stored raw and shown uppercased; an empty field falls
  // back to the widget's own default, VIRTUOSO.
  function writeWordmark(text) {
    var value = String(text || "").trim().slice(0, 24)
    queueWrite(styleScript + " name " + Util.shellQuote(value === "" ? "VIRTUOSO" : value))
  }

  function toggleEffect(key) {
    writeVirtuosoKey(key, !effectOn(key))
  }

  // ---- dropdown state -----------------------------------------------------
  // Dropdowns own their selection once a choice lands, so values are mirrored
  // into plain properties and re-synced when the panel opens or the host
  // hands back a changed config. Toggle rows keep live bindings instead —
  // they never write `checked` themselves.

  property string styleValue: "notch"
  property string backgroundValue: "opaque"
  property string positionValue: "top"
  property string pillStyleValue: "digits"
  property string wordmarkValue: ""

  function syncValues() {
    styleValue = liveStyle
    backgroundValue = liveBackground
    positionValue = livePosition
    pillStyleValue = livePillStyle
    // Leave the name field alone while it is being typed in.
    if (!nameField.activeFocus) wordmarkValue = liveWordmark
  }

  function setSurfaceStyle(value) {
    styleValue = value
    writeSurfaceStyle(value)
  }

  function setBackgroundLook(value) {
    backgroundValue = value
    queueWrite(styleScript + " background " + Util.shellQuote(String(value || "opaque")))
  }

  function setBarPosition(value) {
    positionValue = value
    queueWrite(styleScript + " position " + Util.shellQuote(String(value || "top")))
  }

  function setPillStyle(value) {
    pillStyleValue = value
    writePillStyle(value)
  }

  Component.onCompleted: syncValues()
  onOpenedChanged: if (opened) syncValues()

  Connections {
    target: root.shellApi
    function onBarConfigChanged() { root.syncValues() }
  }

  // Color.muted reads too dark on the popup surface; lift it toward bar text.
  readonly property color mutedText: Qt.rgba(
    Color.muted.r * 0.18 + barForeground.r * 0.82,
    Color.muted.g * 0.18 + barForeground.g * 0.82,
    Color.muted.b * 0.18 + barForeground.b * 0.82,
    1)

  Ui.KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    contentWidth: Style.space(420)
    contentHeight: fittedContentHeight(scroll.contentHeight, Style.space(640))

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: settingsColumn.implicitHeight
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds

      ColumnLayout {
        id: settingsColumn
        width: scroll.width
        spacing: Style.spacing.sm

        Text {
          Layout.fillWidth: true
          text: "Bar settings"
          textFormat: Text.PlainText
          color: root.barForeground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          visible: !root.shellReady
          text: "Settings facade unavailable"
          textFormat: Text.PlainText
          color: root.mutedText
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---- NAME ------------------------------------------------------------

        Ui.PanelSeparator {
          Layout.fillWidth: true
        }

        Ui.PanelSectionHeader {
          text: "Name"
        }

        Rectangle {
          Layout.fillWidth: true
          enabled: root.shellReady
          opacity: enabled ? 1 : 0.45
          height: Style.space(36)
          radius: Style.space(8)
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.06)
          border.width: 1
          border.color: nameField.activeFocus ? Color.accent
            : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.18)

          TextInput {
            id: nameField
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            verticalAlignment: TextInput.AlignVCenter
            enabled: root.shellReady
            color: root.barForeground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            text: root.wordmarkValue
            maximumLength: 24
            selectByMouse: true
            echoMode: TextInput.Normal
            onEditingFinished: root.writeWordmark(text)
          }
        }

        Text {
          Layout.fillWidth: true
          text: "The letterspaced mark on the far left. Shown uppercased; empty falls back to VIRTUOSO."
          textFormat: Text.PlainText
          color: root.mutedText
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---- SURFACE ----------------------------------------------------

        Ui.PanelSeparator {
          Layout.fillWidth: true
        }

        Ui.PanelSectionHeader {
          text: "Surface"
        }

        Ui.Dropdown {
          Layout.fillWidth: true
          enabled: root.shellReady
          opacity: enabled ? 1 : 0.45
          label: "Style"
          value: root.styleValue
          options: [
            { value: "notch", label: "Notch" },
            { value: "fit", label: "Fit" },
            { value: "dock", label: "Dock" },
            { value: "full", label: "Full" }
          ]
          onChanged: function(value) { root.setSurfaceStyle(value) }
        }

        Ui.Dropdown {
          Layout.fillWidth: true
          enabled: root.shellReady
          opacity: enabled ? 1 : 0.45
          label: "Background"
          value: root.backgroundValue
          options: [
            { value: "opaque", label: "Opaque" },
            { value: "glassy", label: "Glassy" },
            { value: "none", label: "None" }
          ]
          onChanged: function(value) { root.setBackgroundLook(value) }
        }

        Ui.Dropdown {
          Layout.fillWidth: true
          enabled: root.shellReady
          opacity: enabled ? 1 : 0.45
          label: "Position"
          value: root.positionValue
          options: [
            { value: "top", label: "Top" },
            { value: "bottom", label: "Bottom" },
            { value: "left", label: "Left" },
            { value: "right", label: "Right" }
          ]
          onChanged: function(value) { root.setBarPosition(value) }
        }

        Text {
          Layout.fillWidth: true
          text: "Left and right are experimental."
          textFormat: Text.PlainText
          color: root.mutedText
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---- WORKSPACES -------------------------------------------------

        Ui.PanelSeparator {
          Layout.fillWidth: true
        }

        Ui.PanelSectionHeader {
          text: "Workspaces"
        }

        Ui.Dropdown {
          Layout.fillWidth: true
          enabled: root.shellReady
          opacity: enabled ? 1 : 0.45
          label: "Pill style"
          value: root.pillStyleValue
          options: [
            { value: "digits", label: "Digits" },
            { value: "numbers", label: "Numbers" },
            { value: "halo", label: "Halo" },
            { value: "kanji", label: "Kanji" },
            { value: "rings", label: "Rings" },
            { value: "aurora", label: "Aurora" },
            { value: "pacman", label: "Pacman" }
          ]
          onChanged: function(value) { root.setPillStyle(value) }
        }

        Text {
          Layout.fillWidth: true
          text: "Applies to the workspace pills instantly."
          textFormat: Text.PlainText
          color: root.mutedText
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}

