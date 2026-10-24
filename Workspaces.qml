import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "display.workspaces.lite"
  property var displayRanks: ({})
  property var declaredWorkspaces: ({})
  readonly property var workspaceCatalog: cursorTracker ? cursorTracker.declaredWorkspaces : declaredWorkspaces
  property point cursorPosition: Qt.point(0, 0)
  property bool cursorKnown: false
  readonly property bool cursorQueryRunning: cursorQuery.running
  readonly property var cursorTracker: {
    var widgets = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    return widgets.length ? widgets[0] : null
  }
  readonly property string cursorDisplayName: cursorKnown ? displayAt(cursorPosition.x, cursorPosition.y) : ""

  function finiteNumber(value) { return typeof value === "number" && isFinite(value) }

  // The catalog script ships next to this file. Qt.resolvedUrl hands back a
  // file:// URL, so decode it into a real path: an install directory may hold
  // spaces or other characters the URL encoder escaped.
  readonly property string catalogScript: {
    var url = Qt.resolvedUrl("workspace_catalog.py").toString()
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : url
  }

  function scheduleRefresh() {
    if (cursorTracker !== root) return
    refreshTimer.restart()
  }
  function refreshModels() {
    if (cursorTracker !== root) return
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    if (!catalogQuery.running) catalogQuery.running = true
  }

  onCursorTrackerChanged: {
    cursorKnown = false
    if (cursorTracker === root) scheduleRefresh()
    else { cursorQuery.running = false; refreshTimer.stop() }
  }
  Component.onCompleted: { refreshDisplayOrder(); scheduleRefresh() }
  Component.onDestruction: { cursorQuery.running = false; refreshTimer.stop(); catalogQuery.running = false }
  onSettingsChanged: refreshDisplayOrder()

  Timer { id: refreshTimer; interval: 100; onTriggered: root.refreshModels() }

  // Quickshell already reads Hyprland's event socket and relays every event as
  // rawEvent, so this widget listens there only. Window-level events are
  // ignored on purpose: they would re-query the catalog constantly.
  function respondsToEvent(name) {
    return name.indexOf("workspace") === 0 || name.indexOf("focusedmon") === 0
      || name.indexOf("moveworkspace") === 0 || name.indexOf("monitor") === 0
      || name === "configreloaded"
  }
  Connections {
    target: Hyprland
    enabled: root.cursorTracker === root
    function onRawEvent(event) { if (root.respondsToEvent(event.name)) root.scheduleRefresh() }
  }

  Process {
    id: catalogQuery
    command: ["python3", root.catalogScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var catalog = root.parseCatalog(text)
        // Bad or truncated output keeps the last good model instead of blanking
        // the bar.
        if (catalog) root.declaredWorkspaces = catalog
      }
    }
  }

  // Only a positive-id list per named monitor is accepted, so nothing the
  // catalog prints can reach the delegates unchecked.
  function parseCatalog(text) {
    var result
    try { result = JSON.parse(text) } catch (error) { return null }
    if (!result || result.ok !== true) return null
    if (!result.workspaces || typeof result.workspaces !== "object" || Array.isArray(result.workspaces)) return null
    var catalog = {}
    var names = Object.keys(result.workspaces)
    for (var i = 0; i < names.length; ++i) {
      var ids = result.workspaces[names[i]]
      if (!Array.isArray(ids) || names[i] === "__proto__") continue
      var seen = {}
      var accepted = []
      for (var j = 0; j < ids.length; ++j) {
        var id = ids[j]
        if (!Number.isInteger(id) || id <= 0 || seen[id]) continue
        seen[id] = true
        accepted.push(id)
      }
      catalog[names[i]] = accepted.sort(function(left, right) { return left - right })
    }
    return catalog
  }

  // A non-mirrored monitor arrives as mirrorOf "none" from Hyprland and may be
  // null elsewhere; only a connector name means the output mirrors another one.
  function isMirrored(state) {
    var mirror = state.mirrorOf
    return mirror !== undefined && mirror !== null && mirror !== "" && mirror !== "none"
  }
  function isPresented(state) {
    return !!state && !state.disabled && state.dpmsStatus !== false && !isMirrored(state)
  }

  function displayAt(x, y) {
    if (!finiteNumber(x) || !finiteNumber(y)) return ""
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; ++i) {
      var monitor = monitors[i], state = monitor && monitor.lastIpcObject
      if (!isPresented(state)) continue
      if (!finiteNumber(state.width) || !finiteNumber(state.height) || !finiteNumber(state.scale)
          || state.width < 1 || state.height < 1 || state.scale <= 0
          || !finiteNumber(state.x) || !finiteNumber(state.y) || !finiteNumber(state.transform)) continue
      var rotated = state.transform % 2 !== 0
      var width = Math.round((rotated ? state.height : state.width) / state.scale)
      var height = Math.round((rotated ? state.width : state.height) / state.scale)
      if (x >= state.x && x < state.x + width && y >= state.y && y < state.y + height) return monitor.name
    }
    return ""
  }
  function pollCursor() {
    if (cursorTracker !== root || cursorQuery.running) return
    var widgets = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    for (var i = 0; i < widgets.length; ++i)
      if (widgets[i] !== root && widgets[i].cursorQueryRunning) return
    cursorQuery.running = true
  }
  Timer {
    interval: 100; repeat: true; triggeredOnStart: true
    running: root.cursorTracker === root && Hyprland.monitors.values.length > 0
    onTriggered: root.pollCursor()
    onRunningChanged: if (!running) cursorQuery.running = false
  }
  Process {
    id: cursorQuery
    command: ["hyprctl", "-j", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var position = JSON.parse(text)
          if (!root.finiteNumber(position.x) || !root.finiteNumber(position.y)) throw new Error("invalid cursor")
          root.cursorPosition = Qt.point(position.x, position.y)
          root.cursorKnown = true
        } catch (error) { root.cursorKnown = false }
      }
    }
    onExited: function(code, status) { if (code !== 0 || status !== 0) root.cursorKnown = false }
  }
  Timer { interval: 1000; running: cursorQuery.running; onTriggered: { root.cursorKnown = false; cursorQuery.signal(9) } }

  function refreshDisplayOrder() {
    var entries = setting("displays", []), ranks = {}
    Hyprland.monitors.values.forEach(function(m) {
      if (!m || typeof m.name !== "string") return
      var match = displaySettings(m), index = entries.indexOf(match)
      if (index >= 0) ranks[m.name] = index
    })
    if (JSON.stringify(displayRanks) !== JSON.stringify(ranks)) displayRanks = ranks
  }
  Connections { target: Hyprland.monitors; function onValuesChanged() { root.refreshDisplayOrder() } }
  function saveDisplays(entries) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return false
    var next = Object.assign({}, settings, { id: moduleName, displays: entries })
    settings = next
    bar.shell.updateEntryInline(moduleName, next)
    return true
  }
  function rememberedDisplayKey(entry) {
    if (!entry) return ""
    return JSON.stringify([entry.connector || "", entry.make || "", entry.model || "", entry.serial || ""])
  }
  function rememberedDisplays() {
    return setting("displays", []).slice()
  }
  function rememberedDisplay(key) {
    var entries = setting("displays", [])
    for (var i = 0; i < entries.length; ++i)
      if (rememberedDisplayKey(entries[i]) === key) return entries[i]
    return null
  }
  function connectedConnectorFor(entry) {
    if (!entry) return ""
    var key = rememberedDisplayKey(entry), monitors = orderedMonitors()
    for (var i = 0; i < monitors.length; ++i)
      if (rememberedDisplayKey(displaySettings(monitors[i])) === key) return monitors[i].name
    return ""
  }
  function rememberedDisplayOptions() {
    return rememberedDisplays().map(function(entry) {
      var connector = connectedConnectorFor(entry)
      var name = entry.name || entry.connector || "Unnamed display"
      return {
        value: rememberedDisplayKey(entry),
        label: (entry.icon || "\uf108") + "  " + name + " · " + (entry.connector || "no connector")
          + " · " + (connector ? "Connected" : "Disconnected")
      }
    })
  }
  function updateRememberedDisplay(key, name, icon) {
    name = String(name).trim()
    if (!name || !icon) return false
    var entries = setting("displays", []).slice()
    var index = entries.findIndex(function(entry) { return rememberedDisplayKey(entry) === key })
    if (index < 0) return false
    entries[index] = Object.assign({}, entries[index], { name: name, icon: icon })
    return saveDisplays(entries)
  }
  function forgetRememberedDisplay(key) {
    var entries = setting("displays", [])
    var kept = entries.filter(function(entry) { return rememberedDisplayKey(entry) !== key })
    return kept.length !== entries.length && saveDisplays(kept)
  }
  function displayEntry(monitor) {
    var identity = monitor.lastIpcObject || {}, entry = Object.assign({}, displaySettings(monitor), { connector: monitor.name })
    ;["make", "model", "serial"].forEach(function(key) { if (typeof identity[key] === "string") entry[key] = identity[key] })
    return entry
  }
  function renameDisplay(connector, name) {
    name = String(name).trim()
    var monitor = Hyprland.monitors.values.find(function(m) { return m && m.name === connector })
    if (!name || !monitor) return false
    var entries = setting("displays", []).slice(), current = displaySettings(monitor), index = entries.indexOf(current)
    var entry = Object.assign(displayEntry(monitor), { name: name })
    if (index < 0) entries.push(entry); else entries[index] = entry
    return saveDisplays(entries)
  }
  function setDisplayIcon(connector, icon) {
    var monitor = Hyprland.monitors.values.find(function(m) { return m && m.name === connector })
    if (!icon || !monitor) return false
    var entries = setting("displays", []).slice(), current = displaySettings(monitor), index = entries.indexOf(current)
    var entry = Object.assign(displayEntry(monitor), { icon: icon })
    if (index < 0) entries.push(entry); else entries[index] = entry
    return saveDisplays(entries)
  }
  function moveDisplayOrder(connector, direction) {
    var monitors = orderedMonitors(), index = monitors.findIndex(function(m) { return m.name === connector }), destination = index + direction
    if (index < 0 || destination < 0 || destination >= monitors.length) return false
    monitors.splice(destination, 0, monitors.splice(index, 1)[0])
    var existing = setting("displays", []), matched = monitors.map(function(m) { return displaySettings(m) })
    return saveDisplays(monitors.map(function(m) { return displayEntry(m) }).concat(
      existing.filter(function(entry) { return matched.indexOf(entry) < 0 })))
  }
  function displaySettings(monitor) {
    if (!monitor || typeof monitor.name !== "string") return {}
    var entries = setting("displays", []), monitors = Hyprland.monitors.values
    for (var i = 0; i < entries.length; ++i) {
      var entry = entries[i]
      if (!entry.make || !entry.model) continue
      var matches = monitors.filter(function(candidate) {
        var state = candidate && candidate.lastIpcObject
        return state && state.make === entry.make && state.model === entry.model && (!entry.serial || state.serial === entry.serial)
      })
      if (matches.length === 1 && matches[0].name === monitor.name) return entry
    }
    for (var j = 0; j < entries.length; ++j) if (entries[j].connector === monitor.name) return entries[j]
    return { name: monitor.name, icon: monitor.name.indexOf("eDP") === 0 ? "\uf109" : "\uf108" }
  }
  function orderedMonitors() {
    return Hyprland.monitors.values.filter(function(m) {
      return m && typeof m.name === "string" && m.name !== "" && isPresented(m.lastIpcObject)
    }).sort(function(a, b) {
      var ar = displayRanks[a.name] === undefined ? Infinity : displayRanks[a.name]
      var br = displayRanks[b.name] === undefined ? Infinity : displayRanks[b.name]
      if (ar !== br) return ar - br
      if (a.x !== b.x) return a.x - b.x
      return a.name.localeCompare(b.name)
    })
  }
  function workspaceById(id) {
    return Hyprland.workspaces.values.find(function(workspace) { return workspace && workspace.id === id }) || null
  }
  function workspacesFor(monitor) {
    return monitor && workspaceCatalog[monitor.name] ? workspaceCatalog[monitor.name] : []
  }
  function workspaceHasWindows(workspace) {
    if (!workspace) return false
    if (workspace.toplevels && workspace.toplevels.values)
      return workspace.toplevels.values.length > 0
    var state = workspace.lastIpcObject
    return state && typeof state.windows === "number" && state.windows > 0
  }

  // Opening a declared-but-uncreated workspace needs a dispatcher call, and the
  // syntax depends on how the compositor is configured. A Lua config (Omarchy's
  // default) evaluates /dispatch as Lua and rejects a bare `workspace 7`; it
  // wants the same hl.dsp.focus call the stock Omarchy widget issues. A classic
  // .conf config wants the opposite. usingLua picks the likely form and the exit
  // status falls back to the other one, because a rejected dispatch exits
  // non-zero and is silent otherwise. usingLua is false until the Hyprland
  // object settles, so the fallback is what makes the first click reliable.
  property int pendingWorkspaceId: 0
  property bool workspaceRetried: false
  function workspaceDispatchRequest(id, luaSyntax) {
    return luaSyntax ? "hl.dsp.focus({ workspace = \"" + id + "\" })" : "workspace " + id
  }
  function focusWorkspace(id) {
    if (!Number.isInteger(id) || id <= 0 || id > 2147483647) return
    var workspace = workspaceById(id)
    if (workspace) {
      workspace.activate()
      return
    }
    if (workspaceCommand.running) return
    pendingWorkspaceId = id
    workspaceRetried = false
    workspaceCommand.command = ["hyprctl", "dispatch",
      workspaceDispatchRequest(id, Hyprland.usingLua === true)]
    workspaceCommand.running = true
  }

  Process {
    id: workspaceCommand
    onExited: function(code, status) {
      var retried = root.workspaceRetried
      var id = root.pendingWorkspaceId
      root.pendingWorkspaceId = 0
      root.workspaceRetried = false
      if (code === 0 && status === 0 || retried || id <= 0) return
      root.pendingWorkspaceId = id
      root.workspaceRetried = true
      workspaceCommand.command = ["hyprctl", "dispatch",
        root.workspaceDispatchRequest(id, !(Hyprland.usingLua === true))]
      workspaceCommand.running = true
    }
  }

  implicitWidth: groups.implicitWidth
  implicitHeight: groups.implicitHeight
  SettingsPanel { id: settingsPanel; bar: root.bar; workspaceWidget: root }
  GridLayout {
    id: groups
    columns: root.vertical ? 1 : Math.max(1, monitorRepeater.count)
    columnSpacing: Style.space(7); rowSpacing: Style.space(2)
    Repeater {
      id: monitorRepeater
      model: root.orderedMonitors()
      delegate: GridLayout {
        id: group
        required property var modelData
        readonly property string connector: modelData ? modelData.name : ""
        readonly property var display: root.displaySettings(modelData)
        columns: root.vertical ? 1 : 2; columnSpacing: 0; rowSpacing: 0
        WidgetButton {
          id: displayButton
          bar: root.bar
          active: group.connector !== "" && root.cursorTracker && root.cursorTracker.cursorDisplayName === group.connector
          text: group.display.name || group.connector
          labelVisible: false
          implicitWidth: root.vertical ? root.barSize : displayLabel.implicitWidth + scaledHorizontalMargin * 2
          Row {
            id: displayLabel
            anchors.centerIn: parent; spacing: Style.space(6)
            readonly property color labelColor: parent.active ? parent.activeColor : parent.foreground
            Text { width: Style.space(22); text: group.display.icon || "\uf108"; horizontalAlignment: Text.AlignHCenter; color: displayLabel.labelColor; font.family: parent.parent.fontFamily; font.pixelSize: parent.parent.fontSize; renderType: Text.NativeRendering }
            Text { visible: !root.setting("iconOnly", false) && !root.vertical; text: group.display.name || group.connector; color: displayLabel.labelColor; font.family: parent.parent.fontFamily; font.pixelSize: parent.parent.fontSize; renderType: Text.NativeRendering }
          }
          tooltipText: (group.display.name || group.connector) + " · " + group.connector + "\nRight-click to customize this menubar"
          horizontalMargin: 4; fixedHeight: root.barSize
          onPressed: function(button) {
            if (button === Qt.RightButton) settingsPanel.toggle()
            else if (button === Qt.LeftButton && group.modelData.activeWorkspace) group.modelData.activeWorkspace.activate()
          }
        }
        GridLayout {
          columns: root.vertical ? 1 : Math.max(1, workspaceRepeater.count); columnSpacing: 0; rowSpacing: 0
          Repeater {
            id: workspaceRepeater
            model: root.workspacesFor(group.modelData)
            delegate: WidgetButton {
              required property int modelData
              readonly property var workspace: root.workspaceById(modelData)
              readonly property bool shown: group.modelData.activeWorkspace && group.modelData.activeWorkspace.id === modelData
              readonly property bool focused: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData
              bar: root.bar
              text: shown ? "[" + modelData + "]" : String(modelData)
              tooltipText: (group.display.name || group.connector) + " · Workspace " + modelData + (focused ? " · Keyboard focus" : shown ? " · Visible" : "")
              active: focused
              dimmed: !shown && !root.workspaceHasWindows(workspace)
              horizontalMargin: 4; fixedHeight: root.barSize
              onPressed: function(button) { if (button === Qt.LeftButton) root.focusWorkspace(modelData) }
              Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: parent.width - Style.space(8); height: Style.space(2); color: parent.activeColor; visible: parent.focused }
            }
          }
        }
      }
    }
  }
}
