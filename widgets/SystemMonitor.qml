import QtQuick
import Quickshell
import qs.Commons
import "../components"
import "../components/Format.js" as F

// The system monitor widget: a 300 px column of Nothing-style tiles built
// from dot-matrix numerals and dot gauges. Every size is in logical px at
// scale 1 and multiplies by `scale`.
//
// Tiles (top to bottom):  CPU (wide)  |  GPU · MEMORY  |  THERMAL (wide)  |  DISK · NET (wide)
Item {
  id: root

  property var sample: ({})
  property bool stale: false
  property real scale: 1
  property int columns: 2
  property var tiles: ["cpu", "gpu", "mem", "thermal", "disk", "net"]
  property var sensors: []          // thermal row ids to show; empty = all
  property real tileAlpha: 1.0
  property string clickCommand: ""
  readonly property bool wanted: true   // read by the host window

  // ----------------------------------------------------------- palette

  Palette { id: pal; tileAlpha: root.tileAlpha }
  readonly property color fg: pal.fg
  readonly property color bg: pal.bg
  readonly property color accent: pal.accent
  readonly property string fontFamily: pal.fontFamily
  readonly property color dotOn: pal.dotOn
  readonly property color ink: pal.ink
  readonly property color labelColor: pal.labelColor
  readonly property color tertiary: pal.tertiary
  readonly property color dotOff: pal.dotOff
  readonly property color line: pal.line
  readonly property color tileFill: pal.tileFill
  readonly property color redText: pal.redText

  // ----------------------------------------------------------- geometry

  function u(px) { return Math.round(px * scale) }
  readonly property real gutter: u(8)
  readonly property real widgetWidth: u(300)
  readonly property real half: (widgetWidth - gutter) / 2
  readonly property real tileH: u(146)

  implicitWidth: widgetWidth
  implicitHeight: column.implicitHeight

  // ----------------------------------------------------------- data

  readonly property var cpu: sample && sample.cpu ? sample.cpu : ({})
  readonly property var gpu: sample && sample.gpu ? sample.gpu : ({})
  readonly property var mem: sample && sample.mem ? sample.mem : ({})
  readonly property var disk: sample && sample.disk ? sample.disk : ({})
  readonly property var net: sample && sample.net ? sample.net : ({})
  readonly property var temps: sample && Array.isArray(sample.temps) ? sample.temps : []
  readonly property bool hasSample: !!(sample && sample.cpu)
  readonly property bool live: hasSample && !stale

  readonly property bool gpuAwake: gpu.state === "active" || gpu.state === "idle"
  readonly property bool gpuAsleep: gpu.state === "suspended"
  readonly property int cpuLevel: F.tempLevel(cpu.temp, cpu.temp_high, cpu.temp_crit)
  readonly property int gpuLevel: gpuAwake ? F.tempLevel(gpu.temp, 83, 93) : 0
  readonly property int memLevel: F.isNum(mem.percent) && mem.percent >= 92 ? 2 : 0
  readonly property int diskLevel: F.isNum(disk.percent) && disk.percent >= 90 ? 2 : 0
  readonly property int thermalLevel: {
    var w = 0
    for (var i = 0; i < temps.length; i++) w = Math.max(w, F.tempLevel(temps[i].value, temps[i].high, temps[i].crit))
    return w
  }

  // Stable list of sensor ids for the THERMAL rows. Only reassigned when the
  // set of sensors actually changes, so the Repeater keeps its delegates and
  // each refresh is just a Canvas repaint instead of a rebuild (no flash).
  property var thermalIds: []
  function tempRow(id) {
    for (var i = 0; i < temps.length; i++) if (temps[i].id === id) return temps[i]
    return null
  }

  // Per-thread load, smoothed so the block breathes instead of flickering.
  property var coreEma: []
  onSampleChanged: {
    var ids = []
    for (var t = 0; t < temps.length; t++) {
      var row = temps[t]
      if (!row || !F.isNum(row.value)) continue
      if (sensors.length > 0 && sensors.indexOf(row.id) === -1) continue
      ids.push(row.id)
    }
    if (ids.join(",") !== thermalIds.join(",")) thermalIds = ids

    var cores = Array.isArray(cpu.cores) ? cpu.cores : []
    var next = []
    for (var i = 0; i < cores.length; i++) {
      var v = (Number(cores[i]) || 0) / 100
      var prev = i < coreEma.length ? coreEma[i] : v
      next.push(prev * 0.5 + v * 0.5)
    }
    coreEma = next
  }

  function has(id) { return tiles.indexOf(id) !== -1 }
  function tempOf(id) {
    for (var i = 0; i < temps.length; i++) if (temps[i].id === id) return temps[i].value
    return NaN
  }
  function ledFor(level) { return stale ? "hollow" : (level >= 2 ? "on" : "off") }
  function dotColor(level) { return stale ? tertiary : (level >= 2 ? accent : dotOn) }
  function textColor(level) { return level >= 2 ? redText : ink }

  // ----------------------------------------------------------- inline parts

  component Caption: Text {
    color: root.labelColor
    font.family: root.fontFamily
    font.pixelSize: Math.max(8, root.u(9))
    font.letterSpacing: 1.0 * root.scale
    font.capitalization: Font.AllUppercase
    renderType: Text.NativeRendering
  }

  component Ink: Text {
    color: root.ink
    font.family: root.fontFamily
    font.pixelSize: Math.max(8, root.u(11))
    renderType: Text.NativeRendering
  }

  // Ring gauge sized and coloured for a half tile.
  component RingTile: RingGauge {
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.u(2)
    scale: root.scale
    stale: root.stale
    ringColor: root.dotOn
    offColor: root.dotOff
    tertiary: root.tertiary
    captionColor: root.labelColor
    fontFamily: root.fontFamily
  }

  // One thermal row: name, dot bar, dot numeral.
  component ThermalRow: Item {
    id: thermalRow
    property string name: ""
    property real value: NaN
    property real high: NaN
    property real crit: NaN
    property real floor: 20           // bar starts here
    property string suffix: "°"
    property int minColumns: 15
    readonly property int level: F.tempLevel(value, high, crit)
    readonly property real topValue: F.isNum(high) ? high : (F.isNum(crit) ? crit - 10 : 90)
    width: parent ? parent.width : 0
    height: root.u(22)
    Caption {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: root.u(62)
      elide: Text.ElideRight
      text: name
      color: level >= 2 ? root.redText : root.labelColor
    }
    DotBar {
      anchors.left: parent.left
      anchors.leftMargin: root.u(66)
      anchors.right: parent.right
      anchors.rightMargin: root.u(44)
      anchors.verticalCenter: parent.verticalCenter
      height: root.u(8)
      count: 20
      pitch: width / 20
      dotRadius: Math.max(1.4, 1.9 * root.scale)
      mode: "fill"
      value: F.clamp01((thermalRow.value - thermalRow.floor) / Math.max(5, thermalRow.topValue - thermalRow.floor))
      color: root.stale ? root.tertiary : root.dotOn
      offColor: root.dotOff
    }
    DotText {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: F.isNum(thermalRow.value) ? Math.round(thermalRow.value) + thermalRow.suffix : "-"
      pitch: root.u(2)
      weight: 0.5
      minColumns: thermalRow.minColumns
      horizontalAlignment: Text.AlignRight
      color: root.dotColor(level)
    }
  }

  // ----------------------------------------------------------- layout

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: root.clickCommand ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.clickCommand) Util.execDetached(root.clickCommand)
  }

  Column {
    id: column
    width: root.widgetWidth
    spacing: root.gutter

    // ------------------------------------------------------- CPU (wide)
    Tile {
      visible: root.has("cpu")
      width: parent.width
      height: root.tileH
      unit: root.scale
      color: root.tileFill
      lineColor: root.line
      labelColor: root.labelColor
      inkColor: root.ink
      ledOnColor: root.accent
      ledOffColor: root.dotOff
      ledHollowColor: root.tertiary
      fontFamily: root.fontFamily
      label: "cpu"
      // The one red dot on a healthy desktop: lit while samples are fresh.
      led: root.live ? "on" : (root.hasSample ? "hollow" : "off")
      trailing: root.hasSample ? F.freq(root.cpu.freq_mhz) : ""
      trailingColor: root.labelColor

      // Hero: load percentage, left-aligned, 8 px pitch
      DotText {
        id: cpuHero
        anchors.left: parent.left
        anchors.top: parent.top
        text: root.hasSample ? F.pct(root.cpu.usage) : "-"
        pitch: root.u(8)
        weight: 0.39
        minColumns: 11
        ghost: 0.06
        ghostColor: root.fg
        horizontalAlignment: Text.AlignRight
        color: root.stale ? root.tertiary : root.dotOn
      }
      Text {
        anchors.left: cpuHero.right
        anchors.leftMargin: root.u(6)
        anchors.baseline: cpuHero.bottom
        anchors.baselineOffset: -root.u(2)
        text: "%"
        color: root.labelColor
        font.family: root.fontFamily
        font.pixelSize: root.u(12)
        renderType: Text.NativeRendering
      }

      // Subline: load average and thread count
      Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        spacing: root.u(6)
        Ink { text: root.sample.load ? F.load(root.sample.load[0]) : "--" }
        Caption { text: "load"; anchors.baseline: parent.children[0].baseline }
        Ink { text: root.cpu.threads ? String(root.cpu.threads) : "--"; anchors.baseline: parent.children[0].baseline }
        Caption { text: "thr"; anchors.baseline: parent.children[0].baseline }
      }

      // Right column: thread matrix over the package temperature
      DotMatrix {
        id: cores
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: root.u(2)
        columns: 5
        pitch: root.u(12)
        minRadius: Math.max(1.2, 1.5 * root.scale)
        maxRadius: Math.max(3, 4.5 * root.scale)
        values: root.coreEma
        color: root.stale ? root.tertiary : root.dotOn
        alertColor: root.accent
        alerts: {
          // a thread's dot turns red when its core is hot
          var out = []
          var ct = Array.isArray(root.cpu.core_temps) ? root.cpu.core_temps : []
          var crit = F.isNum(root.cpu.temp_crit) ? root.cpu.temp_crit : 100
          var per = ct.length ? Math.max(1, Math.round(root.coreEma.length / ct.length)) : 1
          for (var i = 0; i < root.coreEma.length; i++) {
            var t = ct[Math.min(ct.length - 1, Math.floor(i / per))]
            if (F.isNum(t) && t >= crit - 10) out.push(i)
          }
          return out
        }
      }
      DotText {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: F.isNum(root.cpu.temp) ? F.deg(root.cpu.temp) + "°C" : "-"
        pitch: root.u(4)
        weight: 0.39
        minColumns: 20
        horizontalAlignment: Text.AlignRight
        color: root.dotColor(root.cpuLevel)
      }
    }

    // ------------------------------------------------------- GPU | MEMORY
    Row {
      width: parent.width
      spacing: root.gutter
      visible: root.has("gpu") || root.has("mem")

      Tile {
        visible: root.has("gpu")
        width: root.has("mem") ? root.half : parent.width
        height: root.tileH
        unit: root.scale
        color: root.tileFill
        lineColor: root.line
        labelColor: root.labelColor
        inkColor: root.ink
        ledOnColor: root.accent
        ledOffColor: root.dotOff
        ledHollowColor: root.tertiary
        fontFamily: root.fontFamily
        label: "gpu"
        led: root.ledFor(root.gpuLevel)
        trailing: {
          if (!root.hasSample) return ""
          if (root.gpuAwake && F.isNum(root.gpu.temp)) return F.deg(root.gpu.temp) + "°C"
          if (root.gpuAsleep) return F.isNum(root.tempOf("gpu")) ? F.deg(root.tempOf("gpu")) + "°C" : "sleep"
          return ""
        }
        trailingColor: root.gpuLevel >= 2 ? root.redText : (root.gpuAwake ? root.ink : root.labelColor)

        RingTile {
          active: root.gpuAwake
          value: F.clamp01((root.gpu.util || 0) / 100)
          text: F.pct(root.gpu.util)
          unit: root.gpuAsleep ? "sleep" : (F.isNum(root.gpu.power_w) ? F.watts(root.gpu.power_w) + "w" : "%")
          dots: root.dotColor(root.gpuLevel)
        }
      }

      Tile {
        visible: root.has("mem")
        width: root.has("gpu") ? root.half : parent.width
        height: root.tileH
        unit: root.scale
        color: root.tileFill
        lineColor: root.line
        labelColor: root.labelColor
        inkColor: root.ink
        ledOnColor: root.accent
        ledOffColor: root.dotOff
        ledHollowColor: root.tertiary
        fontFamily: root.fontFamily
        label: "memory"
        led: root.ledFor(root.memLevel)
        trailing: root.hasSample ? F.gib(root.mem.total, 0) + "G" : ""
        trailingColor: root.labelColor

        RingTile {
          active: root.hasSample
          value: F.clamp01((root.mem.percent || 0) / 100)
          text: F.pct(root.mem.percent)
          unit: F.isNum(root.mem.used) ? F.gib(root.mem.used, 1) + " gb" : "%"
          dots: root.dotColor(root.memLevel)
        }
      }
    }

    // ------------------------------------------------------- THERMAL (wide)
    Tile {
      visible: root.has("thermal") || root.has("temps")
      width: parent.width
      height: thermalRows.implicitHeight + contentTop + pad
      unit: root.scale
      pad: root.u(14)
      contentTop: root.u(38)
      color: root.tileFill
      lineColor: root.line
      labelColor: root.labelColor
      inkColor: root.ink
      ledOnColor: root.accent
      ledOffColor: root.dotOff
      ledHollowColor: root.tertiary
      fontFamily: root.fontFamily
      label: "thermal"
      led: root.ledFor(root.thermalLevel)
      trailing: root.thermalLevel >= 3 ? "critical" : (root.thermalLevel >= 2 ? "hot" : "")
      trailingColor: root.redText

      Column {
        id: thermalRows
        width: parent.width
        spacing: root.u(1)

        Repeater {
          model: root.thermalIds
          delegate: ThermalRow {
            required property string modelData
            readonly property var row: root.tempRow(modelData)
            name: row ? (row.label || "") : ""
            value: row && F.isNum(row.value) ? row.value : NaN
            high: row && F.isNum(row.high) ? row.high : NaN
            crit: row && F.isNum(row.crit) ? row.crit : NaN
          }
        }
      }
    }

    // ------------------------------------------------------- DISK · NET (wide)
    Tile {
      visible: root.has("disk") || root.has("net")
      width: parent.width
      height: root.u(76)
      unit: root.scale
      pad: root.u(14)
      contentTop: root.u(34)
      color: root.tileFill
      lineColor: root.line
      labelColor: root.labelColor
      inkColor: root.ink
      ledOnColor: root.accent
      ledOffColor: root.dotOff
      ledHollowColor: root.tertiary
      fontFamily: root.fontFamily
      label: root.has("disk") && root.has("net") ? "disk · net" : (root.has("disk") ? "disk" : "net")
      led: root.ledFor(root.diskLevel)
      trailing: {
        if (!root.hasSample) return ""
        var parts = []
        if (root.has("disk") && F.isNum(root.disk.used)) parts.push(F.bytes(root.disk.used) + "/" + F.bytes(root.disk.total))
        if (root.has("net") && root.net.iface) parts.push(String(root.net.iface))
        return parts.join("  ")
      }
      trailingColor: root.labelColor

      // Disk usage bar on the left, network rates on the right
      DotBar {
        id: diskBar
        visible: root.has("disk")
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.has("net") ? root.u(96) : parent.width
        height: root.u(10)
        count: 20
        pitch: width / 20
        dotRadius: Math.max(1.5, 2.0 * root.scale)
        value: F.clamp01((root.disk.percent || 0) / 100)
        color: root.stale ? root.tertiary : root.dotOn
        offColor: root.dotOff
      }
      Caption {
        visible: root.has("disk")
        anchors.left: diskBar.left
        anchors.top: diskBar.bottom
        anchors.topMargin: root.u(3)
        text: F.isNum(root.disk.percent) ? F.pct(root.disk.percent) + "% used" : ""
      }

      Row {
        visible: root.has("net")
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.u(12)
        Row {
          spacing: root.u(4)
          Caption { text: "rx"; anchors.verticalCenter: parent.verticalCenter }
          DotText {
            anchors.verticalCenter: parent.verticalCenter
            text: F.rate(root.net.rx_bps)
            pitch: root.u(2)
            weight: 0.5
            minColumns: 23
            horizontalAlignment: Text.AlignRight
            color: root.stale ? root.tertiary : root.dotOn
          }
        }
        Row {
          spacing: root.u(4)
          Caption { text: "tx"; anchors.verticalCenter: parent.verticalCenter }
          DotText {
            anchors.verticalCenter: parent.verticalCenter
            text: F.rate(root.net.tx_bps)
            pitch: root.u(2)
            weight: 0.5
            minColumns: 23
            horizontalAlignment: Text.AlignRight
            color: root.stale ? root.tertiary : root.dotOn
          }
        }
      }
    }
  }
}
