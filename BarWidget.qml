import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// BarWidget.qml - Status Bar Widget for Omabot
BarWidget {
  id: root
  moduleName: "dorneles.omabot"

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem
    ? panelItem.popoutSwitchClosing === true
    : false

  readonly property bool showLabelSetting: setting("showLabel", false)
  readonly property string iconStyleSetting: setting("iconStyle", "robot")
  readonly property string customIconSetting: setting("customIcon", "")
  readonly property string activeBarIcon: Model.resolveBarIcon(iconStyleSetting, customIconSetting)

  function open() {
    if (panelItem && panelItem.open) panelItem.open()
  }

  function close() {
    if (panelItem && panelItem.close) panelItem.close()
  }

  function toggle() {
    if (panelItem && panelItem.toggle) panelItem.toggle()
  }

  function togglePanel() {
    toggle()
  }

  function closeForPopoutSwitch() {
    if (panelItem && panelItem.closeForPopoutSwitch) panelItem.closeForPopoutSwitch()
  }

  function updateSetting(key, val) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = val
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    }
  }

  function cycleIconStyle() {
    var next = Model.nextIconStyle(iconStyleSetting)
    updateSetting("iconStyle", next)
  }

  function setIconStyle(styleName) {
    updateSetting("iconStyle", styleName)
  }

  function triggerSync() {
    if (panelItem && panelItem.triggerSync) {
      panelItem.triggerSync()
    }
  }

  function injectPanel() {
    var target = panelItem
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

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical || !root.showLabelSetting ? root.activeBarIcon : (root.activeBarIcon + " omabot")
    active: true
    dimmed: false
    useActiveColor: true
    activeColor: bar ? bar.urgent : Color.urgent
    fontSize: Style.font.body
    horizontalMargin: 8
    verticalPadding: 2
    tooltipText: "Omabot • AI Bot & Prompt Directory\n──────────────────────────────\n• Left-click: Open Bot Directory\n• Right-click: Cycle Bar Icon (" + root.iconStyleSetting + ")\n• Middle-click: Sync Latest Bots"

    onPressed: function(btn) {
      if (btn === Qt.RightButton) {
        root.cycleIconStyle()
      } else if (btn === Qt.MiddleButton) {
        root.triggerSync()
      } else {
        root.toggle()
      }
    }
  }
}
