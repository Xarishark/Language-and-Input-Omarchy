import QtQuick
import qs.Ui
import qs.Commons

// Searchable page replacing the settings content inside the same panel.
Item {
  id: root
  property bool opened: false
  property var options: []
  property string titleText: "Add keyboard layout"
  property string actionText: "Add"
  property string placeholderText: "Search languages and variants…"
  property bool showIdentifiers: true
  property bool searchable: true
  property bool mouseNavigation: false
  property string descriptionText: ""
  readonly property var filtered: options.filter(function(row) {
    var query = root.searchable ? search.text.toLowerCase().trim() : ""
    return root.optionLabel(row).toLowerCase().indexOf(query) !== -1
  })
  signal canceled()
  signal chosen(var row)

  function optionLabel(row) {
    return row.label + (root.showIdentifiers ? " [" + row.layout + (row.variant ? "/" + row.variant : "") + "]" : "")
  }

  visible: opened
  onOpenedChanged: if (opened) {
    reset()
  }
  onFilteredChanged: results.currentIndex = 0

  function reset() { mouseNavigation = false; search.text = ""; results.currentIndex = 0; restoreFocus() }

  function restoreFocus() { Qt.callLater(function() { if (root.opened) (root.searchable ? search : results).forceActiveFocus() }) }

  function choose() {
    if (results.currentIndex >= 0 && results.currentIndex < filtered.length)
      chosen(filtered[results.currentIndex])
  }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(event) {
    root.mouseNavigation = false
    if (root.searchable && results.activeFocus && event.text.length > 0
        && !event.isAutoRepeat && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
        && event.text.charCodeAt(0) >= 32 && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) {
      search.forceActiveFocus()
      search.text += event.text
      event.accepted = true
    } else if (event.key === Qt.Key_Escape) {
      root.canceled()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      // Keep Tab navigation within this page.
      var backwards = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
      if (search.activeFocus) (backwards ? cancel : results).forceActiveFocus()
      else if (results.activeFocus) (backwards && root.searchable ? search : cancel).forceActiveFocus()
      else (backwards || !root.searchable ? results : search).forceActiveFocus()
      event.accepted = true
    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
      results.currentIndex = Math.max(0, Math.min(filtered.length - 1,
        results.currentIndex + (event.key === Qt.Key_Down ? 1 : -1)))
      results.forceActiveFocus()
      results.positionViewAtIndex(results.currentIndex, ListView.Contain)
      event.accepted = true
    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !cancel.activeFocus) {
      root.choose()
      event.accepted = true
    }
  }

  Item {
    anchors.fill: parent

    Column {
      id: header
      width: parent.width
      spacing: Style.spacing.panelGap
      PanelSectionHeader { text: root.titleText; fontSize: Style.font.title }
      Text {
        width: parent.width
        visible: root.descriptionText !== ""
        text: root.descriptionText
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }
      TextField {
        id: search
        visible: root.searchable
        width: parent.width
        placeholderText: root.placeholderText
      }
    }

    ListView {
      id: results
      anchors.top: header.bottom
      anchors.bottom: footer.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: Style.spacing.panelGap
      anchors.bottomMargin: Style.spacing.panelGap
      model: root.filtered
      clip: true
      currentIndex: 0
      boundsBehavior: Flickable.StopAtBounds
      delegate: CursorSurface {
        required property var modelData
        required property int index
        width: results.width
        height: Math.max(Style.spacing.popupRowHeight, label.implicitHeight + Style.spacing.labelGap * 2)
        hasCursor: results.currentIndex === index && (!root.mouseNavigation || optionMouse.containsMouse)
        OpticalGlyph {
          id: entryIcon
          visible: !!modelData.iconText
          text: modelData.iconText || ""
          color: Color.foreground
          fontSize: Style.font.icon
          width: Style.space(24)
          height: width
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.labelGap
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          id: label
          anchors.fill: parent
          anchors.margins: Style.spacing.labelGap
          anchors.leftMargin: entryIcon.visible ? entryIcon.width + Style.spacing.controlGap + Style.spacing.labelGap : Style.spacing.labelGap
          text: root.optionLabel(modelData)
          textFormat: Text.PlainText
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }
        MouseArea {
          anchors.fill: parent
          id: optionMouse
          hoverEnabled: true
          onEntered: { root.mouseNavigation = true; results.currentIndex = index }
          onPositionChanged: { root.mouseNavigation = true; results.currentIndex = index }
          onClicked: { results.currentIndex = index; root.choose() }
        }
      }
      Text {
        anchors.centerIn: parent
        visible: results.count === 0
        text: "No matching entries"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }

    Column {
      id: footer
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: Style.spacing.labelGap
      Button { id: cancel; text: "Back"; iconText: "←"; focusable: true; onClicked: root.canceled() }
      Text {
        width: parent.width
        text: "↑/↓ Navigate · Enter " + root.actionText + " · Esc Back"
        textFormat: Text.PlainText
        color: Qt.darker(Color.foreground, 1.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
