import QtQuick
import Quickshell
import qs.Commons
import "../components"
import "../components/Format.js" as F

// The clock widget: one 300 x 146 tile with two modes.
//   clock  big dot-matrix time and the date; no seconds, so it repaints once
//          a minute and the desktop stays still
//   timer  the remaining time takes the hero, a dot ring drains beside it,
//          the clock moves to the trailing text and the LED lights up
// Timer state lives in the host (Desktop.qml) so every screen shows the
// same countdown and IPC can drive it.
Item {
  id: root

  property var host: null           // Desktop.qml root: timer state and controls
  property real scale: 1
  property real tileAlpha: 1.0
  property string clickCommand: ""  // run on click in clock mode; empty = nothing
  property string format: "auto"    // auto | 12h | 24h

  Palette { id: pal; tileAlpha: root.tileAlpha }

  function u(px) { return Math.round(px * scale) }
  readonly property real widgetWidth: u(300)
  readonly property real tileH: u(146)
  readonly property bool wanted: true

  implicitWidth: widgetWidth
  implicitHeight: tileH

  // ----------------------------------------------------------- clock

  property date now: new Date()
  Timer {
    interval: 1000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = new Date()
  }

  readonly property bool twelveHour: {
    if (format === "12h") return true
    if (format === "24h") return false
    return Qt.locale().timeFormat(Locale.ShortFormat).indexOf("AP") !== -1
  }
  // Qt's "h" is only 12-hour when the format also carries AP, so format with
  // it and drop the suffix.
  readonly property string timeText: twelveHour ? Qt.formatTime(now, "h:mm AP").split(" ")[0] : Qt.formatTime(now, "HH:mm")
  readonly property string meridiem: twelveHour ? Qt.formatTime(now, "AP") : ""
  readonly property string dateText: Qt.formatDate(now, "ddd d MMM")
  readonly property string clockLine: twelveHour ? timeText + " " + meridiem : timeText

  // ----------------------------------------------------------- timer

  readonly property bool timerActive: host ? host.timerActive : false
  readonly property bool timerPaused: host ? host.timerPaused : false
  readonly property bool timerDone: host ? host.timerDone : false
  readonly property real remainingMs: host ? host.timerRemainingMs : 0
  readonly property real durationMs: host ? host.timerDurationMs : 0
  readonly property real fraction: durationMs > 0 ? F.clamp01(remainingMs / durationMs) : 0
  readonly property string remainingText: F.countdown(remainingMs)
  readonly property string endsText: {
    if (!host || !timerActive || timerPaused || timerDone) return ""
    var d = new Date(host.timerEndsAt)
    return "ends " + Qt.formatTime(d, twelveHour ? "h:mm AP" : "HH:mm")
  }

  // The LED blinks while a finished timer waits to be dismissed.
  property bool blink: false
  Timer {
    interval: 500
    running: root.timerDone
    repeat: true
    onTriggered: root.blink = !root.blink
    onRunningChanged: if (!running) root.blink = false
  }

  component Caption: Text {
    color: pal.labelColor
    font.family: pal.fontFamily
    font.pixelSize: Math.max(8, root.u(9))
    font.letterSpacing: 1.0 * root.scale
    font.capitalization: Font.AllUppercase
    renderType: Text.NativeRendering
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: root.timerActive || root.clickCommand ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(mouse) {
      if (!root.host) return
      if (root.timerActive) {
        // left: pause / resume, or dismiss a finished timer; right: cancel
        if (mouse.button === Qt.RightButton || root.timerDone) root.host.timerStop()
        else root.host.timerToggle()
      } else if (mouse.button === Qt.LeftButton && root.clickCommand) {
        Util.execDetached(root.clickCommand)
      }
    }
  }

  Tile {
    width: root.widgetWidth
    height: root.tileH
    unit: root.scale
    color: pal.tileFill
    lineColor: pal.line
    labelColor: pal.labelColor
    inkColor: pal.ink
    ledOnColor: pal.accent
    ledOffColor: pal.dotOff
    ledHollowColor: pal.tertiary
    fontFamily: pal.fontFamily
    label: root.timerActive ? "timer" : "clock"
    led: {
      if (!root.timerActive) return "off"
      if (root.timerDone) return root.blink ? "on" : "off"
      return root.timerPaused ? "hollow" : "on"
    }
    trailing: root.timerActive ? root.clockLine : ""
    trailingColor: pal.labelColor

    // ---- clock mode
    DotText {
      id: clockHero
      visible: !root.timerActive
      anchors.left: parent.left
      anchors.top: parent.top
      text: root.timeText
      pitch: root.u(8)
      weight: 0.39
      color: pal.dotOn
    }
    Text {
      visible: !root.timerActive && root.meridiem !== ""
      anchors.left: clockHero.right
      anchors.leftMargin: root.u(8)
      anchors.baseline: clockHero.bottom
      anchors.baselineOffset: -root.u(2)
      text: root.meridiem
      color: pal.labelColor
      font.family: pal.fontFamily
      font.pixelSize: root.u(12)
      font.letterSpacing: 1.5 * root.scale
      renderType: Text.NativeRendering
    }
    Caption {
      visible: !root.timerActive
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      text: root.dateText
    }

    // ---- timer mode
    DotText {
      id: timerHero
      visible: root.timerActive
      anchors.left: parent.left
      anchors.top: parent.top
      text: root.remainingText
      // m:ss fits beside the ring at 6 px; h:mm:ss drops to 4 px
      pitch: root.remainingText.length >= 7 ? root.u(4) : root.u(6)
      weight: 0.39
      color: root.timerPaused ? pal.tertiary : (root.timerDone ? pal.accent : pal.dotOn)
    }
    Caption {
      visible: root.timerActive
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      text: root.timerDone ? "done · click to dismiss" : (root.timerPaused ? "paused" : root.endsText)
      color: root.timerDone ? pal.redText : pal.labelColor
    }
    DotRing {
      visible: root.timerActive
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: root.u(1)
      width: root.u(88)
      height: root.u(88)
      value: root.timerDone ? 0 : root.fraction
      count: 36
      dotRadius: Math.max(1.5, 2.0 * root.scale)
      headRadius: Math.max(2, 2.75 * root.scale)
      color: root.timerPaused ? pal.tertiary : pal.dotOn
      offColor: pal.dotOff
    }
  }
}
