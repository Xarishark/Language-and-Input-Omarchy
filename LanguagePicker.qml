import QtQuick

// Group by the installed XKB base layout (language/country family), then
// choose its default or variant. Every option retains its original identity.
Item {
  id: root
  property bool opened: false
  property var options: []
  property string selectedGroup: ""
  property string selectedLabel: ""
  readonly property var groups: {
    var found = ({})
    options.forEach(function(row) {
      if (row.layout !== "custom" && !found[row.layout]) found[row.layout] = {layout: row.layout, label: row.groupLabel || row.layout}
    })
    return Object.keys(found).map(function(key) { return found[key] }).sort(function(a, b) { return a.label.localeCompare(b.label) })
  }
  readonly property var variants: options.filter(function(row) { return row.layout === root.selectedGroup }).sort(function(a, b) {
    if (!a.variant) return -1
    if (!b.variant) return 1
    return a.label.localeCompare(b.label)
  })
  signal canceled()
  signal chosen(var row)
  visible: opened
  onOpenedChanged: if (opened) { selectedGroup = ""; selectedLabel = "" }

  LayoutPicker {
    id: picker
    anchors.fill: parent
    opened: root.opened
    options: root.selectedGroup ? root.variants : root.groups
    titleText: root.selectedGroup ? root.selectedLabel + " layouts" : "Add keyboard language"
    placeholderText: root.selectedGroup ? "Start typing to filter layouts…" : "Start typing to filter languages…"
    actionText: root.selectedGroup ? "Add" : "Select"
    showIdentifiers: root.selectedGroup !== ""
    onCanceled: {
      if (root.selectedGroup) { root.selectedGroup = ""; root.selectedLabel = ""; reset() }
      else root.canceled()
    }
    onChosen: function(row) {
      if (root.selectedGroup) root.chosen(row)
      else { root.selectedGroup = row.layout; root.selectedLabel = row.label; reset() }
    }
  }
}
