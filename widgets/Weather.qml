import QtQuick
import Quickshell
import qs.Commons
import "../components"
import "../components/Format.js" as F
import "../components/Weather.js" as W

// The weather widget: one 300 x 146 tile. Current temperature as the hero
// numeral with the condition and feels-like beneath, and a four-day
// forecast on the right with dot glyphs and highs and lows. Data and the
// location come from the host (Desktop.qml), which shares Omarchy's own
// weather location.
Item {
  id: root

  property var host: null
  property real scale: 1
  property real tileAlpha: 1.0
  property string clickCommand: ""

  Palette { id: pal; tileAlpha: root.tileAlpha }

  function u(px) { return Math.round(px * scale) }
  readonly property real widgetWidth: u(300)
  readonly property real tileH: u(146)
  readonly property bool wanted: true

  implicitWidth: widgetWidth
  implicitHeight: tileH

  readonly property var wx: host ? host.weather : null
  readonly property bool hasData: wx !== null && F.isNum(wx.temp)
  readonly property bool stale: host ? host.weatherStale : true
  readonly property bool imperial: host ? host.weatherImperial : false
  readonly property string place: host ? host.weatherPlace : ""
  readonly property bool hasLocation: host ? host.weatherHasLocation : false
  readonly property var cond: hasData ? W.condition(wx.code, wx.isDay) : ({ label: "", glyph: "", severe: false })
  readonly property string today: Qt.formatDate(new Date(), "yyyy-MM-dd")

  function deg(v) { return F.isNum(v) ? String(Math.round(v)) + "°" : "--" }

  component Caption: Text {
    color: pal.labelColor
    font.family: pal.fontFamily
    font.pixelSize: Math.max(8, root.u(9))
    font.letterSpacing: 1.0 * root.scale
    font.capitalization: Font.AllUppercase
    renderType: Text.NativeRendering
  }

  // One forecast row: day, glyph, high / low
  component DayRow: Item {
    id: dayRow
    property var day: null
    property bool isToday: false
    width: parent ? parent.width : 0
    height: root.u(22)
    Caption {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: dayRow.day ? W.dayName(dayRow.day.date, root.today) : ""
      color: dayRow.isToday ? pal.ink : pal.labelColor
    }
    DotText {
      anchors.left: parent.left
      anchors.leftMargin: root.u(40)
      anchors.verticalCenter: parent.verticalCenter
      text: dayRow.day ? W.condition(dayRow.day.code, true).glyph : ""
      pitch: root.u(2)
      weight: 0.5
      color: root.stale ? pal.tertiary : pal.dotOn
    }
    DotText {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: dayRow.day ? root.deg(dayRow.day.max) + " " + root.deg(dayRow.day.min) : ""
      pitch: root.u(2)
      weight: 0.5
      minColumns: 23
      horizontalAlignment: Text.AlignRight
      color: root.stale ? pal.tertiary : pal.dotOn
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
    label: "weather"
    // Red only for severe weather; hollow while the report is stale or missing.
    led: !root.hasData || root.stale ? "hollow" : (root.cond.severe ? "on" : "off")
    trailing: root.place.toUpperCase()
    trailingColor: pal.labelColor

    // ---- left: hero temperature, condition, feels like
    DotText {
      id: hero
      anchors.left: parent.left
      anchors.top: parent.top
      text: root.hasData ? root.deg(root.wx.temp) : "--"
      pitch: root.u(7)
      weight: 0.39
      color: root.stale ? pal.tertiary : (root.cond.severe ? pal.accent : pal.dotOn)
    }
    DotText {
      anchors.left: hero.right
      anchors.leftMargin: root.u(8)
      anchors.top: parent.top
      anchors.topMargin: root.u(2)
      visible: root.hasData
      text: root.cond.glyph
      pitch: root.u(3)
      weight: 0.45
      color: root.stale ? pal.tertiary : pal.dotOn
    }
    Caption {
      anchors.left: parent.left
      anchors.bottom: feels.top
      anchors.bottomMargin: root.u(3)
      width: root.u(124)
      elide: Text.ElideRight
      text: {
        if (!root.hasLocation) return "no location set"
        if (!root.hasData) return root.stale ? "no report" : "loading"
        return root.cond.label
      }
      color: root.cond.severe ? pal.redText : pal.labelColor
    }
    Caption {
      id: feels
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      width: root.u(124)
      elide: Text.ElideRight
      text: {
        if (!root.hasData) return root.hasLocation ? "" : "use the bar's weather popup"
        var parts = ["feels " + root.deg(root.wx.feels)]
        if (F.isNum(root.wx.wind)) parts.push(Math.round(root.wx.wind) + (root.imperial ? " mph" : " km/h"))
        return parts.join(" · ")
      }
    }

    // ---- right: four-day forecast
    Column {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: -root.u(1)
      width: root.u(128)
      spacing: 0
      Repeater {
        model: root.hasData ? Math.min(4, root.wx.days.length) : 0
        delegate: DayRow {
          required property int index
          day: root.wx.days[index]
          isToday: index === 0
        }
      }
    }
  }
}
