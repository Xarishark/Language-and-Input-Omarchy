import QtQuick
import qs.Ui
import qs.Commons

// Same searchable full-window page as keyboard layout and shortcut selection.
Item {
  id: root
  property bool opened: false
  property var options: []
  property string scope: "user"
  property var pending: null
  signal canceled()
  signal chosen(string scope, string locale)
  visible: opened
  onOpenedChanged: if (opened) pending = null
  Keys.onPressed: function(event) {
    if (root.pending && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
      root.chosen(root.scope, root.pending.locale)
      event.accepted = true
    }
  }
  Keys.onEscapePressed: {
    if (root.pending) root.pending = null
    else root.canceled()
  }
  Column {
    anchors.centerIn: parent
    width: parent.width
    visible: !!root.pending
    spacing: Style.spacing.panelGap
    PanelHero { title: "Authentication required"; meta: root.pending ? root.pending.label : "" }
    Text {
      width: parent.width
      text: root.pending && root.pending.requiresGeneration
        ? "This language needs to be generated. Administrator authentication is required to install it."
        : "Changing the system default requires administrator authentication."
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.controlGap
      Button { text: "Continue"; iconText: "󰒃"; onClicked: root.chosen(root.scope, root.pending.locale) }
      Button { text: "Back"; iconText: "←"; onClicked: root.pending = null }
    }
    Text {
      width: parent.width
      text: "Enter Continue · Esc Back"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
    }
  }
  LayoutPicker {
    anchors.fill: parent
    opened: root.opened && !root.pending
    titleText: root.scope === "user" ? "My display language" : "System language"
    descriptionText: root.scope === "user" ? "" : "Language for the login screen, system services, and new accounts."
    placeholderText: "Search languages and regions…"
    actionText: "Select"
    showIdentifiers: false
    options: (root.scope === "user" ? [{locale: "", label: "Use system default"}] : []).concat(root.options.map(function(row) { return {locale: row.locale, label: row.label.replace(/\s*\[[^\]]*\]$/, ""), requiresGeneration: row.requiresGeneration, iconText: row.requiresGeneration || root.scope === "system" ? "󰒃" : ""} }))
    onCanceled: root.canceled()
    onChosen: function(row) {
      if (row.requiresGeneration || root.scope === "system") { root.pending = row; root.forceActiveFocus() }
      else root.chosen(root.scope, row.locale)
    }
  }
}
