import QtQuick
import qs.Ui
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property bool opened: controller.open
  property int menuIndex: 0
  property bool switchOpen: false
  property string switchMode: "record"
  function openSwitch(mode) { switchMode = mode; switchOpen = true }
  property bool localeOpen: false
  property string localeScope: "user"
  function openLocale(scope) { localeScope = scope; localeOpen = true }
  function closeLocale() { localeOpen = false; selectMenu(languages.layouts.length + (localeScope === "user" ? 3 : 4)) }
  function closeSwitch() { switchOpen = false; selectMenu(languages.layouts.length + (switchMode === "record" ? 1 : 2)) }

  function selectMenu(index) {
    if (languages.dragging && index !== languages.selectedIndex) return
    menuIndex = Math.max(0, Math.min(index, languages.layouts.length + 4))
    languages.cursorActive = true
    if (menuIndex < languages.layouts.length) languages.selectedIndex = menuIndex
    keyCatcher.forceActiveFocus()
    Qt.callLater(function() {
      var target = root.menuIndex < languages.layouts.length ? languages.rowAt(root.menuIndex)
        : root.menuIndex === languages.layouts.length ? languages.addItem
        : root.menuIndex === languages.layouts.length + 1 ? recordAction
        : root.menuIndex === languages.layouts.length + 2 ? listAction
        : root.menuIndex === languages.layouts.length + 3 ? localeAction : systemLocaleAction
      if (!target) return
      var y = target.mapToItem(content, 0, 0).y
      if (y < viewport.contentY) viewport.contentY = y
      else if (y + target.height > viewport.contentY + viewport.height)
        viewport.contentY = Math.max(0, y + target.height - viewport.height)
    })
  }

  function open(payloadJson) { menuIndex = 0; controller.show(); languages.reload(); localeModel.reload(); selectMenu(0) }
  function close() { languages.cancelDrag(); languages.addOpen = false; switchOpen = false; localeOpen = false; controller.hide() }

  // Notify the host on user dismissal so subsequent toggle calls stay in sync.
  function dismiss() {
    if (shell && typeof shell.hide === "function")
      shell.hide(manifest ? manifest.id : "xarishark.language-input")
    else close()
  }

  component MenuAction: CursorSurface {
    property string text: ""
    property string iconText: ""
    property int menuPosition: 0
    signal activated()
    width: parent.width
    height: Math.max(Style.space(22), Style.font.icon + Style.spacing.sm * 2) + Style.spacing.labelGap * 2
    hasCursor: root.menuIndex === menuPosition && (!languages.mouseHoverActive || actionMouse.containsMouse)
    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.controlGap
      OpticalGlyph {
        visible: iconText !== ""
        text: iconText
        color: Color.foreground
        fontSize: Style.font.icon
        implicitWidth: Style.space(24)
        implicitHeight: Style.space(24)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: parent.parent.text
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (languages.mouseHoverActive) root.selectMenu(parent.menuPosition)
      onPositionChanged: function(mouse) {
        languages.pointerMoved(mapToGlobal(mouse.x, mouse.y))
        if (languages.mouseHoverActive && !languages.dragging) root.selectMenu(parent.menuPosition)
      }
      onClicked: { root.selectMenu(parent.menuPosition); parent.activated() }
    }
  }

  PanelController { id: controller }
  LocaleModel { id: localeModel }

  CenteredPanel {
    id: panel
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: Style.space(520)
    contentHeight: (languages.addOpen || root.switchOpen || root.localeOpen) ? Style.space(480) : content.implicitHeight
    onCloseRequested: root.dismiss()

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // One menu cursor: mouse-only remove buttons never receive key focus.
      blocked: true
      Keys.onPressed: function(event) {
        languages.mouseHoverActive = false
        if (languages.addOpen || root.switchOpen || root.localeOpen) return
        if (event.key === Qt.Key_Alt && !event.isAutoRepeat) {
          if (root.menuIndex < languages.layouts.length) languages.beginDrag(root.menuIndex)
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
          var delta = event.key === Qt.Key_Up ? -1 : 1
          if (languages.dragging || event.modifiers & Qt.AltModifier) {
            if (root.menuIndex < languages.layouts.length) languages.move(root.menuIndex, delta)
          } else root.selectMenu(root.menuIndex + delta)
          event.accepted = true
        } else if (event.key === Qt.Key_Delete) {
          if (root.menuIndex < languages.layouts.length) languages.remove(root.menuIndex)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          if (root.menuIndex === languages.layouts.length && languages.addItem.enabled) languages.addOpen = true
          else if (root.menuIndex === languages.layouts.length + 1 && languages.editable) root.openSwitch("record")
          else if (root.menuIndex === languages.layouts.length + 2 && languages.editable) root.openSwitch("list")
          else if (root.menuIndex === languages.layouts.length + 3 && !localeModel.busy) root.openLocale("user")
          else if (root.menuIndex === languages.layouts.length + 4 && !localeModel.busy) root.openLocale("system")
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          if (languages.dragging) { event.accepted = true; return }
          root.selectMenu(root.menuIndex + (event.key === Qt.Key_Backtab || event.modifiers & Qt.ShiftModifier ? -1 : 1))
          event.accepted = true
        }
      }
      Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Alt && !event.isAutoRepeat && !languages.mouseDragging) { languages.drop(); event.accepted = true }
      }
      Keys.onEscapePressed: {
        if (languages.dragging) languages.cancelDrag()
        else if (root.switchOpen) root.closeSwitch()
        else if (root.localeOpen) root.closeLocale()
        else if (!languages.popupOpen) root.dismiss()
      }
      onCloseRequested: root.dismiss()

      Flickable {
        id: viewport
        anchors.fill: parent
        visible: !languages.addOpen && !root.switchOpen && !root.localeOpen
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.spacing.panelGap

          PanelHero {
            title: "Language & Input"
            meta: "Keyboard and language settings"
            trailingControl: Component {
              OpticalGlyph {
                implicitWidth: Style.space(24)
                implicitHeight: Style.space(24)
                visible: languages.saving || localeModel.saving || languages.savedVisible || localeModel.savedVisible
                text: (languages.saving || localeModel.saving) ? "󰆓" : "✓"
                color: (languages.saving || localeModel.saving) ? Color.foreground : "#9ece6a"
                fontSize: Style.font.icon
                opacity: 1
                SequentialAnimation on opacity {
                  running: languages.saving || localeModel.saving
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.3; duration: 400 }
                  NumberAnimation { to: 1; duration: 400 }
                }
                onTextChanged: opacity = 1
              }
            }
            iconComponent: Component {
              OpticalGlyph {
                text: "⌨"
                implicitWidth: Style.space(32)
                implicitHeight: Style.space(32)
                width: implicitWidth
                height: implicitHeight
                color: Color.foreground
                fontSize: Style.font.display
              }
            }
          }

          InputLanguages {
            id: languages
            width: parent.width
            menuSelected: root.menuIndex < layouts.length
            addHasCursor: root.menuIndex === layouts.length
            onLanguageSelected: function(index) { root.selectMenu(index) }
            onAddSelected: root.selectMenu(layouts.length)
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap
            PanelSeparator {}
            PanelSectionHeader { text: "Input Switching" }
            Row {
              width: parent.width
              spacing: Style.spacing.controlGap
              Text {
                id: currentHotkeyLabel
                text: "Current Hotkey:"
                anchors.verticalCenter: parent.verticalCenter
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              Keycaps {
                keys: languages.currentSwitchOptions.length ? languages.switchLabel.split("+").map(function(key) { return key.trim() }) : ["None"]
                fontSize: Style.font.body
                transformOrigin: Item.Left
                scale: Math.min(1, Math.max(1, parent.width - currentHotkeyLabel.width - parent.spacing) / Math.max(1, implicitWidth))
              }
            }
            MenuAction {
              id: recordAction
              menuPosition: languages.layouts.length + 1
              text: "Record new hotkey"
              iconText: "●"
              enabled: languages.editable
              onActivated: root.openSwitch("record")
            }
            MenuAction {
              id: listAction
              menuPosition: languages.layouts.length + 2
              text: "Select a hotkey from the list"
              iconText: "☰"
              enabled: languages.editable
              onActivated: root.openSwitch("list")
            }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap
            PanelSeparator {}
            PanelSectionHeader { text: "System Language" }
            Text {
              width: parent.width
              text: "Current User Language: " + localeModel.label
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }
            MenuAction {
              id: localeAction
              text: "Change my display language"
              iconText: "󰗊"
              menuPosition: languages.layouts.length + 3
              enabled: !localeModel.busy
              onActivated: root.openLocale("user")
            }
            MenuAction {
              id: systemLocaleAction
              text: "Change system language"
              iconText: "󰒃"
              menuPosition: languages.layouts.length + 4
              enabled: !localeModel.busy
              onActivated: root.openLocale("system")
            }
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: localeModel.error || localeModel.notice
            color: Color.urgent
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {}
          Text {
            width: parent.width
            text: "↑/↓ Navigate · Enter Select · Hold Alt+↑/↓ Move language\nDel Remove language · Esc Cancel / Close"
            textFormat: Text.PlainText
            color: Qt.darker(Color.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      SystemLanguage {
        anchors.fill: parent
        opened: root.localeOpen
        scope: root.localeScope
        options: localeModel.state.available
        onCanceled: root.closeLocale()
        onChosen: function(scope, locale) { localeModel.choose(scope, locale); root.closeLocale() }
      }

      SwitchHotkey {
        anchors.fill: parent
        opened: root.switchOpen
        mode: root.switchMode
        options: languages.switchOptions
        onCanceled: root.closeSwitch()
        onChosen: function(option) { languages.chooseSwitch(option); root.closeSwitch() }
      }

      LanguagePicker {
        anchors.fill: parent
        opened: languages.addOpen
        options: languages.addOptions
        onCanceled: languages.closePicker()
        onChosen: function(row) { languages.add(row) }
      }
    }
  }
}
