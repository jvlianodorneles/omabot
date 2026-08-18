import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// BarWidget.qml - Status Bar Widget & Popup Directory for Omabot
BarWidget {
  id: root
  moduleName: "dorneles.omabot"

  readonly property bool showLabelSetting: setting("showLabel", false)
  readonly property int syncIntervalHoursSetting: Number(setting("syncIntervalHours", 12))
  readonly property string syncScriptPath: Qt.resolvedUrl("scripts/omabot-sync.py").toString().replace(/^file:\/\//, "")
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/omabot"
  readonly property string stateFilePath: stateDir + "/bots.json"
  readonly property string favoritesFilePath: stateDir + "/favorites.json"
  readonly property string recentsFilePath: stateDir + "/recents.json"
  readonly property string customBotsFilePath: stateDir + "/custom_bots.json"

  // Bot dataset & filter state
  property var allBots: []
  property var customBots: []
  property var favoritesList: []
  property var favoritesSet: ({})
  property var recentsList: []
  property var selectedBot: null

  property string searchQuery: ""
  property string selectedCategory: "All"
  property string copiedSlug: ""
  property bool isSyncing: false

  readonly property var categories: Model.extractCategories(allBots, customBots, favoritesList, recentsList)
  readonly property var filteredBots: Model.filterBots(allBots, customBots, searchQuery, selectedCategory, favoritesSet, recentsList)

  function openPopup() {
    botPopup.open = true
  }

  function closePopup() {
    botPopup.open = false
  }

  function togglePopup() {
    botPopup.open = !botPopup.open
  }

  function triggerSync() {
    if (syncProcess.running) return
    isSyncing = true
    syncProcess.command = ["python3", syncScriptPath, "sync"]
    syncProcess.running = true
  }

  function toggleFavorite(slug) {
    if (!slug) return
    var set = {}
    for (var k in root.favoritesSet) set[k] = root.favoritesSet[k]
    
    var list = []
    if (set[slug]) {
      delete set[slug]
    } else {
      set[slug] = true
    }
    for (var s in set) if (set[s]) list.push(s)
    
    root.favoritesSet = set
    root.favoritesList = list

    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "fav", slug])
    }
  }

  function recordRecent(slug) {
    if (!slug) return
    var list = root.recentsList.slice()
    var idx = list.indexOf(slug)
    if (idx !== -1) list.splice(idx, 1)
    list.unshift(slug)
    root.recentsList = list.slice(0, 20)
  }

  function copyBotPrompt(bot) {
    if (!bot || !bot.prompt) return
    var slug = bot.slug || bot.name
    copiedSlug = slug
    recordRecent(slug)
    
    if (syncScriptPath !== "") {
      Quickshell.execDetached(["python3", syncScriptPath, "copy", slug])
    } else {
      Quickshell.execDetached(["wl-copy", bot.prompt])
    }

    copiedTimer.restart()
  }

  function openSourceUrl(url) {
    var target = url || "https://github.com/elie222/botdirectory.ai"
    Quickshell.execDetached(["xdg-open", target])
  }

  // --- Live State File Watchers ---
  property FileView stateFile: FileView {
    path: root.stateFilePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var parsed = Model.parseBots(text())
      if (parsed && parsed.length > 0) root.allBots = parsed
    }
  }

  property FileView favoritesFile: FileView {
    path: root.favoritesFilePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var arr = JSON.parse(text())
        if (Array.isArray(arr)) {
          root.favoritesList = arr
          var set = {}
          for (var i = 0; i < arr.length; i++) set[arr[i]] = true
          root.favoritesSet = set
        }
      } catch (e) {}
    }
  }

  property FileView recentsFile: FileView {
    path: root.recentsFilePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var arr = JSON.parse(text())
        if (Array.isArray(arr)) root.recentsList = arr
      } catch (e) {}
    }
  }

  property FileView customBotsFile: FileView {
    path: root.customBotsFilePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var arr = JSON.parse(text())
        if (Array.isArray(arr)) root.customBots = arr
      } catch (e) {}
    }
  }

  property FileView builtinFile: FileView {
    path: Qt.resolvedUrl("data/bots.json").toString().replace(/^file:\/\//, "")
    printErrors: false
    onLoaded: {
      if (!root.allBots || root.allBots.length === 0) {
        var parsed = Model.parseBots(text())
        if (parsed && parsed.length > 0) root.allBots = parsed
      }
    }
  }

  Component.onCompleted: {
    stateFile.reload()
    favoritesFile.reload()
    recentsFile.reload()
    customBotsFile.reload()
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
    onTriggered: root.copiedSlug = ""
  }

  // Periodic automatic background synchronizer
  Timer {
    id: autoSyncTimer
    interval: Math.max(1, root.syncIntervalHoursSetting) * 3600 * 1000
    running: root.syncIntervalHoursSetting > 0
    repeat: true
    onTriggered: root.triggerSync()
  }

  // IPC Handler for Hyprland keybindings, Omarchy menu, and CLI control
  IpcHandler {
    target: "dorneles.omabot"

    function open(): void { root.openPopup() }
    function close(): void { root.closePopup() }
    function show(): void { root.openPopup() }
    function hide(): void { root.closePopup() }
    function toggle(): void { root.togglePopup() }
    function refresh(): void { root.triggerSync() }
    function sync(): void { root.triggerSync() }
    function search(query: string): void {
      root.openPopup()
      root.searchQuery = query
    }
    function copy(slug: string): void {
      var bots = (root.allBots || []).concat(root.customBots || [])
      for (var i = 0; i < bots.length; i++) {
        if (bots[i].slug === slug || bots[i].name === slug) {
          root.copyBotPrompt(bots[i])
          break
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
    active: botPopup.open
    dimmed: !botPopup.open
    useActiveColor: true
    activeColor: bar ? bar.urgent : Color.urgent
    fontSize: Style.font.body
    horizontalMargin: 8
    verticalPadding: 2
    tooltipText: "Omabot • AI Bot & Prompt Directory\n──────────────────────────────\n• Left-click: Open Bot Directory\n• Middle-click: Sync Latest Bots"

    onPressed: function(btn) {
      if (btn === Qt.MiddleButton) {
        root.triggerSync()
      } else {
        root.togglePopup()
      }
    }
  }

  // ===========================================================================
  // POPUP CARD (Native Quickshell Popup Window)
  // ===========================================================================
  PopupCard {
    id: botPopup
    anchorItem: button
    bar: root.bar
    contentWidth: fittedContentWidth(Style.space(430))
    contentHeight: Style.space(530)
    open: false
    triggerMode: "click"

    onOpenChanged: {
      if (open) {
        root.selectedBot = null
        root.stateFile.reload()
        root.favoritesFile.reload()
        root.recentsFile.reload()
        root.customBotsFile.reload()
        Qt.callLater(function() {
          if (searchInput) {
            searchInput.forceActiveFocus()
            searchInput.selectAll()
          }
        })
      } else {
        categoryPopup.close()
        root.selectedBot = null
      }
    }

    Item {
      id: popupMainContainer
      anchors.fill: parent

      // -----------------------------------------------------------------------
      // VIEW A: MAIN DIRECTORY LIST VIEW
      // -----------------------------------------------------------------------
      Item {
        id: mainListView
        anchors.fill: parent
        visible: root.selectedBot === null

        // --- SECTION 1: HEADER (Search Bar & Category Filter) ---
        Item {
          id: headerSection
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: searchContainer.height + categoryFilterRow.height + Style.space(14)

          // 1. Search Bar (Top Element)
          BorderSurface {
            id: searchContainer
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.space(36)
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6

            readonly property bool isFocused: searchInput.activeFocus
            readonly property bool isHot: searchMouse.containsMouse
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

              Text {
                text: "󰍉" // nf-md-magnify
                color: Qt.darker(Color.popups.text, 1.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                Layout.alignment: Qt.AlignVCenter
              }

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

                onTextChanged: root.searchQuery = text

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    if (text !== "") {
                      text = ""
                      event.accepted = true
                    } else {
                      botPopup.close()
                      event.accepted = true
                    }
                  } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    botListView.forceActiveFocus()
                    if (botListView.count > 0 && botListView.currentIndex < 0) {
                      botListView.currentIndex = 0
                    }
                    event.accepted = true
                  }
                }

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

          // 2. Category Filter (Bottom Element)
          Row {
            id: categoryFilterRow
            anchors.top: searchContainer.bottom
            anchors.topMargin: Style.space(8)
            anchors.right: parent.right
            spacing: Style.space(8)
            z: 20

            Text {
              text: "CATEGORIES"
              color: Qt.darker(Color.popups.text, 1.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
              anchors.verticalCenter: parent.verticalCenter
            }

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
                  color: root.selectedCategory.indexOf("⭐") !== -1 ? "#F59E0B" : Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }

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
                  if (categoryPopup.opened) categoryPopup.close()
                  else categoryPopup.open()
                }
              }

              Popup {
                id: categoryPopup
                x: categorySelector.width - width
                y: categorySelector.height + Style.space(4)
                width: Style.space(170)
                implicitHeight: Math.min(Style.space(260), catListView.contentHeight + Style.space(8))
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

        // --- SECTION 2: RESULTS LIST ---
        Item {
          id: resultsSection
          anchors.top: headerSection.bottom
          anchors.bottom: footerSection.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.space(4)
          anchors.bottomMargin: Style.space(6)
          clip: true

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

          ListView {
            id: botListView
            anchors.fill: parent
            model: root.filteredBots
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: 0
            visible: root.filteredBots.length > 0
            currentIndex: -1

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Down || event.text === "j") {
                botListView.currentIndex = Math.min(botListView.count - 1, botListView.currentIndex + 1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up || event.text === "k") {
                if (botListView.currentIndex <= 0) {
                  botListView.currentIndex = -1
                  searchInput.forceActiveFocus()
                } else {
                  botListView.currentIndex = botListView.currentIndex - 1
                }
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (botListView.currentIndex >= 0 && botListView.currentIndex < botListView.count) {
                  root.selectedBot = root.filteredBots[botListView.currentIndex]
                }
                event.accepted = true
              } else if (event.text === "/") {
                searchInput.forceActiveFocus()
                searchInput.selectAll()
                event.accepted = true
              }
            }

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

              readonly property string itemSlug: modelData.slug || modelData.name
              readonly property bool isCopied: root.copiedSlug === itemSlug
              readonly property bool isFav: !!root.favoritesSet[itemSlug]
              readonly property bool isCurrent: botListView.currentIndex === index

              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)
              }

              Rectangle {
                anchors.fill: parent
                anchors.topMargin: 1
                color: isCurrent
                  ? Style.selectedFillFor(Color.popups.text, Color.accent)
                  : (itemMouseArea.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent")
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
              }

              RowLayout {
                id: itemContainer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                // Left Column: Bot Details
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(3)

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    // Star / Favorite Icon Indicator
                    Text {
                      text: botItemDelegate.isFav ? "󰓏" : "󰓎" // star filled / outline
                      color: botItemDelegate.isFav ? "#F59E0B" : Qt.darker(Color.popups.text, 1.8)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      Layout.alignment: Qt.AlignVCenter

                      MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Style.space(4)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleFavorite(botItemDelegate.itemSlug)
                      }
                    }

                    // Bot Name
                    Text {
                      text: modelData.name || "Unnamed Bot"
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.maximumWidth: itemContainer.width - Style.space(120)
                    }

                    // Category Tag
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
                        color: Model.categoryColor(modelData.category, Qt.darker(Color.popups.text, 1.4))
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption - 1
                        font.bold: true
                      }
                    }

                    Item { Layout.fillWidth: true }
                  }

                  // Prompt Preview (2 lines max)
                  Text {
                    text: Model.cleanPreview(modelData.prompt)
                    color: Qt.darker(Color.popups.text, 1.4)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                  }
                }

                // Right Column: 1-Click Copy Icon Button
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

                  Text {
                    anchors.centerIn: parent
                    text: botItemDelegate.isCopied ? "󰄬" : "󰆏" // checkmark or copy icon
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

              // Row click opens full detail view
              MouseArea {
                id: itemMouseArea
                anchors.fill: parent
                anchors.rightMargin: Style.space(42)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  botListView.currentIndex = index
                  root.selectedBot = modelData
                }
              }
            }
          }
        }

        // --- SECTION 3: FOOTER ---
        Item {
          id: footerSection
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(26)

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)
          }

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

      // -----------------------------------------------------------------------
      // VIEW B: FULL PROMPT DETAIL VIEW / SHEET
      // -----------------------------------------------------------------------
      Item {
        id: detailView
        anchors.fill: parent
        visible: root.selectedBot !== null

        readonly property var bot: root.selectedBot || ({})
        readonly property string botSlug: bot.slug || bot.name || ""
        readonly property bool isCopied: root.copiedSlug === botSlug
        readonly property bool isFav: !!root.favoritesSet[botSlug]

        // --- Detail Header ---
        Item {
          id: detailHeader
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(56)

          RowLayout {
            anchors.fill: parent
            spacing: Style.space(8)

            // Back button
            BorderSurface {
              width: Style.space(32)
              height: Style.space(32)
              radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
              color: backMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
              borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

              Text {
                anchors.centerIn: parent
                text: "󰁍" // nf-md-arrow_left
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedBot = null
              }
            }

            // Title and Meta Info
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(6)

                Text {
                  text: detailView.bot.name || ""
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                  Layout.maximumWidth: detailHeader.width - Style.space(120)
                }

                Rectangle {
                  visible: !!detailView.bot.category
                  height: Style.space(16)
                  implicitWidth: detailCatText.implicitWidth + Style.space(8)
                  radius: height / 2
                  color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)

                  Text {
                    id: detailCatText
                    anchors.centerIn: parent
                    text: detailView.bot.category || ""
                    color: Model.categoryColor(detailView.bot.category, Color.accent)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption - 1
                    font.bold: true
                  }
                }

                Item { Layout.fillWidth: true }
              }

              Text {
                visible: !!detailView.bot.contributor
                text: "Created by @" + (detailView.bot.contributor || "")
                color: Qt.darker(Color.popups.text, 1.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight

                MouseArea {
                  anchors.fill: parent
                  enabled: !!detailView.bot.contributor_url
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (detailView.bot.contributor_url) root.openSourceUrl(detailView.bot.contributor_url)
                }
              }
            }

            // Favorite Star Button in Header
            BorderSurface {
              width: Style.space(32)
              height: Style.space(32)
              radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
              color: detailFavMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
              borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

              Text {
                anchors.centerIn: parent
                text: detailView.isFav ? "󰓏" : "󰓎"
                color: detailView.isFav ? "#F59E0B" : Qt.darker(Color.popups.text, 1.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: detailFavMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleFavorite(detailView.botSlug)
              }
            }
          }

          Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)
          }
        }

        // --- Integrations Row (if any) ---
        Flow {
          id: integrationsFlow
          anchors.top: detailHeader.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.space(8)
          spacing: Style.space(6)
          visible: !!(detailView.bot && detailView.bot.integrations && detailView.bot.integrations.length > 0)

          Repeater {
            model: detailView.bot.integrations || []
            delegate: Rectangle {
              height: Style.space(20)
              implicitWidth: intLabel.implicitWidth + Style.space(12)
              radius: height / 2
              color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
              border.width: 1
              border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)

              Text {
                id: intLabel
                anchors.centerIn: parent
                text: "⚡ " + modelData
                color: Color.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.caption - 1
                font.bold: true
              }
            }
          }
        }

        // --- Scrollable Full Prompt Body ---
        BorderSurface {
          id: promptCard
          anchors.top: integrationsFlow.visible ? integrationsFlow.bottom : detailHeader.bottom
          anchors.bottom: detailActionFooter.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: Style.space(8)
          anchors.bottomMargin: Style.space(8)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
          color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.03)
          borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

          Flickable {
            id: promptFlickable
            anchors.fill: parent
            anchors.margins: Style.space(10)
            contentWidth: width
            contentHeight: fullPromptText.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
              policy: ScrollBar.AsNeeded
              width: Style.space(4)
              anchors.right: parent.right
            }

            TextEdit {
              id: fullPromptText
              width: promptFlickable.width - Style.space(8)
              text: detailView.bot.prompt || ""
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              readOnly: true
              selectByMouse: true
              selectionColor: Style.selectionFillFor(Color.popups.text, Color.accent)
              selectedTextColor: Color.popups.text
            }
          }
        }

        // --- Detail Action Footer ---
        Item {
          id: detailActionFooter
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(38)

          RowLayout {
            anchors.fill: parent
            spacing: Style.space(8)

            // Primary "Copy Prompt" Button
            BorderSurface {
              Layout.fillWidth: true
              height: Style.space(34)
              radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
              color: detailView.isCopied
                ? Style.selectedFillFor(Color.popups.text, Color.accent)
                : (copyActionMouse.containsMouse ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.9))

              Row {
                anchors.centerIn: parent
                spacing: Style.space(6)

                Text {
                  text: detailView.isCopied ? "󰄬" : "󰆏"
                  color: detailView.isCopied ? Color.accent : Color.background
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: detailView.isCopied ? "Copied to Clipboard!" : "Copy Prompt"
                  color: detailView.isCopied ? Color.accent : Color.background
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: copyActionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyBotPrompt(detailView.bot)
              }
            }
          }
        }
      }
    }
  }
}
