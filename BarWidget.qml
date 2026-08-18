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

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function refresh() {
    if (panelLoader.item) panelLoader.item.triggerSync()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // Panel loader for the popup window
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
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
    active: root.opened
    dimmed: !root.opened
    useActiveColor: true
    activeColor: bar ? bar.urgent : Color.urgent
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
