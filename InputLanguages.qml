import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Ui
import qs.Commons

Column {
  id: root
  spacing: Style.spacing.labelGap

  property var layouts: []
  property var available: []
  property var switchOptions: []
  property var currentSwitchOptions: []
  property string switchChoice: ""
  property string savedSwitchChoice: ""
  property string submittedSwitchChoice: ""
  readonly property string switchLabel: currentSwitchOptions.length
    ? currentSwitchOptions.map(function(code) {
        var row = root.switchOptions.find(function(item) { return item.option === code })
        return row ? row.label : code
      }).join("; ") : "No layout-switch shortcut"
  function savePayload() {
    var payload = {revision: revision, layouts: layouts}
    if (switchChoice !== savedSwitchChoice) payload.switchOption = switchChoice
    return payload
  }
  function chooseSwitch(option) {
    if (!editable || dragging) return
    switchChoice = option
    savedVisible = false
    saveTimer.restart()
  }
  property var savedLayouts: []
  property string revision: ""
  property string error: ""
  property bool savedVisible: false
  property var submittedLayouts: []
  readonly property bool editable: !busy || saving
  property bool mouseHoverActive: true
  property real pointerX: -1
  property real pointerY: -1
  function pointerMoved(point) {
    if (Math.abs(point.x - pointerX) > 1 || Math.abs(point.y - pointerY) > 1) {
      mouseHoverActive = true
      pointerX = point.x
      pointerY = point.y
    }
  }
  property string warning: ""
  property bool busy: false
  property string operation: "read"
  property string recoveryError: ""
  property bool saving: operation === "apply" && busy
  property string responseText: ""
  property string stderrText: ""
  property bool stdoutDone: false
  property bool stderrDone: false
  property bool exitDone: false
  property int exitCode: 0
  readonly property bool dirty: (JSON.stringify(layouts) !== JSON.stringify(savedLayouts) || switchChoice !== savedSwitchChoice)
  property bool addOpen: false
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool menuSelected: true
  property bool addHasCursor: false
  property bool dragging: false
  property bool mouseDragging: false
  property real dragPointerY: 0
  property real dragGrabOffset: 0
  property string draggedKey: ""
  property var dragStartLayouts: []
  property var rowModel: []
  function layoutKey(row) { return row.layout + ":" + row.variant }
  function syncRows() {
    var oldKeys = rowModel.map(layoutKey).sort().join("|")
    var newKeys = layouts.map(layoutKey).sort().join("|")
    if (oldKeys !== newKeys) rowModel = layouts.slice()
  }
  onLayoutsChanged: syncRows()
  signal languageSelected(int index)
  signal addSelected()
  function rowAt(index) {
    for (var i = 0; i < rows.count; i++) {
      var item = rows.itemAt(i)
      if (item && item.positionIndex === index) return item
    }
    return null
  }
  readonly property Item addItem: addButton
  readonly property bool popupOpen: addOpen
  readonly property var addOptions: available.filter(function(row) {
    return !root.layouts.some(function(existing) {
      return existing.layout === row.layout && existing.variant === row.variant
    })
  })

  function closePicker() {
    addOpen = false
    addSelected()
  }

  function add(row) {
    if (!editable || layouts.length >= 4) return
    layouts = layouts.concat([row])
    closePicker()
    focusRow(layouts.length - 1)
    saveTimer.restart()
  }

  function focusRow(index) {
    selectedIndex = Math.max(0, Math.min(index, layouts.length - 1))
    cursorActive = true
    languageSelected(selectedIndex)
  }

  function reload() {
    if (busy || saveTimer.running || dragging) { focusRow(selectedIndex); return }
    selectedIndex = 0
    request("read", null)
  }

  function failed(message) {
    busy = false
    error = message
    if (operation === "apply") {
      layouts = savedLayouts.slice()
      switchChoice = savedSwitchChoice
      recoveryError = message
      // Re-read after rollback or stale state, without a manual Reload action.
      Qt.callLater(function() { root.request("read", null) })
    } else focusRow(selectedIndex)
  }

  function request(action, payload) {
    if (busy) return
    busy = true
    operation = action
    if (action === "apply") { submittedLayouts = layouts.slice(); submittedSwitchChoice = switchChoice }
    responseText = ""
    stderrText = ""
    stdoutDone = false
    stderrDone = false
    exitDone = false
    error = recoveryError
    savedVisible = false
    backend.command = ["python3", decodeURIComponent(Qt.resolvedUrl("keyboard.py").toString().replace(/^file:\/\//, "")), action]
    if (payload) backend.command = backend.command.concat([JSON.stringify(payload)])
    backend.running = true
  }

  function finishRequest() {
    if (!stdoutDone || !stderrDone || !exitDone) return
    if (responseText.trim()) acceptResponse(responseText)
    else failed(stderrText.trim() || "Could not start the keyboard helper")
  }

  function acceptResponse(text) {
    busy = false
    try {
      var result = JSON.parse(text)
      if (!result.ok) { failed(result.error || "Keyboard operation failed"); return }
      var currentKey = layouts[selectedIndex] ? layoutKey(layouts[selectedIndex]) : ""
      var newerEdits = operation === "apply" && JSON.stringify(layouts) !== JSON.stringify(submittedLayouts)
      var newerSwitch = operation === "apply" && switchChoice !== submittedSwitchChoice
      currentSwitchOptions = result.currentSwitchOptions
      savedSwitchChoice = currentSwitchOptions.join(",")
      if (!newerSwitch) switchChoice = savedSwitchChoice
      switchOptions = result.switchOptions
      var actual = result.layouts.map(function(row) { return {layout: row.layout, variant: row.variant, label: row.label} })
      if (!newerEdits) layouts = actual
      savedLayouts = actual
      selectedIndex = Math.max(0, layouts.findIndex(function(row) { return root.layoutKey(row) === currentKey }))
      revision = result.revision
      if (JSON.stringify(available) !== JSON.stringify(result.available)) available = result.available
      warning = result.deviceOverrides.length
        ? "These keyboards have their own overrides: " + result.deviceOverrides.join(", ") : ""
      savedVisible = operation === "apply" && !dirty && !dragging
      if (savedVisible) savedTimer.restart()
      if (dirty && !dragging) saveTimer.restart()
      error = recoveryError
      recoveryError = ""
      if (menuSelected) focusRow(selectedIndex)
    } catch (e) { failed("Invalid response from keyboard helper") }
  }

  function beginDrag(index, fromMouse) {
    if (dragging || !editable || index < 0 || index >= layouts.length) return
    saveTimer.stop()
    draggedKey = layoutKey(layouts[index])
    dragStartLayouts = layouts.slice()
    dragging = true
    mouseDragging = fromMouse === true
    savedVisible = false
    focusRow(index)
  }

  function drop() {
    if (!dragging) return
    dragging = false
    mouseDragging = false
    draggedKey = ""
    if (dirty) {
      if (!busy) request("apply", savePayload())
      else saveTimer.restart()
    }
  }

  function cancelDrag() {
    if (!dragging) return
    var originalIndex = dragStartLayouts.findIndex(function(row) { return root.layoutKey(row) === root.draggedKey })
    layouts = dragStartLayouts.slice()
    dragging = false
    mouseDragging = false
    draggedKey = ""
    focusRow(originalIndex)
    if (dirty) saveTimer.restart()
  }

  function move(index, delta) {
    if (!editable) return
    if (!dragging) beginDrag(index)
    index = layouts.findIndex(function(row) { return root.layoutKey(row) === root.draggedKey })
    if (index < 0) return
    var next = layouts.slice()
    var target = index + delta
    if (target < 0 || target >= next.length) return
    var row = next.splice(index, 1)[0]
    next.splice(target, 0, row)
    layouts = next
    focusRow(target)
  }

  function remove(index) {
    if (!editable || dragging || layouts.length <= 1) return
    var next = layouts.slice()
    next.splice(index, 1)
    layouts = next
    focusRow(Math.min(index, next.length - 1))
    saveTimer.restart()
  }

  Timer { id: savedTimer; interval: 2000; onTriggered: root.savedVisible = false }

  Timer {
    id: saveTimer
    interval: 180
    onTriggered: if (root.dirty && !root.busy && !root.dragging)
      root.request("apply", root.savePayload())
  }

  Process {
    id: backend
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { root.responseText = text; root.stdoutDone = true; root.finishRequest() }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: { root.stderrText = text; root.stderrDone = true; root.finishRequest() }
    }
    onExited: function(code) {
      root.exitCode = code
      root.exitDone = true
      root.finishRequest()
    }
  }

  PanelSeparator {}
  PanelSectionHeader { text: "Input Languages" }


  Item {
    id: languageList
    width: root.width
    readonly property real rowHeight: Math.max(Style.space(22), Style.font.icon + Style.spacing.sm * 2) + Style.spacing.labelGap * 2
    height: root.layouts.length * rowHeight
    Repeater {
      id: rows
      model: root.rowModel
      CursorSurface {
        id: languageRow
        required property var modelData
        required property int index
        readonly property int positionIndex: root.layouts.findIndex(function(row) { return root.layoutKey(row) === root.layoutKey(modelData) })
        readonly property bool pickedUp: root.dragging && root.layoutKey(modelData) === root.draggedKey
        width: root.width
        height: parent.rowHeight
        y: pickedUp && root.mouseDragging
          ? Math.max(0, Math.min(languageList.height - height, root.dragPointerY - root.dragGrabOffset))
          : Math.max(0, positionIndex) * parent.rowHeight
        z: pickedUp ? 1 : 0
        scale: pickedUp ? 1.025 : 1
        hasCursor: pickedUp || (!root.dragging && root.menuSelected && root.cursorActive && root.selectedIndex === positionIndex && (!root.mouseHoverActive || rowMouse.containsMouse))
        Behavior on y {
          enabled: !(languageRow.pickedUp && root.mouseDragging)
          NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          preventStealing: true
          acceptedButtons: Qt.LeftButton
          cursorShape: root.mouseDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          property real pressedY: 0
          property real grabOffset: 0
          onEntered: if (root.mouseHoverActive && !root.dragging) root.focusRow(languageRow.positionIndex)
          onClicked: if (!root.dragging) root.focusRow(languageRow.positionIndex)
          onPressed: function(mouse) {
            pressedY = mapToItem(languageList, mouse.x, mouse.y).y
            grabOffset = mouse.y
          }
          onPositionChanged: function(mouse) {
            root.pointerMoved(mapToGlobal(mouse.x, mouse.y))
            if (!pressed) {
              if (root.mouseHoverActive && !root.dragging) root.focusRow(languageRow.positionIndex)
              return
            }
            if (!root.editable || (root.dragging && !root.mouseDragging)) return
            var point = mapToItem(languageList, mouse.x, mouse.y)
            if (!root.dragging && Math.abs(point.y - pressedY) < Style.space(5)) return
            if (!root.dragging) {
              root.dragGrabOffset = grabOffset
              root.dragPointerY = point.y
              root.beginDrag(languageRow.positionIndex, true)
            }
            root.dragPointerY = point.y
            var target = Math.max(0, Math.min(root.layouts.length - 1,
              Math.round((point.y - root.dragGrabOffset) / languageList.rowHeight)))
            if (target !== root.selectedIndex) root.move(root.selectedIndex, target - root.selectedIndex)
          }
          onReleased: function(mouse) {
            if (!root.mouseDragging) return
            var point = mapToItem(languageList, mouse.x, mouse.y)
            if (point.x >= 0 && point.x <= languageList.width && point.y >= 0 && point.y <= languageList.height)
              root.drop()
            else root.cancelDrag()
          }
          onCanceled: if (root.mouseDragging) root.cancelDrag()
        }

        RowLayout {
          id: controls
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.spacing.rowPaddingX
          anchors.rightMargin: Style.spacing.rowPaddingX
          spacing: Style.spacing.controlGap

          Text {
            Layout.fillWidth: true
            text: (languageRow.pickedUp || (!root.dragging && root.mouseHoverActive && rowMouse.containsMouse) ? "↕ " : (languageRow.positionIndex + 1) + ". ") + modelData.label
            textFormat: Text.PlainText
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          PanelActionButton {
            iconText: "×"
            tooltipText: "Remove layout"
            focusable: false
            enabled: root.editable && !root.dragging && root.layouts.length > 1
            hoverColor: Color.urgent
            onClicked: root.remove(languageRow.positionIndex)
          }
        }
      }
    }
  }

  CursorSurface {
    id: addButton
    width: root.width
    height: languageList.rowHeight
    hasCursor: root.addHasCursor && (!root.mouseHoverActive || addMouse.containsMouse)
    enabled: root.editable && !root.dragging && root.revision !== "" && root.layouts.length < 4
    Text {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.rowPaddingX
      text: "+ " + (root.layouts.length >= 4 ? "Four layouts maximum" : "Add keyboard layout")
      textFormat: Text.PlainText
      color: parent.enabled ? Color.foreground : Qt.darker(Color.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      verticalAlignment: Text.AlignVCenter
    }
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      id: addMouse
      onEntered: if (root.mouseHoverActive) root.addSelected()
      onPositionChanged: function(mouse) {
        root.pointerMoved(mapToGlobal(mouse.x, mouse.y))
        if (root.mouseHoverActive && !root.dragging) root.addSelected()
      }
      onClicked: root.addOpen = true
    }
  }

  Text {
    width: parent.width
    visible: text !== ""
    text: root.error || root.warning
    textFormat: Text.PlainText
    color: root.error ? Color.urgent : Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }
}
