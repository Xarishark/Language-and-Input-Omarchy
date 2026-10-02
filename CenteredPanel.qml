import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Ui
import qs.Commons

// Standalone centered surface, using Omarchy's shared popup chrome.
PanelWindow {
  id: root
  property bool open: false
  property Item focusTarget: null
  property real contentWidth: Style.space(420)
  property real contentHeight: Style.space(240)
  default property alias content: holder.children
  signal closeRequested()

  visible: open
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; bottom: true; left: true; right: true }
  WlrLayershell.namespace: "xarishark-language-input"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: open
    ? (focusPrime.running ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
    : WlrKeyboardFocus.None

  function acquireFocus() {
    if (!open) return
    focusPrime.restart()
    Qt.callLater(function() {
      if (root.open && root.focusTarget) root.focusTarget.forceActiveFocus()
    })
  }
  onOpenChanged: acquireFocus()
  onBackingWindowVisibleChanged: if (backingWindowVisible) acquireFocus()
  Timer { id: focusPrime; interval: 75 }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onClicked: root.closeRequested()
  }

  BorderSurface {
    id: card
    anchors.centerIn: parent
    width: Math.min(root.contentWidth, Math.max(1, root.width - Style.gapsOut * 2))
    height: Math.min(root.contentHeight + contentTopInset + contentBottomInset,
      Math.max(1, root.height - Style.gapsOut * 2))
    color: Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.popupPadding
    radius: Style.cornerRadius

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    Item {
      id: holder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      anchors.rightMargin: card.contentRightInset
    }
  }

}
