import QtQuick
import Quickshell.Io

Item {
  id: root
  visible: false
  property var state: ({available: [], userLocale: "", systemLocale: "", activeLocale: "", activeMessages: "", needsLogin: false})
  property bool busy: false
  property string operation: "read"
  readonly property bool saving: busy && operation === "apply"
  property bool savedVisible: false
  property string error: ""
  property string output: ""
  property string errors: ""
  property bool stdoutDone: false
  property bool stderrDone: false
  property bool exitDone: false
  function languageName(code) {
    var row = state.available.find(function(item) { return item.locale === code || item.locale.toLowerCase().replace("utf-8", "utf8") === code.toLowerCase().replace("utf-8", "utf8") })
    return row ? row.label.replace(/\s*\[[^\]]*\]$/, "") : "Unknown language"
  }
  readonly property string label: state.activeLocale ? languageName(state.activeMessages || state.activeLocale) : "Loading…"
  readonly property string notice: state.needsLogin
    ? "System language change pending. Please restart or relog." : ""

  function reload() { if (!busy) request("read", null) }
  function choose(scope, locale) {
    if (!busy) request("apply", {scope: scope, locale: locale, revision: state.revision})
  }
  function request(action, payload) {
    if (busy) return
    operation = action
    busy = true
    savedVisible = false
    error = ""
    output = ""
    errors = ""
    stdoutDone = false
    stderrDone = false
    exitDone = false
    backend.command = ["python3", decodeURIComponent(Qt.resolvedUrl("locale_backend.py").toString().replace(/^file:\/\//, "")), action]
    if (payload) backend.command = backend.command.concat([JSON.stringify(payload)])
    backend.running = true
  }
  function finish() {
    if (!stdoutDone || !stderrDone || !exitDone) return
    busy = false
    try {
      var result = JSON.parse(output)
      if (!result.ok) { error = result.error || "Could not change language"; return }
      state = result
      if (operation === "apply") {
        savedVisible = true
        savedTimer.restart()
      }
    } catch (e) { error = errors.trim() || "Could not read language settings" }
  }
  Timer { id: savedTimer; interval: 2000; onTriggered: root.savedVisible = false }
  Process {
    id: backend
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.output = text; root.stdoutDone = true; root.finish() } }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: { root.errors = text; root.stderrDone = true; root.finish() } }
    onExited: { root.exitDone = true; root.finish() }
  }
}
