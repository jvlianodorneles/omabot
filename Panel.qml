import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Panel.qml - AI Bot Directory popup window for Omabot
Panel {
  id: root
  moduleName: "dorneles.omabot"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: Color.popups.text
  readonly property color activeColor: Color.accent
  readonly property string fontFamily: Style.font.family

  // Bot dataset and filter state
  property var allBots: []
  property string searchQuery: ""
  property string selectedCategory: "All"
  property string copiedSlug: ""
  property bool isSyncing: false

  readonly property var categories: Model.extractCategories(allBots)
  readonly property var filteredBots: Model.filterBots(allBots, searchQuery, selectedCategory)
  readonly property string syncScriptPath: Qt.resolvedUrl("scripts/omabot-sync.py").toString().replace(/^file:\/\//, "")
  readonly property string stateFilePath: Quickshell.env("HOME") + "/.local/state/omarchy/omabot/bots.json"

  function open() {
    controller.show()
    stateFile.reload()
    Qt.callLater(function() {
      if (searchInput) {
        searchInput.forceActiveFocus()
        searchInput.selectAll()
      }
    })
  }

  function close() {
    categoryPopup.close()
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") {
      return bar.switchPanelFrom(barIdentity, direction)
    }
    return false
  }

  function triggerSync() {
    if (syncProcess.running) return
    isSyncing = true
    syncProcess.command = ["python3", syncScriptPath, "sync"]
    syncProcess.running = true
  }

  function copyBotPrompt(bot) {
    if (!bot || !bot.prompt) return
    copiedSlug = bot.slug || bot.name
    
    // Copy via sync script / wl-copy
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "copy", bot.slug || bot.name])
    } else {
      Quickshell.execDetached(["wl-copy", bot.prompt])
    }

    copiedTimer.restart()
  }

  function openSourceUrl() {
    Quickshell.execDetached(["xdg-open", "https://github.com/elie222/botdirectory.ai"])
  }

  // Live state watcher
  property FileView stateFile: FileView {
    path: root.stateFilePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = Model.parseBots(text())
      if (parsed && parsed.length > 0) {
        root.allBots = parsed
      }
    }
  }

  // Builtin fallback data loader
  property FileView builtinFile: FileView {
    path: Qt.resolvedUrl("data/bots.json").toString().replace(/^file:\/\//, "")
    printErrors: false
    onLoaded: {
      if (!root.allBots || root.allBots.length === 0) {
        var parsed = Model.parseBots(text())
        if (parsed && parsed.length > 0) {
          root.allBots = parsed
        }
      }
    }
  }

  Component.onCompleted: {
    stateFile.reload()
    builtinFile.reload()
  }

  Process {
    id: syncProcess
    onExited: function(exitCode) {
      root.isSyncing = false
      stateFile.reload()
    }
  }

  Timer {
    id: copiedTimer
    interval: 1800
    onTriggered: {
      root.copiedSlug = ""
    }
  }

  // Native Popup Window
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: searchInput
    contentWidth: panel.fittedContentWidth ? panel.fittedContentWidth(Style.space(420)) : Style.space(420)
    contentHeight: Style.space(520)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Main Vertical Layout Container (3 Sections: Header, Results List, Footer)
      Item {
        anchors.fill: parent

        // =====================================================================
        // SECTION 1: HEADER (Control Area - Search Bar & Category Filter)
        // =====================================================================
        Item {
          id: headerSection
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: searchContainer.height + categoryFilterRow.height + Style.space(14)

          // --- 1. Search Bar (Top Element) ---
          BorderSurface {
            id: searchContainer
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.space(36)
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6

            readonly property bool isFocused: searchInput.activeFocus
            readonly property bool isHot: searchMouse.containsMouse || searchInput.hovered
            readonly property var borderSpecObj: Border.controlSpec(
              isFocused ? "focus" : (isHot ? "hover-cursor" : "normal"),
              Color.popups.text,
              Color.accent
            )

            color: Style.controlFill(isFocused, isHot, Color.popups.text, Color.accent)
            borderSpec: borderSpecObj

            MouseArea {
              id: searchMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.IBeamCursor
              onClicked: searchInput.forceActiveFocus()
            }

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              // Magnifying Glass Icon (Dark Grey / Muted)
              Text {
                text: "󰍉" // nf-md-magnify
                color: Qt.darker(Color.popups.text, 1.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                Layout.alignment: Qt.AlignVCenter
              }

              // Search Text Input
              TextInput {
                id: searchInput
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                selectByMouse: true
                selectionColor: Style.selectionFillFor(Color.popups.text, Color.accent)
                selectedTextColor: Color.popups.text
                clip: true

                onTextChanged: {
                  root.searchQuery = text
                }

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    if (text !== "") {
                      text = ""
                      event.accepted = true
                    } else {
                      root.close()
                      event.accepted = true
                    }
                  } else if (event.key === Qt.Key_Down) {
                    botListView.forceActiveFocus()
                    if (botListView.count > 0 && botListView.currentIndex < 0) {
                      botListView.currentIndex = 0
                    }
                    event.accepted = true
                  }
                }

                // Placeholder Text
                Text {
                  anchors.fill: parent
                  visible: !searchInput.text && !searchInput.inputMethodComposing
                  text: "Search bots..."
                  color: Qt.darker(Color.popups.text, 1.8)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  verticalAlignment: Text.AlignVCenter
                }
              }

              // Clear Button (X)
              Rectangle {
                visible: searchInput.text !== ""
                width: Style.space(18)
                height: Style.space(18)
                radius: width / 2
                color: clearHover.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
                Layout.alignment: Qt.AlignVCenter

                Text {
                  anchors.centerIn: parent
                  text: "✕"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.popups.text, 1.4)
                }

                MouseArea {
                  id: clearHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    searchInput.text = ""
                    searchInput.forceActiveFocus()
                  }
                }
              }

              // Refresh / Sync Indicator
              Rectangle {
                visible: root.isSyncing
                width: Style.space(18)
                height: Style.space(18)
                color: "transparent"
                Layout.alignment: Qt.AlignVCenter

                Text {
                  anchors.centerIn: parent
                  text: "󰑐"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  color: Color.accent

                  RotationAnimator on rotation {
                    running: root.isSyncing
                    from: 0
                    to: 360
                    duration: 800
                    loops: Animation.Infinite
                  }
                }
              }
            }
          }

          // --- 2. Category Filter (Bottom Element) ---
          Row {
            id: categoryFilterRow
            anchors.top: searchContainer.bottom
            anchors.topMargin: Style.space(8)
            anchors.right: parent.right
            spacing: Style.space(8)
            z: 20

            // "CATEGORIES" Label
            Text {
              text: "CATEGORIES"
              color: Qt.darker(Color.popups.text, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
              anchors.verticalCenter: parent.verticalCenter
            }

            // Category Dropdown Trigger Selector
            BorderSurface {
              id: categorySelector
              height: Style.space(24)
              implicitWidth: catContentRow.implicitWidth + Style.space(16)
              radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4

              readonly property bool isHot: catMouseArea.containsMouse || categoryPopup.opened
              readonly property var borderSpecObj: Border.controlSpec(
                categoryPopup.opened ? "focus" : (isHot ? "hover-cursor" : "normal"),
                Color.popups.text,
                Color.accent
              )

              color: Style.controlFill(categoryPopup.opened, isHot, Color.popups.text, Color.accent)
              borderSpec: borderSpecObj
              anchors.verticalCenter: parent.verticalCenter

              Row {
                id: catContentRow
                anchors.centerIn: parent
                spacing: Style.space(6)

                Text {
                  text: root.selectedCategory
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }

                // Small Chevron Down Icon
                Text {
                  text: "󰅀" // nf-md-chevron_down
                  color: Qt.darker(Color.popups.text, 1.3)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: catMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (categoryPopup.opened) {
                    categoryPopup.close()
                  } else {
                    categoryPopup.open()
                  }
                }
              }

              // Floating Category Dropdown Menu
              Popup {
                id: categoryPopup
                x: categorySelector.width - width
                y: categorySelector.height + Style.space(4)
                width: Style.space(160)
                implicitHeight: Math.min(
                  Style.space(220),
                  catListView.contentHeight + Style.space(8)
                )
                padding: Style.space(4)
                focus: true

                background: BorderSurface {
                  color: Color.popups.background
                  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                  borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(1.5)))
                }

                contentItem: ListView {
                  id: catListView
                  model: root.categories
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  spacing: Style.space(2)

                  delegate: Rectangle {
                    required property string modelData
                    required property int index

                    width: catListView.width
                    height: Style.space(28)
                    radius: Style.cornerRadius > 0 ? Style.cornerRadius - 1 : 4
                    color: {
                      if (modelData === root.selectedCategory) {
                        return Style.selectedFillFor(Color.popups.text, Color.accent)
                      } else if (catItemHover.containsMouse) {
                        return Style.hoverFillFor(Color.popups.text, Color.accent)
                      }
                      return "transparent"
                    }

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(8)
                      anchors.rightMargin: Style.space(8)
                      spacing: Style.space(6)

                      Text {
                        text: modelData
                        color: modelData === root.selectedCategory ? Color.accent : Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: modelData === root.selectedCategory
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        width: parent.width - (modelData === root.selectedCategory ? Style.space(18) : 0)
                      }

                      Text {
                        visible: modelData === root.selectedCategory
                        text: "󰄬"
                        color: Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    MouseArea {
                      id: catItemHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.selectedCategory = modelData
                        categoryPopup.close()
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // =====================================================================
        // SECTION 2: RESULTS LIST (Central Area - Scrollable Bot Items)
        // =====================================================================
        Item {
          id: resultsSection
          anchors.top: headerSection.bottom
          anchors.bottom: footerSection.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.space(4)
          anchors.bottomMargin: Style.space(6)
          clip: true

          // Empty State
          Column {
            anchors.centerIn: parent
            visible: root.filteredBots.length === 0
            spacing: Style.space(8)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "󰚩" // nf-md-robot
              color: Qt.darker(Color.popups.text, 1.8)
              font.family: Style.font.family
              font.pixelSize: Style.space(36)
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.searchQuery ? "No bots found for '" + root.searchQuery + "'" : "No bots in this category"
              color: Qt.darker(Color.popups.text, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Try a different search term or category filter"
              color: Qt.darker(Color.popups.text, 1.8)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          // Main Bot List View
          ListView {
            id: botListView
            anchors.fill: parent
            model: root.filteredBots
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 0
            visible: root.filteredBots.length > 0

            ScrollBar.vertical: ScrollBar {
              id: customScrollBar
              policy: ScrollBar.AsNeeded
              width: Style.space(5)
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom

              contentItem: Rectangle {
                implicitWidth: Style.space(5)
                radius: width / 2
                color: customScrollBar.pressed
                  ? Color.accent
                  : (customScrollBar.hovered ? Qt.darker(Color.popups.text, 1.3) : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.2))
              }
            }

            delegate: Item {
              id: botItemDelegate
              required property var modelData
              required property int index

              width: botListView.width
              height: itemContainer.implicitHeight + Style.space(16)

              readonly property bool isCopied: root.copiedSlug === (modelData.slug || modelData.name)

              // Divider Line at top of item
              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)
              }

              // Item Background hover effect
              Rectangle {
                anchors.fill: parent
                anchors.topMargin: 1
                color: itemMouseArea.containsMouse
                  ? Style.hoverFillFor(Color.popups.text, Color.accent)
                  : "transparent"
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
              }

              // Content Row
              RowLayout {
                id: itemContainer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                // Left Column: Bot Name + Prompt Preview (2 lines)
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(3)

                  // Row: Bot Name & Category Badge
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    Text {
                      text: modelData.name || "Unnamed Bot"
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.maximumWidth: itemContainer.width - Style.space(110)
                    }

                    // Subtle category tag
                    Rectangle {
                      visible: !!modelData.category
                      height: Style.space(16)
                      implicitWidth: catTagText.implicitWidth + Style.space(8)
                      radius: height / 2
                      color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.06)

                      Text {
                        id: catTagText
                        anchors.centerIn: parent
                        text: modelData.category || ""
                        color: Qt.darker(Color.popups.text, 1.5)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption - 1
                        font.bold: false
                      }
                    }

                    Item { Layout.fillWidth: true }
                  }

                  // Prompt Preview Text (2 Lines max)
                  Text {
                    text: Model.cleanPreview(modelData.prompt)
                    color: Qt.darker(Color.popups.text, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    lineHeight: 1.15
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }
                }

                // Right Column: Copy Icon Button (Two overlapping documents)
                BorderSurface {
                  id: copyBtn
                  width: Style.space(32)
                  height: Style.space(32)
                  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                  Layout.alignment: Qt.AlignVCenter

                  readonly property bool isHovered: copyMouseArea.containsMouse
                  readonly property var borderSpecObj: Border.controlSpec(
                    botItemDelegate.isCopied ? "focus" : (isHovered ? "hover-cursor" : "normal"),
                    Color.popups.text,
                    Color.accent
                  )

                  color: botItemDelegate.isCopied
                    ? Style.selectedFillFor(Color.popups.text, Color.accent)
                    : Style.controlFill(false, isHovered, Color.popups.text, Color.accent)
                  borderSpec: borderSpecObj

                  // Copy Icon / Checkmark on copied
                  Text {
                    anchors.centerIn: parent
                    text: botItemDelegate.isCopied ? "󰄬" : "󰆏" // nf-md-check or nf-md-content_copy
                    color: botItemDelegate.isCopied
                      ? Color.accent
                      : (copyBtn.isHovered ? Color.popups.text : Qt.darker(Color.popups.text, 1.3))
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  MouseArea {
                    id: copyMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyBotPrompt(modelData)
                  }
                }
              }

              // Row click to copy
              MouseArea {
                id: itemMouseArea
                anchors.left: parent.left
                anchors.right: copyBtn.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyBotPrompt(modelData)
              }
            }
          }
        }

        // =====================================================================
        // SECTION 3: FOOTER (Bottom Reference & Data Source Link)
        // =====================================================================
        Item {
          id: footerSection
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(26)

          // Top divider for footer
          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)
          }

          // Centered Text: "omabot - data source"
          Row {
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
              text: "omabot —"
              color: Qt.darker(Color.popups.text, 1.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: sourceLinkText
              text: "data source"
              color: footerMouse.containsMouse ? Color.accent : Qt.darker(Color.popups.text, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.underline: footerMouse.containsMouse
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "󰌹" // nf-md-link
              color: footerMouse.containsMouse ? Color.accent : Qt.darker(Color.popups.text, 1.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption - 1
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            id: footerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openSourceUrl()
          }
        }
      }
    }
  }
}
