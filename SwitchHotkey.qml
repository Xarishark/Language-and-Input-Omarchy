import QtQuick
import qs.Ui
import qs.Commons
import "Shortcut.js" as Shortcut

Item {
  id: root
  property bool opened: false
  property string mode: "record"
  property var options: []
  readonly property var cyclingOptions: options.filter(function(row) {
    return row.option === "grp:toggle" || /_toggle$/.test(row.option)
  })
  property bool complete: false
  property string candidate: ""
  property var held: ({})
  property var captured: []
  signal canceled()
  signal chosen(string option)
  visible: opened
  onOpenedChanged: if (opened && mode === "record") retry()

  function retry() {
    held = ({})
    captured = []
    candidate = ""
    complete = false
    Qt.callLater(function() { if (root.opened && root.mode === "record") root.forceActiveFocus() })
  }
  function save() { if (complete && candidate) chosen(candidate) }

  function keyName(event) {
    // Accept evdev codes and their XKB (+8) counterparts. Check the Qt
    // modifier too, so a remapped non-modifier is never mistaken for one.
    var sides = {50: "Left Shift", 62: "Right Shift", 37: "Left Ctrl", 105: "Right Ctrl",
      64: "Left Alt", 108: "Right Alt", 133: "Left Super", 134: "Right Super",
      42: "Left Shift", 54: "Right Shift", 29: "Left Ctrl", 97: "Right Ctrl",
      56: "Left Alt", 100: "Right Alt", 125: "Left Super", 126: "Right Super"}
    var side = sides[event.nativeScanCode]
    if (side && ((side.indexOf("Shift") !== -1 && event.key === Qt.Key_Shift)
      || (side.indexOf("Ctrl") !== -1 && event.key === Qt.Key_Control)
      || (side.indexOf("Alt") !== -1 && (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr))
      || (side.indexOf("Super") !== -1 && event.key === Qt.Key_Meta))) return side
    if (event.key === Qt.Key_Shift) return "Shift"
    if (event.key === Qt.Key_Control) return "Ctrl"
    if (event.key === Qt.Key_Alt) return "Alt"
    if (event.key === Qt.Key_AltGr) return "Right Alt"
    if (event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R) return "Super"
    if (event.key === Qt.Key_Space) return "Space"
    if (event.key === Qt.Key_CapsLock) return "Caps Lock"
    if (event.key === Qt.Key_ScrollLock) return "Scroll Lock"
    if (event.key === Qt.Key_Menu) return "Menu"
    if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) return String.fromCharCode(event.key)
    if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) return String.fromCharCode(event.key)
    if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35) return "F" + (event.key - Qt.Key_F1 + 1)
    if (event.key === Qt.Key_Tab) return "Tab"
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) return "Enter"
    if (event.key === Qt.Key_Backspace) return "Backspace"
    if (event.key === Qt.Key_Delete) return "Del"
    return event.text && event.text.charCodeAt(0) >= 32 ? event.text.toUpperCase() : "Unknown key"
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    if (mode !== "record") return
    event.accepted = true
    if (event.key === Qt.Key_Escape) { root.canceled(); return }
    if (event.isAutoRepeat) return
    if (complete) {
      if (event.modifiers & Qt.ControlModifier) {
        if (event.key === Qt.Key_S) root.save()
        else if (event.key === Qt.Key_R) root.retry()
      }
      return
    }
    var id = String(event.nativeScanCode || event.key)
    var next = Object.assign({}, held)
    next[id] = keyName(event)
    held = next
    if (captured.indexOf(next[id]) === -1) captured = captured.concat([next[id]])
  }
  Keys.onReleased: function(event) {
    if (mode !== "record") return
    event.accepted = true
    if (event.isAutoRepeat || complete) return
    var id = String(event.nativeScanCode || event.key)
    if (!held[id]) return
    var next = Object.assign({}, held)
    delete next[id]
    held = next
    if (Object.keys(held).length) return
    var option = Shortcut.optionFor(captured)
    candidate = cyclingOptions.some(function(row) { return row.option === option }) ? option : ""
    complete = true
  }

  LayoutPicker {
    anchors.fill: parent
    opened: root.opened && root.mode === "list"
    options: [{option: "", label: "No layout-switch shortcut"}].concat(root.cyclingOptions)
    titleText: "Select a hotkey"
    searchable: false
    placeholderText: "Search shortcuts…"
    actionText: "Select"
    showIdentifiers: false
    onCanceled: root.canceled()
    onChosen: function(row) { root.chosen(row.option) }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width
    visible: root.mode === "record"
    spacing: Style.spacing.panelGap
    Text {
      width: parent.width
      text: "Press key combination"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.display
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
    Keycaps {
      keys: root.captured
      anchors.horizontalCenter: parent.horizontalCenter
      scale: Math.min(1, parent.width / Math.max(1, implicitWidth))
    }
    Text {
      width: parent.width
      visible: root.complete
      text: root.candidate ? "✓  Valid combination" : "×  Invalid combination"
      color: root.candidate ? "#9ece6a" : Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      horizontalAlignment: Text.AlignHCenter
    }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.controlGap
      visible: root.complete
      Button { text: "Save"; iconText: "󰆓"; enabled: root.candidate !== ""; onClicked: root.save() }
      Button { text: "Retry"; iconText: "↻"; onClicked: root.retry() }
    }
    Text {
      width: parent.width
      text: root.complete ? "Ctrl+S Save · Ctrl+R Retry · Esc Back" : "Esc Back"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }
  }
}
