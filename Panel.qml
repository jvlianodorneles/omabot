import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Panel.qml - Power AI Bot Directory popup window for Omabot
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

  // Bot datasets and state
  property var allBots: []
  property var customBots: []
  property var favoritesList: []
  property var favoritesSet: ({})
  property var recentsList: []
  property var selectedBot: null
  property var editingBot: null

  property string searchQuery: ""
  property string activeScope: "all" // "all", "favorites", "recent", "custom"
  property string selectedCategory: "All"
  property string copiedSlug: ""
  property bool isSyncing: false

  readonly property var categories: Model.extractCategories(allBots, customBots)
  readonly property var filteredBots: Model.filterBots(allBots, customBots, searchQuery, activeScope, selectedCategory, favoritesSet, recentsList)
  
  readonly property string syncScriptPath: Qt.resolvedUrl("scripts/omabot-sync.py").toString().replace(/^file:\/\//, "")
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/omabot"
  readonly property string stateFilePath: stateDir + "/bots.json"
  readonly property string favoritesFilePath: stateDir + "/favorites.json"
  readonly property string recentsFilePath: stateDir + "/recents.json"
  readonly property string customBotsFilePath: stateDir + "/custom_bots.json"

  function open() {
    selectedBot = null
    editingBot = null
    controller.show()
    stateFile.reload()
    favoritesFile.reload()
    recentsFile.reload()
    customBotsFile.reload()
    searchFocusTimer.restart()
  }

  function close() {
    categoryPopup.close()
    selectedBot = null
    editingBot = null
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

  function openEditorForNew() {
    editingBot = {
      name: "",
      category: "Custom",
      integrations: [],
      prompt: "",
      slug: "",
      isNew: true,
      oldSlug: ""
    }
  }

  function openEditorForEdit(bot) {
    if (!bot) return
    var ints = []
    if (Array.isArray(bot.integrations)) {
      for (var i = 0; i < bot.integrations.length; i++) ints.push(bot.integrations[i])
    }
    editingBot = {
      name: bot.name || "",
      category: bot.category || "Custom",
      integrations: ints,
      prompt: bot.prompt || "",
      slug: bot.slug || "",
      isNew: false,
      oldSlug: bot.slug || bot.name || ""
    }
  }

  function openEditorForClone(bot) {
    if (!bot) return
    var ints = []
    if (Array.isArray(bot.integrations)) {
      for (var i = 0; i < bot.integrations.length; i++) ints.push(bot.integrations[i])
    }
    editingBot = {
      name: (bot.name || "Bot") + " (Custom)",
      category: bot.category || "Custom",
      integrations: ints,
      prompt: bot.prompt || "",
      slug: "",
      isNew: true,
      oldSlug: ""
    }
  }

  function saveEditorBot(name, category, prompt, integrations, oldSlug) {
    if (!name || !name.trim() || !prompt || !prompt.trim()) return
    var intStr = (integrations || []).join(", ")
    var cmd = ["python3", syncScriptPath, "add", name.trim(), "-c", (category || "Custom").trim(), "-p", prompt.trim(), "-i", intStr]
    if (oldSlug && oldSlug.trim()) {
      cmd.push("--old-slug")
      cmd.push(oldSlug.trim())
    }
    Quickshell.execDetached(cmd)

    editingBot = null
    activeScope = "custom"
    customBotsFile.reload()
  }

  function deleteCustomBot(slug) {
    if (!slug) return
    Quickshell.execDetached(["python3", syncScriptPath, "remove-custom", slug])
    selectedBot = null
    editingBot = null
    customBotsFile.reload()
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

  // --- Live state watchers ---
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

  // Delay focus to searchInput until after KeyboardPanel's 75ms focus prime
  // completes and the compositor has granted keyboard focus to the surface.
  Timer {
    id: searchFocusTimer
    interval: 100
    onTriggered: {
      if (root.opened && searchInput) {
        searchInput.forceActiveFocus()
        searchInput.selectAll()
      }
    }
  }

  // Native Popup Window
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth ? panel.fittedContentWidth(Style.space(480)) : Style.space(480)
    contentHeight: Style.space(560)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchInput.activeFocus || nameInputField.activeFocus || promptEditInput.activeFocus

      onCloseRequested: {
        if (root.editingBot) {
          root.editingBot = null
        } else if (root.selectedBot) {
          root.selectedBot = null
        } else {
          root.close()
        }
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.selectedBot !== null || root.editingBot !== null) return
        if (dy > 0) {
          // Down
          botListView.currentIndex = Math.min(botListView.count - 1, botListView.currentIndex + 1)
        } else if (dy < 0) {
          // Up
          if (botListView.currentIndex <= 0) {
            botListView.currentIndex = -1
            searchInput.forceActiveFocus()
            searchInput.selectAll()
          } else {
            botListView.currentIndex = botListView.currentIndex - 1
          }
        }
      }
      onActivateRequested: {
        if (root.selectedBot !== null || root.editingBot !== null) return
        if (botListView.currentIndex >= 0 && botListView.currentIndex < botListView.count) {
          root.selectedBot = root.filteredBots[botListView.currentIndex]
        }
      }
      onReturnRequested: {
        if (root.selectedBot !== null || root.editingBot !== null) return
        if (botListView.currentIndex >= 0 && botListView.currentIndex < botListView.count) {
          root.selectedBot = root.filteredBots[botListView.currentIndex]
        } else {
          searchInput.forceActiveFocus()
          searchInput.selectAll()
        }
      }
      onTextKey: function(t) {
        if (t === "/" || t === "s") {
          searchInput.forceActiveFocus()
          searchInput.selectAll()
        }
      }

      // Top-level container
      Item {
        anchors.fill: parent

        // =====================================================================
        // VIEW A: MAIN DIRECTORY LIST VIEW
        // =====================================================================
        Item {
          id: mainListView
          anchors.fill: parent
          visible: root.selectedBot === null && root.editingBot === null

          // --- SECTION 1: HEADER (Search Bar, New Bot Button & Filter Toolbar) ---
          Item {
            id: headerSection
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: searchRowContainer.height + filterToolbar.height + Style.space(14)

            // Search Row + "+ New Bot" Button
            RowLayout {
              id: searchRowContainer
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: Style.space(36)
              spacing: Style.space(8)

              // Search Bar Surface
              BorderSurface {
                Layout.fillWidth: true
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
                          root.close()
                          event.accepted = true
                        }
                      } else if (event.key === Qt.Key_Down) {
                        keyCatcher.forceActiveFocus()
                        if (botListView.count > 0 && botListView.currentIndex < 0) {
                          botListView.currentIndex = 0
                        }
                        event.accepted = true
                      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.filteredBots && root.filteredBots.length > 0) {
                          var targetIdx = (botListView.currentIndex >= 0 && botListView.currentIndex < root.filteredBots.length) ? botListView.currentIndex : 0
                          root.selectedBot = root.filteredBots[targetIdx]
                          event.accepted = true
                        }
                      }
                    }

                    Text {
                      anchors.fill: parent
                      visible: !searchInput.text && !searchInput.inputMethodComposing
                      text: "Search bots, prompts, tools..."
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

              // "+ New Bot" Button
              BorderSurface {
                height: Style.space(36)
                implicitWidth: newBtnContent.implicitWidth + Style.space(18)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                color: newBtnMouse.containsMouse ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)
                borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

                Row {
                  id: newBtnContent
                  anchors.centerIn: parent
                  spacing: Style.space(5)

                  Text {
                    text: "󰐕"
                    color: newBtnMouse.containsMouse ? Color.background : Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "New Bot"
                    color: newBtnMouse.containsMouse ? Color.background : Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: newBtnMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openEditorForNew()
                }
              }
            }

            // Filter Toolbar (Scope Pills on Left + Category Selector on Right)
            Item {
              id: filterToolbar
              anchors.top: searchRowContainer.bottom
              anchors.topMargin: Style.space(8)
              anchors.left: parent.left
              anchors.right: parent.right
              height: Style.space(26)
              z: 20

              // Left: Scope Tabs
              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                // "All" Pill
                Rectangle {
                  height: Style.space(24)
                  implicitWidth: allPillText.implicitWidth + Style.space(14)
                  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
                  color: root.activeScope === "all"
                    ? Style.selectedFillFor(Color.popups.text, Color.accent)
                    : (allPillMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent")
                  border.width: 1
                  border.color: root.activeScope === "all" ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12)

                  Text {
                    id: allPillText
                    anchors.centerIn: parent
                    text: "All"
                    color: root.activeScope === "all" ? Color.accent : Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: root.activeScope === "all"
                  }

                  MouseArea {
                    id: allPillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activeScope = "all"
                  }
                }

                // "⭐ Favorites" Pill
                Rectangle {
                  height: Style.space(24)
                  implicitWidth: favPillRow.implicitWidth + Style.space(12)
                  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
                  color: root.activeScope === "favorites"
                    ? Qt.rgba(0.96, 0.62, 0.04, 0.18)
                    : (favPillMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent")
                  border.width: 1
                  border.color: root.activeScope === "favorites" ? "#F59E0B" : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12)

                  Row {
                    id: favPillRow
                    anchors.centerIn: parent
                    spacing: Style.space(4)

                    Text {
                      text: "⭐ Favorites"
                      color: root.activeScope === "favorites" ? "#F59E0B" : Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: root.activeScope === "favorites"
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      visible: root.favoritesList.length > 0
                      text: "(" + root.favoritesList.length + ")"
                      color: root.activeScope === "favorites" ? "#F59E0B" : Qt.darker(Color.popups.text, 1.6)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption - 1
                      font.bold: true
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  MouseArea {
                    id: favPillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activeScope = "favorites"
                  }
                }

                // "🕒 History" Pill
                Rectangle {
                  height: Style.space(24)
                  implicitWidth: histPillRow.implicitWidth + Style.space(12)
                  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
                  color: root.activeScope === "recent"
                    ? Style.selectedFillFor(Color.popups.text, Color.accent)
                    : (histPillMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent")
                  border.width: 1
                  border.color: root.activeScope === "recent" ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12)

                  Row {
                    id: histPillRow
                    anchors.centerIn: parent
                    spacing: Style.space(4)

                    Text {
                      text: "🕒 History"
                      color: root.activeScope === "recent" ? Color.accent : Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: root.activeScope === "recent"
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      visible: root.recentsList.length > 0
                      text: "(" + root.recentsList.length + ")"
                      color: root.activeScope === "recent" ? Color.accent : Qt.darker(Color.popups.text, 1.6)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption - 1
                      font.bold: true
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  MouseArea {
                    id: histPillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activeScope = "recent"
                  }
                }

                // "📁 Custom" Pill
                Rectangle {
                  height: Style.space(24)
                  implicitWidth: customPillRow.implicitWidth + Style.space(12)
                  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
                  color: root.activeScope === "custom"
                    ? Style.selectedFillFor(Color.popups.text, Color.accent)
                    : (customPillMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent")
                  border.width: 1
                  border.color: root.activeScope === "custom" ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12)

                  Row {
                    id: customPillRow
                    anchors.centerIn: parent
                    spacing: Style.space(4)

                    Text {
                      text: "📁 Custom"
                      color: root.activeScope === "custom" ? Color.accent : Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: root.activeScope === "custom"
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      visible: root.customBots.length > 0
                      text: "(" + root.customBots.length + ")"
                      color: root.activeScope === "custom" ? Color.accent : Qt.darker(Color.popups.text, 1.6)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption - 1
                      font.bold: true
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  MouseArea {
                    id: customPillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activeScope = "custom"
                  }
                }
              }

              // Right: Category Dropdown
              BorderSurface {
                id: categorySelector
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
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

                Row {
                  id: catContentRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Text {
                    text: root.selectedCategory === "All" ? "Category: All" : root.selectedCategory
                    color: root.selectedCategory !== "All" ? Model.categoryColor(root.selectedCategory, Color.accent) : Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: root.selectedCategory !== "All"
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
                  width: Style.space(160)
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
                          color: modelData === root.selectedCategory ? Color.accent : Model.categoryColor(modelData, Color.popups.text)
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
              spacing: Style.space(10)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.activeScope === "favorites" ? "⭐" : (root.activeScope === "recent" ? "🕒" : (root.activeScope === "custom" ? "📁" : "󰚩"))
                color: Qt.darker(Color.popups.text, 1.8)
                font.family: Style.font.family
                font.pixelSize: Style.space(36)
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                  if (root.searchQuery) return "No bots found for '" + root.searchQuery + "'"
                  if (root.activeScope === "favorites") return "No favorite bots yet"
                  if (root.activeScope === "recent") return "No recently copied bots"
                  if (root.activeScope === "custom") return "No custom bots created yet"
                  return "No bots in this category"
                }
                color: Qt.darker(Color.popups.text, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }

              // Quick Action to Create Custom Bot when empty
              BorderSurface {
                visible: root.activeScope === "custom"
                anchors.horizontalCenter: parent.horizontalCenter
                height: Style.space(32)
                implicitWidth: emptyCreateRow.implicitWidth + Style.space(20)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                color: emptyCreateMouse.containsMouse ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)

                Row {
                  id: emptyCreateRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Text {
                    text: "󰐕"
                    color: emptyCreateMouse.containsMouse ? Color.background : Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: "Create Your First Custom Bot"
                    color: emptyCreateMouse.containsMouse ? Color.background : Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  id: emptyCreateMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openEditorForNew()
                }
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
                    : (rowHoverArea.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent")
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

                  // Left Column: Bot Details (Title on line 1, Badges on line 2, Preview on line 3)
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(4)

                    // Line 1: Star + Bot Name + Custom Indicator
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

                      // Bot Name (Full Width, elides properly)
                      Text {
                        text: modelData.name || "Unnamed Bot"
                        color: Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                      }

                      // Custom Badge
                      Rectangle {
                        visible: !!modelData.isCustom
                        height: Style.space(16)
                        implicitWidth: customTagText.implicitWidth + Style.space(8)
                        radius: height / 2
                        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)

                        Text {
                          id: customTagText
                          anchors.centerIn: parent
                          text: "Custom"
                          color: Color.accent
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption - 2
                          font.bold: true
                        }
                      }
                    }

                    // Line 2: Category Tag + Integration Badges with Icons
                    Flow {
                      Layout.fillWidth: true
                      spacing: Style.space(4)
                      visible: !!modelData.category || (modelData.integrations && modelData.integrations.length > 0)

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

                      // Integration Badges Preview with Tool Icons
                      Repeater {
                        model: modelData.integrations || []
                        delegate: Rectangle {
                          height: Style.space(16)
                          implicitWidth: toolTagRow.implicitWidth + Style.space(8)
                          radius: height / 2
                          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.09)

                          Row {
                            id: toolTagRow
                            anchors.centerIn: parent
                            spacing: Style.space(3)

                            Text {
                              text: Model.toolIcon(modelData)
                              color: Color.accent
                              font.family: Style.font.family
                              font.pixelSize: Style.font.caption - 1
                              anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                              text: modelData
                              color: Color.accent
                              font.family: Style.font.family
                              font.pixelSize: Style.font.caption - 2
                              font.bold: true
                              anchors.verticalCenter: parent.verticalCenter
                            }
                          }
                        }
                      }
                    }

                    // Line 3: Prompt Preview (2 lines max)
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
                  id: rowHoverArea
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

        // =====================================================================
        // VIEW B: FULL PROMPT DETAIL VIEW / SHEET
        // =====================================================================
        Item {
          id: detailView
          anchors.fill: parent
          visible: root.selectedBot !== null && root.editingBot === null

          readonly property var bot: root.selectedBot || ({})
          readonly property string botSlug: bot.slug || bot.name || ""
          readonly property bool isCopied: root.copiedSlug === botSlug
          readonly property bool isFav: !!root.favoritesSet[botSlug]
          readonly property bool isCustomBot: !!bot.isCustom

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
                    Layout.maximumWidth: detailHeader.width - Style.space(160)
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

              // Custom Action: Edit / Fork / Clone
              BorderSurface {
                width: Style.space(32)
                height: Style.space(32)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                color: editActionMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
                borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

                Text {
                  anchors.centerIn: parent
                  text: detailView.isCustomBot ? "󰏫" : "󰑈" // Edit pencil or Clone/Fork icon
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: editActionMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (detailView.isCustomBot) {
                      root.openEditorForEdit(detailView.bot)
                    } else {
                      root.openEditorForClone(detailView.bot)
                    }
                  }
                }
              }

              // Custom Action: Delete (Only if Custom Bot)
              BorderSurface {
                visible: detailView.isCustomBot
                width: Style.space(32)
                height: Style.space(32)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                color: delActionMouse.containsMouse ? Qt.rgba(0.95, 0.25, 0.25, 0.2) : "transparent"
                borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

                Text {
                  anchors.centerIn: parent
                  text: "󰆴" // nf-md-delete
                  color: delActionMouse.containsMouse ? "#EF4444" : Qt.darker(Color.popups.text, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: delActionMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.deleteCustomBot(detailView.botSlug)
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

          // --- Integrations Row with Tool Icons ---
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
                height: Style.space(22)
                implicitWidth: intDetailRow.implicitWidth + Style.space(14)
                radius: height / 2
                color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
                border.width: 1
                border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)

                Row {
                  id: intDetailRow
                  anchors.centerIn: parent
                  spacing: Style.space(5)

                  Text {
                    text: Model.toolIcon(modelData)
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    text: modelData
                    color: Color.accent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption - 1
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }
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

        // =====================================================================
        // VIEW C: CREATE / EDIT CUSTOM BOT FORM VIEW
        // =====================================================================
        Item {
          id: editorView
          anchors.fill: parent
          visible: root.editingBot !== null

          readonly property var editData: root.editingBot || ({})
          property string formName: editData.name || ""
          property string formCategory: editData.category || "Custom"
          property var formIntegrations: editData.integrations || []
          property string formPrompt: editData.prompt || ""

          onVisibleChanged: {
            if (visible && root.editingBot) {
              formName = root.editingBot.name || ""
              formCategory = root.editingBot.category || "Custom"
              formIntegrations = (root.editingBot.integrations || []).slice()
              formPrompt = root.editingBot.prompt || ""
              Qt.callLater(function() {
                if (nameInputField) nameInputField.forceActiveFocus()
              })
            }
          }

          function toggleFormIntegration(toolName) {
            var arr = formIntegrations.slice()
            var idx = arr.indexOf(toolName)
            if (idx !== -1) arr.splice(idx, 1)
            else arr.push(toolName)
            formIntegrations = arr
          }

          // --- Editor Header ---
          Item {
            id: editorHeader
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.space(48)

            RowLayout {
              anchors.fill: parent
              spacing: Style.space(8)

              // Back button
              BorderSurface {
                width: Style.space(32)
                height: Style.space(32)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                color: editorBackMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
                borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

                Text {
                  anchors.centerIn: parent
                  text: "󰁍" // nf-md-arrow_left
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: editorBackMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.editingBot = null
                }
              }

              Text {
                text: editorView.editData.isNew ? "Create Custom Bot" : "Edit Custom Bot"
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                Layout.fillWidth: true
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

          // --- Editor Form Body (Scrollable) ---
          Flickable {
            id: editorFlickable
            anchors.top: editorHeader.bottom
            anchors.bottom: editorFooter.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Style.space(8)
            anchors.bottomMargin: Style.space(8)
            contentWidth: width
            contentHeight: formColumn.implicitHeight + Style.space(16)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
              policy: ScrollBar.AsNeeded
              width: Style.space(4)
              anchors.right: parent.right
            }

            ColumnLayout {
              id: formColumn
              width: editorFlickable.width - Style.space(8)
              spacing: Style.space(12)

              // 1. Bot Name
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(4)

                Text {
                  text: "BOT NAME *"
                  color: Qt.darker(Color.popups.text, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption - 1
                  font.bold: true
                  font.letterSpacing: 0.5
                }

                BorderSurface {
                  Layout.fillWidth: true
                  height: Style.space(34)
                  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 5
                  color: Style.controlFill(nameInputField.activeFocus, false, Color.popups.text, Color.accent)
                  borderSpec: Border.controlSpec(nameInputField.activeFocus ? "focus" : "normal", Color.popups.text, Color.accent)

                  TextInput {
                    id: nameInputField
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    verticalAlignment: Text.AlignVCenter
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    text: editorView.formName
                    selectByMouse: true
                    onTextChanged: editorView.formName = text

                    Text {
                      anchors.fill: parent
                      visible: !nameInputField.text && !nameInputField.inputMethodComposing
                      text: "e.g. Git Commit Formatter"
                      color: Qt.darker(Color.popups.text, 1.8)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      verticalAlignment: Text.AlignVCenter
                    }
                  }
                }
              }

              // 2. Category Selector Chips
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(4)

                Text {
                  text: "CATEGORY"
                  color: Qt.darker(Color.popups.text, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption - 1
                  font.bold: true
                  font.letterSpacing: 0.5
                }

                Flow {
                  Layout.fillWidth: true
                  spacing: Style.space(5)

                  Repeater {
                    model: ["Custom", "Coding", "Productivity", "Marketing", "Writing", "Ops", "Sales", "Success", "Personal"]
                    delegate: Rectangle {
                      height: Style.space(22)
                      implicitWidth: catChipText.implicitWidth + Style.space(14)
                      radius: height / 2
                      color: editorView.formCategory === modelData
                        ? Style.selectedFillFor(Color.popups.text, Color.accent)
                        : (catChipMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent")
                      border.width: 1
                      border.color: editorView.formCategory === modelData ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.15)

                      Text {
                        id: catChipText
                        anchors.centerIn: parent
                        text: modelData
                        color: editorView.formCategory === modelData ? Color.accent : Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption - 1
                        font.bold: editorView.formCategory === modelData
                      }

                      MouseArea {
                        id: catChipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: editorView.formCategory = modelData
                      }
                    }
                  }
                }
              }

              // 3. Integrations / Tools Chips
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(4)

                Text {
                  text: "INTEGRATIONS / TOOLS"
                  color: Qt.darker(Color.popups.text, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption - 1
                  font.bold: true
                  font.letterSpacing: 0.5
                }

                Flow {
                  Layout.fillWidth: true
                  spacing: Style.space(5)

                  Repeater {
                    model: ["GitHub", "Slack", "Gmail", "Figma", "Notion", "Google Calendar", "Google Sheets", "Discord", "Salesforce", "Cursor", "Web Search"]
                    delegate: Rectangle {
                      readonly property bool isSelected: editorView.formIntegrations.indexOf(modelData) !== -1

                      height: Style.space(22)
                      implicitWidth: toolChipRow.implicitWidth + Style.space(12)
                      radius: height / 2
                      color: isSelected
                        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                        : (toolChipMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent")
                      border.width: 1
                      border.color: isSelected ? Color.accent : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.15)

                      Row {
                        id: toolChipRow
                        anchors.centerIn: parent
                        spacing: Style.space(4)

                        Text {
                          text: Model.toolIcon(modelData)
                          color: isSelected ? Color.accent : Qt.darker(Color.popups.text, 1.3)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          text: modelData
                          color: isSelected ? Color.accent : Color.popups.text
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption - 1
                          font.bold: isSelected
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }

                      MouseArea {
                        id: toolChipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: editorView.toggleFormIntegration(modelData)
                      }
                    }
                  }
                }
              }

              // 4. System Prompt Text Area
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(4)

                Text {
                  text: "SYSTEM PROMPT *"
                  color: Qt.darker(Color.popups.text, 1.5)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption - 1
                  font.bold: true
                  font.letterSpacing: 0.5
                }

                BorderSurface {
                  Layout.fillWidth: true
                  height: Style.space(160)
                  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                  color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.03)
                  borderSpec: Border.controlSpec(promptEditInput.activeFocus ? "focus" : "normal", Color.popups.text, Color.accent)

                  Flickable {
                    id: promptEditFlickable
                    anchors.fill: parent
                    anchors.margins: Style.space(8)
                    contentWidth: width
                    contentHeight: promptEditInput.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                      policy: ScrollBar.AsNeeded
                      width: Style.space(4)
                      anchors.right: parent.right
                    }

                    TextEdit {
                      id: promptEditInput
                      width: promptEditFlickable.width - Style.space(8)
                      text: editorView.formPrompt
                      color: Color.popups.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      wrapMode: Text.WordWrap
                      selectByMouse: true
                      selectionColor: Style.selectionFillFor(Color.popups.text, Color.accent)
                      selectedTextColor: Color.popups.text
                      onTextChanged: editorView.formPrompt = text

                      Text {
                        anchors.fill: parent
                        visible: !promptEditInput.text && !promptEditInput.inputMethodComposing
                        text: "Enter your AI bot system prompt instructions here..."
                        color: Qt.darker(Color.popups.text, 1.8)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        wrapMode: Text.WordWrap
                      }
                    }
                  }
                }
              }
            }
          }

          // --- Editor Action Footer ---
          Item {
            id: editorFooter
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Style.space(40)

            RowLayout {
              anchors.fill: parent
              spacing: Style.space(8)

              // Cancel Button
              BorderSurface {
                Layout.fillWidth: true
                height: Style.space(34)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                color: cancelMouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.accent) : "transparent"
                borderSpec: Border.controlSpec("normal", Color.popups.text, Color.accent)

                Text {
                  anchors.centerIn: parent
                  text: "Cancel"
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                MouseArea {
                  id: cancelMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.editingBot = null
                }
              }

              // Save Button
              BorderSurface {
                readonly property bool isValid: editorView.formName.trim().length > 0 && editorView.formPrompt.trim().length > 0

                Layout.fillWidth: true
                height: Style.space(34)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius : 6
                color: isValid
                  ? (saveMouse.containsMouse ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.9))
                  : Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)

              Row {
                anchors.centerIn: parent
                spacing: Style.space(6)

                Text {
                  text: "󰄬" // nf-md-check
                  color: parent.parent.isValid ? Color.background : Qt.darker(Color.popups.text, 1.8)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: editorView.editData.isNew ? "Save Bot" : "Update Bot"
                  color: parent.parent.isValid ? Color.background : Qt.darker(Color.popups.text, 1.8)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: saveMouse
                anchors.fill: parent
                enabled: parent.isValid
                hoverEnabled: parent.isValid
                cursorShape: parent.isValid ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  root.saveEditorBot(
                    editorView.formName,
                    editorView.formCategory,
                    editorView.formPrompt,
                    editorView.formIntegrations,
                    editorView.editData.oldSlug
                  )
                }
              }
            }
          }
        }
      }
    }
  }
}
}
