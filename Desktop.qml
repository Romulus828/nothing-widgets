import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "widgets"
import "components/Format.js" as F

// Service root for the Nothing desktop widgets. The shell instantiates this
// once at startup and injects `shell` / `manifest`. It owns:
//   - the settings, read inline from this plugin's entry in shell.json
//   - one long-running metrics collector (collector.py, JSON lines)
//   - layer-shell windows on the Bottom layer (above the wallpaper, below
//     windows): one per screen and screen corner that hosts a widget, with
//     the widgets that share a corner stacked in a column
//   - the `nothing-widgets` IPC target: omarchy-shell nothing-widgets toggle
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.romulus828.nothing-widgets"

  // Absolute path of this plugin directory, for spawning collector.py.
  readonly property string sourceDir: {
    if (manifest && manifest.__sourceDir) return String(manifest.__sourceDir)
    var url = String(Qt.resolvedUrl("."))
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }
  readonly property string collectorPath: sourceDir + "/collector.py"

  // ------------------------------------------------------------- settings
  //
  // Top-level keys are shared by every widget; `widgets.<name>` holds a
  // widget's own keys and may override any shared one. For compatibility the
  // monitor also reads its keys (position, tiles, sensors, clickCommand) from
  // the top level.

  readonly property var widgetTypes: ["monitor", "battery", "clock"]

  readonly property var sharedDefaults: ({
    marginX: 16,
    marginY: 16,
    scale: 1.0,
    interval: 2,
    screen: "",                // "" = every screen, else a connector name such as "eDP-1"
    visible: true,             // master switch, what show/hide/toggle flip
    tileAlpha: 1.0
  })

  readonly property var widgetDefaults: ({
    monitor: {
      visible: true,
      position: "top-left",    // top-left | top | top-right | left | center | right | bottom-left | bottom | bottom-right
      tiles: ["cpu", "gpu", "mem", "thermal", "disk", "net"],
      sensors: [],             // thermal rows to show by id (cpu, gpu, nvme, mem, wifi, ambient, battery); empty = all
      clickCommand: "omarchy-launch-or-focus-tui btop"
    },
    battery: {
      visible: true,           // still hidden while the machine reports no battery
      position: "top-right",
      lowAt: 15,
      clickCommand: ""
    },
    clock: {
      visible: true,
      position: "top-right",   // stacks under the battery
      format: "auto",          // auto | 12h | 24h
      doneCommand: "notify-send -u critical 'Timer done'",
      doneSound: "default",    // "default" = sounds/timer.wav, "" = silent, or a path to a wav/ogg
      clickCommand: ""
    }
  })

  readonly property var entry: {
    var cfg = shell ? shell.shellConfig : null
    if (!Util.isPlainObject(cfg) || !Array.isArray(cfg.plugins)) return ({})
    for (var i = 0; i < cfg.plugins.length; i++) {
      var e = cfg.plugins[i]
      if (Util.isPlainObject(e) && String(e.id || "") === pluginId) return e
    }
    return ({})
  }

  function present(v) { return v !== undefined && v !== null }

  function setting(key) {
    return present(entry[key]) ? entry[key] : sharedDefaults[key]
  }

  function widgetEntry(name) {
    var w = entry.widgets
    return Util.isPlainObject(w) && Util.isPlainObject(w[name]) ? w[name] : ({})
  }

  function widgetSetting(name, key) {
    var w = widgetEntry(name)
    if (present(w[key])) return w[key]
    var shared = sharedDefaults[key] !== undefined
    if (key !== "visible" && (shared || name === "monitor") && present(entry[key])) return entry[key]
    var d = widgetDefaults[name] || ({})
    if (d[key] !== undefined) return d[key]
    return sharedDefaults[key]
  }

  function widgetScale(name) { return Math.max(0.5, Math.min(3, Number(widgetSetting(name, "scale")) || 1)) }
  function widgetAlpha(name) { return Util.clampAlpha(Number(widgetSetting(name, "tileAlpha"))) }
  function widgetVisible(name) { return widgetSetting(name, "visible") !== false }

  readonly property real interval: Math.max(0.5, Number(setting("interval")) || 2)

  // Visibility is persisted on the shell.json entry so a toggle survives a
  // restart; `shown` mirrors the master switch and is what the windows bind to.
  property bool shown: true
  onEntryChanged: {
    shown = setting("visible") !== false
    timerRestore()
  }
  Component.onCompleted: {
    shown = setting("visible") !== false
    syncCollector()
    timerRestore()
  }

  function persist(mutate) {
    if (!(shell && typeof shell.updateEntryInline === "function" && entry.id)) return false
    var merged = Util.cloneJson(entry)
    mutate(merged)
    shell.updateEntryInline(pluginId, merged)
    return true
  }

  function setShown(value) {
    shown = value === true
    persist(function(e) { e.visible = shown })
  }

  function setWidgetShown(name, value) {
    if (widgetTypes.indexOf(name) === -1) return false
    return persist(function(e) {
      if (!Util.isPlainObject(e.widgets)) e.widgets = {}
      if (!Util.isPlainObject(e.widgets[name])) e.widgets[name] = {}
      e.widgets[name].visible = value === true
    })
  }

  // ------------------------------------------------------------- timer
  //
  // One countdown shared by every screen. `timerEndsAt` is an epoch ms while
  // running, `timerPausedRemaining` is >= 0 while paused, and a finished
  // timer sits at zero with `timerDone` until dismissed or 2 minutes pass.
  // The state is persisted on the plugin entry so a shell restart keeps it.

  property double timerEndsAt: 0
  property double timerDurationMs: 0
  property double timerPausedRemaining: -1
  property bool timerDone: false
  property double timerNow: Date.now()

  readonly property bool timerActive: timerEndsAt > 0 || timerPausedRemaining >= 0
  readonly property bool timerPaused: timerPausedRemaining >= 0 && !timerDone
  readonly property double timerRemainingMs: timerPausedRemaining >= 0 ? timerPausedRemaining : Math.max(0, timerEndsAt - timerNow)

  Timer {
    interval: 250
    running: root.timerEndsAt > 0 && !root.timerDone
    repeat: true
    onTriggered: {
      root.timerNow = Date.now()
      if (root.timerEndsAt - root.timerNow <= 0) root.timerFinish()
    }
  }

  Timer {
    id: timerDismiss
    interval: 120000
    repeat: false
    onTriggered: root.timerStop()
  }

  function timerStart(ms) {
    if (!(ms > 0)) return false
    timerDone = false
    timerDismiss.stop()
    timerDurationMs = ms
    timerPausedRemaining = -1
    timerNow = Date.now()
    timerEndsAt = timerNow + ms
    timerPersist()
    return true
  }

  function timerPause() {
    if (!timerActive || timerPaused || timerDone) return
    timerNow = Date.now()
    timerPausedRemaining = Math.max(0, timerEndsAt - timerNow)
    timerEndsAt = 0
    timerPersist()
  }

  function timerResume() {
    if (!timerPaused) return
    timerNow = Date.now()
    timerEndsAt = timerNow + timerPausedRemaining
    timerPausedRemaining = -1
    timerPersist()
  }

  function timerToggle() { if (timerPaused) timerResume(); else timerPause() }

  function timerStop() {
    timerDismiss.stop()
    timerEndsAt = 0
    timerPausedRemaining = -1
    timerDurationMs = 0
    timerDone = false
    timerPersist()
  }

  function timerFinish() {
    timerEndsAt = 0
    timerPausedRemaining = 0
    timerDone = true
    timerDismiss.restart()
    var cmd = String(widgetSetting("clock", "doneCommand") || "")
    if (cmd) Util.execDetached(cmd)
    playDoneSound()
    timerPersist()
  }

  // Three beeps through whichever player the machine has. The default file
  // ships with the plugin; a custom path or "" replaces or silences it.
  function playDoneSound() {
    var snd = String(widgetSetting("clock", "doneSound"))
    if (snd === "" || snd === "none" || snd === "false") return
    var path = snd === "default" || snd === "true" ? sourceDir + "/sounds/timer.wav" : snd
    Quickshell.execDetached(["bash", "-c",
      'pw-play "$1" 2>/dev/null || paplay "$1" 2>/dev/null || aplay -q "$1" 2>/dev/null || ffplay -nodisp -autoexit -loglevel quiet "$1"',
      "bash", path])
  }

  function timerPersist() {
    persist(function(e) {
      if (!Util.isPlainObject(e.widgets)) e.widgets = {}
      if (!Util.isPlainObject(e.widgets.clock)) e.widgets.clock = {}
      if (timerActive && !timerDone) {
        e.widgets.clock.timer = { endsAt: timerEndsAt, durationMs: timerDurationMs, pausedRemaining: timerPausedRemaining }
      } else {
        delete e.widgets.clock.timer
      }
    })
  }

  // Runs at startup and again on the first settings load, since the entry
  // may not be populated yet when the service completes.
  property bool timerRestored: false
  function timerRestore() {
    if (timerRestored || !entry.id) return
    timerRestored = true
    var t = widgetEntry("clock").timer
    if (!Util.isPlainObject(t)) return
    var dur = Number(t.durationMs) || 0
    if (Number(t.pausedRemaining) >= 0) {
      timerDurationMs = dur
      timerPausedRemaining = Number(t.pausedRemaining)
      timerEndsAt = 0
    } else if (Number(t.endsAt) > Date.now()) {
      timerDurationMs = dur
      timerPausedRemaining = -1
      timerEndsAt = Number(t.endsAt)
    }
    // an end time already in the past while the shell was down is just dropped
  }

  // "auto" clock format follows the bar's clock widget (its `format` in
  // shell.json), falling back to the locale.
  readonly property string clockFormat: {
    var f = String(widgetSetting("clock", "format") || "auto")
    if (f === "12h" || f === "24h") return f
    var cfg = shell ? shell.shellConfig : null
    var layout = Util.isPlainObject(cfg) && Util.isPlainObject(cfg.bar) && Util.isPlainObject(cfg.bar.layout) ? cfg.bar.layout : null
    if (layout) {
      var sections = ["left", "center", "right"]
      for (var i = 0; i < sections.length; i++) {
        var items = layout[sections[i]]
        if (!Array.isArray(items)) continue
        for (var j = 0; j < items.length; j++) {
          var w = items[j]
          if (Util.isPlainObject(w) && w.id === "omarchy.clock" && typeof w.format === "string") {
            return w.format.indexOf("AP") !== -1 || w.format.indexOf("ap") !== -1 ? "12h" : "24h"
          }
        }
      }
    }
    return Qt.locale().timeFormat(Locale.ShortFormat).indexOf("AP") !== -1 ? "12h" : "24h"
  }

  // ------------------------------------------------------------- reminders
  //
  // Omarchy reminders (`omarchy reminder 25 "Tea"`, SUPER+CTRL+R) are systemd
  // user timers. The clock tile counts down to the next one, so this polls
  // the list while a clock widget is on screen. Manual timers take priority.

  property var reminders: []         // [{unit, label, message, minutes, at}] sorted by `at` (epoch ms)
  readonly property var nextReminder: reminders.length ? reminders[0] : null
  readonly property bool clockWanted: shown && widgetVisible("clock")

  Process {
    id: reminderPoll
    command: [root.omarchyPath + "/bin/omarchy-reminder", "show", "--json"]
    stdout: StdioCollector {
      onStreamFinished: root.ingestReminders(text)
    }
  }

  Timer {
    interval: 5000
    running: root.clockWanted
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshReminders()
  }

  function refreshReminders() {
    if (!reminderPoll.running) reminderPoll.running = true
  }

  function ingestReminders(text) {
    var out = []
    try {
      var obj = JSON.parse(String(text || "").trim() || "{}")
      var list = Util.isPlainObject(obj) && Array.isArray(obj.reminders) ? obj.reminders : []
      var now = Date.now()
      for (var i = 0; i < list.length; i++) {
        var r = list[i]
        if (!Util.isPlainObject(r)) continue
        var at = Number(r.at) * 1000
        if (!(at > now)) continue
        out.push({
          unit: String(r.unit || ""),
          label: String(r.label || r.message || "reminder"),
          message: String(r.message || ""),
          minutes: Number(r.minutes) || 0,
          at: at
        })
      }
      out.sort(function(a, b) { return a.at - b.at })
    } catch (e) {
      console.warn("nothing-widgets: bad reminder list:", e)
    }
    // keep the array identity stable unless something changed
    var same = out.length === reminders.length
    for (var j = 0; same && j < out.length; j++) {
      same = out[j].unit === reminders[j].unit && out[j].at === reminders[j].at && out[j].label === reminders[j].label
    }
    if (!same) reminders = out
  }

  function timerStatus() {
    if (!timerActive) return "idle"
    if (timerDone) return "done"
    return (timerPaused ? "paused " : "running ") + F.countdown(timerRemainingMs)
  }

  // ------------------------------------------------------------- data

  property var sample: ({})
  property double lastSampleAt: 0
  property string lastError: ""
  readonly property bool stale: lastSampleAt > 0 && (Date.now() - lastSampleAt) > Math.max(10000, interval * 5000)

  function ingest(line) {
    var text = String(line || "").trim()
    if (!text) return
    try {
      var obj = JSON.parse(text)
      if (!Util.isPlainObject(obj)) return
      sample = obj
      lastSampleAt = Date.now()
      if (Array.isArray(obj.errors) && obj.errors.length) lastError = String(obj.errors[0])
      else lastError = ""
    } catch (e) {
      console.warn("nothing-widgets: bad collector line:", e)
    }
  }

  // Quickshell resets Process.running to false when the child exits, which
  // silently breaks a declarative `running:` binding, so the collector is
  // driven imperatively: syncCollector() starts it when the widget is shown
  // and stops it when hidden; onExited schedules a restart with backoff.
  property int restartDelayMs: 1000

  function syncCollector() {
    if (shown && !collector.running) collector.running = true
    else if (!shown && collector.running) collector.signal(15)
  }

  // A running child keeps its argv, so a new interval (or a manual refresh)
  // bounces it and the exit path relaunches with the current command.
  function restartCollector() {
    if (collector.running) collector.signal(15)
    else syncCollector()
  }

  onShownChanged: syncCollector()
  onIntervalChanged: if (collector.running) collector.signal(15)

  Process {
    id: collector
    // -u: line-buffered stdout through the pipe. -B: never write __pycache__
    // into the plugin directory (any file written there hot-reloads every plugin).
    command: ["python3", "-u", "-B", root.collectorPath, "--interval", String(root.interval)]
    environment: ({ PYTHONUNBUFFERED: "1", PYTHONDONTWRITEBYTECODE: "1" })
    stdout: SplitParser {
      onRead: function(line) {
        root.ingest(line)
        root.restartDelayMs = 1000
      }
    }
    stderr: SplitParser {
      onRead: function(line) { if (String(line).trim()) console.warn("nothing-widgets collector:", line) }
    }
    onExited: function(exitCode, exitStatus) {
      if (!root.shown) return
      if (exitCode !== 0 && exitCode !== 15) console.warn("nothing-widgets: collector exited", exitCode, exitStatus)
      restartTimer.interval = root.restartDelayMs
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 1000
    repeat: false
    onTriggered: {
      root.restartDelayMs = Math.min(root.restartDelayMs * 2, 30000)
      root.syncCollector()
    }
  }

  // Re-evaluate `stale` without needing a sample.
  Timer {
    interval: 5000
    running: root.shown
    repeat: true
    onTriggered: root.lastSampleAtChanged()
  }

  // ------------------------------------------------------------- ipc

  IpcHandler {
    target: "nothing-widgets"

    function show(): string { root.setShown(true); return "ok" }
    function hide(): string { root.setShown(false); return "ok" }
    function toggle(): string { root.setShown(!root.shown); return root.shown ? "shown" : "hidden" }
    // Per-widget switches: monitor | battery
    function showWidget(name: string): string { return root.setWidgetShown(name, true) ? "ok" : "unknown widget " + name }
    function hideWidget(name: string): string { return root.setWidgetShown(name, false) ? "ok" : "unknown widget " + name }
    function toggleWidget(name: string): string {
      if (root.widgetTypes.indexOf(name) === -1) return "unknown widget " + name
      var next = !root.widgetVisible(name)
      root.setWidgetShown(name, next)
      return next ? "shown" : "hidden"
    }
    function refresh(): string { root.restartCollector(); root.refreshReminders(); return "ok" }
    function reminders(): string { root.refreshReminders(); return JSON.stringify(root.reminders) }
    // Timer: `timer 25m` | `timer 10:00` | `timer 1h30m` | `timer pause` | `timer resume` | `timer toggle` | `timer stop` | `timer status`
    function timer(spec: string): string {
      var s = String(spec || "").trim().toLowerCase()
      if (s === "" || s === "status") return root.timerStatus()
      if (s === "stop" || s === "cancel" || s === "clear") { root.timerStop(); return "stopped" }
      if (s === "pause") { root.timerPause(); return root.timerStatus() }
      if (s === "resume") { root.timerResume(); return root.timerStatus() }
      if (s === "toggle") { root.timerToggle(); return root.timerStatus() }
      var ms = F.parseDuration(s)
      if (!(ms > 0)) return "usage: timer 25m | 10:00 | 1h30m | pause | resume | toggle | stop | status"
      root.timerStart(ms)
      return root.timerStatus()
    }
    // Render the first visible window's widgets to a PNG without touching the
    // screen. Useful for sharing a look or checking a layout change.
    function snapshot(path: string): string { return root.snapshotTo(path, "") }
    // Same, for the window at a given position (e.g. "top-left").
    function snapshotAt(path: string, position: string): string { return root.snapshotTo(path, String(position || "")) }
    function debug(): string {
      return JSON.stringify(root.contentItems.map(function(c) { return c.describe() }))
    }
    function status(): string {
      var widgets = {}
      for (var i = 0; i < root.widgetTypes.length; i++) {
        var n = root.widgetTypes[i]
        widgets[n] = { visible: root.widgetVisible(n), position: String(root.widgetSetting(n, "position")), scale: root.widgetScale(n) }
      }
      return JSON.stringify({
        shown: root.shown,
        collectorRunning: collector.running,
        lastSampleAgeMs: root.lastSampleAt ? Date.now() - root.lastSampleAt : null,
        lastError: root.lastError,
        widgets: widgets,
        timer: root.timerStatus(),
        reminders: root.reminders.length,
        windows: root.windowModel.map(function(w) { return w.key }),
        screens: Quickshell.screens.map(function(s) { return s.name })
      })
    }
  }

  // ------------------------------------------------------------- windows

  function snapshotTo(path, position) {
    var target = String(path || "")
    if (!target) return "usage: snapshot /absolute/path.png"
    var item = firstContentItem(position)
    if (!item) return "no visible widget"
    var ok = item.grabToImage(function(result) {
      if (!result.saveToFile(target)) console.warn("nothing-widgets: snapshot failed to save", target)
    }, Qt.size(Math.ceil(item.width * 2), Math.ceil(item.height * 2)))
    return ok ? "ok" : "grab failed"
  }

  property var contentItems: []

  function registerContent(item) {
    var next = contentItems.slice()
    if (next.indexOf(item) === -1) next.push(item)
    contentItems = next
  }

  function unregisterContent(item) {
    contentItems = contentItems.filter(function(m) { return m !== item })
  }

  function firstContentItem(position) {
    for (var i = 0; i < contentItems.length; i++) {
      var m = contentItems[i]
      if (!(m && m.visible && m.width > 0 && m.height > 0)) continue
      if (position && m.windowPosition !== position) continue
      return m
    }
    return null
  }

  // One window per (screen, position) that has at least one enabled widget.
  // Depends only on settings and the screen list, so it is rebuilt when those
  // change and never per sample.
  readonly property var windowModel: {
    var out = []
    var screens = Quickshell.screens
    for (var s = 0; s < screens.length; s++) {
      var screen = screens[s]
      var groups = {}
      var order = []
      for (var i = 0; i < widgetTypes.length; i++) {
        var name = widgetTypes[i]
        if (!widgetVisible(name)) continue
        var filter = String(widgetSetting(name, "screen") || "")
        if (filter !== "" && String(screen.name) !== filter) continue
        var pos = String(widgetSetting(name, "position") || "top-right")
        if (!groups[pos]) { groups[pos] = []; order.push(pos) }
        groups[pos].push(name)
      }
      for (var p = 0; p < order.length; p++) {
        out.push({
          key: String(screen.name) + ":" + order[p],
          screen: screen,
          position: order[p],
          widgets: groups[order[p]],
          marginX: Math.round(Number(widgetSetting(groups[order[p]][0], "marginX"))),
          marginY: Math.round(Number(widgetSetting(groups[order[p]][0], "marginY")))
        })
      }
    }
    return out
  }

  Variants {
    model: root.windowModel

    PanelWindow {
      id: win
      required property var modelData

      screen: modelData.screen
      readonly property string vAnchor: modelData.position.indexOf("top") === 0 ? "top"
        : modelData.position.indexOf("bottom") === 0 ? "bottom" : "center"
      readonly property string hAnchor: modelData.position.indexOf("left") !== -1 ? "left"
        : modelData.position.indexOf("right") !== -1 ? "right" : "center"

      readonly property bool wanted: root.shown && content.implicitHeight > 0
      visible: wanted && !remapGuard.remapping

      ScreenMoveRemap {
        id: remapGuard
        window: win
      }

      color: "transparent"
      WlrLayershell.namespace: "nothing-widgets"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      // Claim no space, but stay out of the bar's reserved strip.
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: 0
      aboveWindows: false

      anchors {
        top: win.vAnchor === "top"
        bottom: win.vAnchor === "bottom"
        left: win.hAnchor === "left"
        right: win.hAnchor === "right"
      }
      margins {
        top: win.vAnchor === "top" ? modelData.marginY : 0
        bottom: win.vAnchor === "bottom" ? modelData.marginY : 0
        left: win.hAnchor === "left" ? modelData.marginX : 0
        right: win.hAnchor === "right" ? modelData.marginX : 0
      }

      implicitWidth: Math.max(1, Math.ceil(content.implicitWidth))
      implicitHeight: Math.max(1, Math.ceil(content.implicitHeight))

      function hasWidget(name) { return modelData.widgets.indexOf(name) !== -1 }

      // Widgets sharing this corner, stacked with the same 8 px gutter the
      // monitor uses between its own tiles. Positioned by hand rather than
      // with a Column: positioners only lay out while their window renders,
      // and this window only renders once it knows it has content.
      Item {
        id: content
        readonly property string windowPosition: win.modelData.position
        readonly property real gutter: 8
        // `visible` reads back *effective* visibility, which is false while
        // this window is hidden, so the stacking is computed from the slots'
        // own conditions rather than from their visible flags.
        readonly property bool monitorOn: monitorSlot.active && monitorSlot.item !== null && monitorSlot.item.wanted
        readonly property bool batteryOn: batterySlot.active && batterySlot.item !== null && batterySlot.item.wanted
        readonly property bool clockOn: clockSlot.active && clockSlot.item !== null && clockSlot.item.wanted
        readonly property real monitorH: monitorOn ? monitorSlot.implicitHeight : 0
        readonly property real batteryH: batteryOn ? batterySlot.implicitHeight : 0
        readonly property real clockH: clockOn ? clockSlot.implicitHeight : 0
        // Stack order is monitor, battery, clock; each slot starts after the
        // visible ones above it.
        readonly property real batteryY: monitorH > 0 ? monitorH + gutter : 0
        readonly property real clockY: batteryY + (batteryH > 0 ? batteryH + gutter : 0)
        implicitWidth: Math.max(monitorOn ? monitorSlot.implicitWidth : 0, batteryOn ? batterySlot.implicitWidth : 0, clockOn ? clockSlot.implicitWidth : 0)
        implicitHeight: clockH > 0 ? clockY + clockH : (batteryH > 0 ? batteryY + batteryH : monitorH)
        width: implicitWidth
        height: implicitHeight
        Component.onCompleted: root.registerContent(content)
        Component.onDestruction: root.unregisterContent(content)

        function describe() {
          function slot(k) {
            return { active: k.active, visible: k.visible, y: k.y, ih: k.implicitHeight,
                     item: k.item ? { wanted: k.item.wanted, ih: k.item.implicitHeight } : null }
          }
          return { pos: windowPosition, w: width, h: height, winVisible: win.visible, wanted: win.wanted,
                   monitor: slot(monitorSlot), battery: slot(batterySlot), clock: slot(clockSlot) }
        }

        Loader {
          id: monitorSlot
          y: 0
          active: win.hasWidget("monitor")
          visible: content.monitorOn
          sourceComponent: SystemMonitor {
            sample: root.sample
            stale: root.stale
            scale: root.widgetScale("monitor")
            tiles: Array.isArray(root.widgetSetting("monitor", "tiles")) ? root.widgetSetting("monitor", "tiles") : root.widgetDefaults.monitor.tiles
            sensors: Array.isArray(root.widgetSetting("monitor", "sensors")) ? root.widgetSetting("monitor", "sensors") : []
            tileAlpha: root.widgetAlpha("monitor")
            clickCommand: String(root.widgetSetting("monitor", "clickCommand") || "")
          }
        }

        Loader {
          id: batterySlot
          y: content.batteryY
          active: win.hasWidget("battery")
          visible: content.batteryOn
          sourceComponent: Battery {
            sample: root.sample
            stale: root.stale
            scale: root.widgetScale("battery")
            tileAlpha: root.widgetAlpha("battery")
            clickCommand: String(root.widgetSetting("battery", "clickCommand") || "")
            lowAt: Math.round(Number(root.widgetSetting("battery", "lowAt")) || 15)
          }
        }

        Loader {
          id: clockSlot
          y: content.clockY
          active: win.hasWidget("clock")
          visible: content.clockOn
          sourceComponent: Clock {
            host: root
            reminder: root.nextReminder
            reminderCount: root.reminders.length
            scale: root.widgetScale("clock")
            tileAlpha: root.widgetAlpha("clock")
            format: root.clockFormat
            clickCommand: String(root.widgetSetting("clock", "clickCommand") || "")
          }
        }
      }
    }
  }
}
