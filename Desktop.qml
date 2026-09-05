import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "widgets"

// Service root for the Nothing desktop widgets. The shell instantiates this
// once at startup and injects `shell` / `manifest`. It owns:
//   - the settings, read inline from this plugin's entry in shell.json
//   - one long-running metrics collector (collector.py, JSON lines)
//   - one layer-shell window per screen on the Bottom layer (above the
//     wallpaper, below windows) that hosts the widget
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

  readonly property var defaults: ({
    position: "top-right",     // top-left | top | top-right | left | center | right | bottom-left | bottom | bottom-right
    marginX: 16,
    marginY: 16,
    scale: 1.0,
    interval: 2,
    screen: "",                // "" = every screen, else a connector name such as "eDP-1"
    visible: true,
    columns: 2,
    tiles: ["cpu", "gpu", "mem", "thermal", "disk", "net"],
    sensors: [],               // thermal rows to show by id (cpu, gpu, nvme, mem, wifi, ambient, battery); empty = all
    tileAlpha: 1.0,
    clickCommand: "omarchy-launch-or-focus-tui btop"
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

  function setting(key) {
    var v = entry[key]
    return v === undefined || v === null ? defaults[key] : v
  }

  readonly property string position: String(setting("position"))
  readonly property int marginX: Math.round(Number(setting("marginX")))
  readonly property int marginY: Math.round(Number(setting("marginY")))
  readonly property real scale: Math.max(0.5, Math.min(3, Number(setting("scale")) || 1))
  readonly property real interval: Math.max(0.5, Number(setting("interval")) || 2)
  readonly property string screenFilter: String(setting("screen") || "")
  readonly property int columns: Math.max(1, Math.min(3, Math.round(Number(setting("columns")) || 2)))
  readonly property var tiles: Array.isArray(setting("tiles")) ? setting("tiles") : defaults.tiles
  readonly property var sensors: Array.isArray(setting("sensors")) ? setting("sensors") : []
  readonly property real tileAlpha: Util.clampAlpha(Number(setting("tileAlpha")))
  readonly property string clickCommand: String(setting("clickCommand") || "")

  // Visibility is persisted on the shell.json entry so a toggle survives a
  // restart; `shown` mirrors it and is what the windows bind to.
  property bool shown: true
  onEntryChanged: shown = setting("visible") !== false
  Component.onCompleted: {
    shown = setting("visible") !== false
    syncCollector()
  }

  function setShown(value) {
    shown = value === true
    if (shell && typeof shell.updateEntryInline === "function" && entry.id) {
      var merged = Util.cloneJson(entry)
      merged.visible = shown
      shell.updateEntryInline(pluginId, merged)
    }
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
    function refresh(): string { root.restartCollector(); return "ok" }
    // Render the widget to a PNG without touching the screen. Useful for
    // sharing a look or checking a layout change while windows cover it.
    function snapshot(path: string): string {
      var target = String(path || "")
      if (!target) return "usage: snapshot /absolute/path.png"
      var item = root.firstMonitorItem()
      if (!item) return "no visible widget"
      var ok = item.grabToImage(function(result) {
        if (!result.saveToFile(target)) console.warn("nothing-widgets: snapshot failed to save", target)
      }, Qt.size(Math.ceil(item.width * 2), Math.ceil(item.height * 2)))
      return ok ? "ok" : "grab failed"
    }
    function status(): string {
      return JSON.stringify({
        shown: root.shown,
        collectorRunning: collector.running,
        lastSampleAgeMs: root.lastSampleAt ? Date.now() - root.lastSampleAt : null,
        lastError: root.lastError,
        position: root.position,
        scale: root.scale,
        screens: Quickshell.screens.map(function(s) { return s.name })
      })
    }
  }

  // ------------------------------------------------------------- windows

  property var monitorItems: []

  function registerMonitor(item) {
    var next = monitorItems.slice()
    if (next.indexOf(item) === -1) next.push(item)
    monitorItems = next
  }

  function unregisterMonitor(item) {
    monitorItems = monitorItems.filter(function(m) { return m !== item })
  }

  function firstMonitorItem() {
    for (var i = 0; i < monitorItems.length; i++) {
      var m = monitorItems[i]
      if (m && m.visible && m.width > 0) return m
    }
    return null
  }

  readonly property string vAnchor: position.indexOf("top") === 0 ? "top" : position.indexOf("bottom") === 0 ? "bottom" : "center"
  readonly property string hAnchor: {
    if (position.indexOf("left") !== -1) return "left"
    if (position.indexOf("right") !== -1) return "right"
    return "center"
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData

      screen: modelData
      readonly property bool wanted: root.shown
        && (root.screenFilter === "" || String(modelData.name) === root.screenFilter)
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
        top: root.vAnchor === "top"
        bottom: root.vAnchor === "bottom"
        left: root.hAnchor === "left"
        right: root.hAnchor === "right"
      }
      margins {
        top: root.vAnchor === "top" ? root.marginY : 0
        bottom: root.vAnchor === "bottom" ? root.marginY : 0
        left: root.hAnchor === "left" ? root.marginX : 0
        right: root.hAnchor === "right" ? root.marginX : 0
      }

      implicitWidth: Math.ceil(monitor.implicitWidth)
      implicitHeight: Math.ceil(monitor.implicitHeight)

      SystemMonitor {
        id: monitor
        sample: root.sample
        stale: root.stale
        scale: root.scale
        columns: root.columns
        tiles: root.tiles
        sensors: root.sensors
        tileAlpha: root.tileAlpha
        clickCommand: root.clickCommand
        Component.onCompleted: root.registerMonitor(monitor)
        Component.onDestruction: root.unregisterMonitor(monitor)
      }
    }
  }
}
