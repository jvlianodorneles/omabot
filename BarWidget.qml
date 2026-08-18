import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// BarWidget.qml - Status Bar Widget for Omabot (AI Bot & Prompt Directory)
BarWidget {
  id: root
  moduleName: "dorneles.omabot"

  readonly property bool showLabelSetting: setting("showLabel", false)
  readonly property int syncIntervalHoursSetting: Number(setting("syncIntervalHours", 12))
  readonly property string syncScriptPath: Qt.resolvedUrl("scripts/omabot-sync.py").toString().replace(/^file:\/\//, "")

  function open(): void {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close(): void {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle(): void {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function refresh(): void {
    if (panelLoader.item) panelLoader.item.triggerSync()
  }

  function injectPanel(): void {
    if (!panelLoader.item) return
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.bar = root.bar
  }

  onBarChanged: injectPanel()

  // Panel loader for the popup window
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

  // Periodic automatic background synchronizer
  Timer {
    id: autoSyncTimer
    interval: Math.max(1, root.syncIntervalHoursSetting) * 3600 * 1000
    running: root.syncIntervalHoursSetting > 0
    repeat: true
    onTriggered: root.refresh()
  }

  // IPC Handler for Hyprland keybindings, Omarchy menu, and CLI control
  IpcHandler {
    target: "dorneles.omabot"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function sync(): void { root.refresh() }
    function search(query: string): void {
      root.open()
      if (panelLoader.item) {
        panelLoader.item.searchQuery = query
      }
    }
    function copy(slug: string): void {
      if (panelLoader.item) {
        var bots = panelLoader.item.allBots || []
        for (var i = 0; i < bots.length; i++) {
          if (bots[i].slug === slug || bots[i].name === slug) {
            panelLoader.item.copyBotPrompt(bots[i])
            break
          }
        }
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Top Bar Button with Robot Icon
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical || !root.showLabelSetting ? "󰚩" : "󰚩 omabot"
    active: panelLoader.item ? panelLoader.item.opened : false
    dimmed: panelLoader.item ? !panelLoader.item.opened : true
    useActiveColor: true
    activeColor: bar ? bar.active : Color.accent
    fontSize: Style.font.body
    horizontalMargin: 8
    verticalPadding: 2
    tooltipText: "Omabot • AI Bot & Prompt Directory\n──────────────────────────────\n• Left-click: Open Bot Directory\n• Middle-click: Sync Latest Bots"

    onPressed: function(btn) {
      if (btn === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }
  }
}
