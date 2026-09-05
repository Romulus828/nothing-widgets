import QtQuick
import Quickshell
import qs.Commons
import "../components"
import "../components/Format.js" as F

// The battery widget: one 300 x 146 tile. Charge ring on the left, a column
// of dot-matrix stats on the right (time left or time to full, draw, health,
// cycle count). Hidden when the machine has no battery.
Item {
  id: root

  property var sample: ({})
  property bool stale: false
  property real scale: 1
  property real tileAlpha: 1.0
  property string clickCommand: ""
  property int lowAt: 15            // percent at which the LED and numerals go red

  Palette { id: pal; tileAlpha: root.tileAlpha }

  function u(px) { return Math.round(px * scale) }
  readonly property real widgetWidth: u(300)
  readonly property real tileH: u(146)

  readonly property var bat: sample && sample.battery ? sample.battery : ({})
  readonly property bool present: bat.present === true
  readonly property bool hasSample: !!(sample && sample.cpu)
  readonly property string status: String(bat.status || "Unknown")
  readonly property bool charging: status === "Charging"
  readonly property bool full: status === "Full" || (bat.ac_online === true && !charging && F.isNum(bat.capacity) && bat.capacity >= 95)
  readonly property bool onAc: bat.ac_online === true
  readonly property bool discharging: status === "Discharging" || (!onAc && !charging && !full)
  readonly property int capacity: F.isNum(bat.capacity) ? Math.round(bat.capacity) : -1
  readonly property bool low: present && discharging && capacity >= 0 && capacity <= lowAt
  readonly property int level: low ? 2 : 0

  // Read by the host: the widget has nothing to show without a battery.
  readonly property bool wanted: present
  implicitWidth: widgetWidth
  implicitHeight: present ? tileH : 0

  function dotColor(level) { return stale ? pal.tertiary : (level >= 2 ? pal.accent : pal.dotOn) }

  readonly property string stateWord: {
    if (!present) return "no battery"
    if (charging) return "charging"
    if (full) return "full"
    if (onAc) return "on ac"
    return "on battery"
  }

  component Caption: Text {
    color: pal.labelColor
    font.family: pal.fontFamily
    font.pixelSize: Math.max(8, root.u(9))
    font.letterSpacing: 1.0 * root.scale
    font.capitalization: Font.AllUppercase
    renderType: Text.NativeRendering
  }

  // One stat row: caption on the left, dot numeral on the right.
  component StatRow: Item {
    id: statRow
    property string name: ""
    property string value: "--"
    property color color: pal.dotOn
    width: parent ? parent.width : 0
    height: root.u(22)
    Caption {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: statRow.name
    }
    DotText {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: statRow.value
      pitch: root.u(2)
      weight: 0.5
      minColumns: 23
      horizontalAlignment: Text.AlignRight
      color: statRow.color
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: root.clickCommand ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.clickCommand) Util.execDetached(root.clickCommand)
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
    label: "battery"
    // Red only when the charge is actually low; hollow while data is stale.
    led: root.stale || !root.hasSample ? "hollow" : (root.low ? "on" : "off")
    trailing: F.isNum(root.bat.energy_wh) ? Math.round(root.bat.energy_wh) + "WH" : ""
    trailingColor: pal.labelColor

    RingGauge {
      id: ring
      anchors.left: parent.left
      y: root.u(2)
      scale: root.scale
      stale: root.stale
      active: root.present && root.hasSample
      value: F.clamp01(root.capacity / 100)
      text: root.capacity >= 0 ? String(root.capacity) : "-"
      unit: root.stateWord
      dots: root.dotColor(root.level)
      ringColor: pal.dotOn
      offColor: pal.dotOff
      tertiary: pal.tertiary
      captionColor: root.low ? pal.redText : pal.labelColor
      fontFamily: pal.fontFamily
    }

    Column {
      anchors.left: ring.right
      anchors.leftMargin: root.u(20)
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: root.u(1)

      StatRow {
        name: root.charging ? "to full" : "left"
        value: {
          if (root.charging) return F.hours(root.bat.hours_to_full)
          if (root.discharging) return F.hours(root.bat.hours_left)
          return "--"
        }
        color: root.dotColor(root.level)
      }
      StatRow {
        name: root.charging ? "charge" : "draw"
        value: F.isNum(root.bat.power_w) && (root.charging || root.discharging) ? F.watts(root.bat.power_w) + "W" : "--"
        color: root.dotColor(0)
      }
      StatRow {
        name: "health"
        value: F.isNum(root.bat.health) ? Math.round(root.bat.health) + "%" : "--"
        color: root.dotColor(F.isNum(root.bat.health) && root.bat.health < 60 ? 2 : 0)
      }
      StatRow {
        name: "cycles"
        value: F.isNum(root.bat.cycles) ? String(root.bat.cycles) : "--"
        color: root.dotColor(0)
      }
    }
  }
}
