import QtQuick

// A horizontal row of dots used as a compact linear gauge.
//
//   value   0..1
//   count   dots in the row
//   mode    "fill"  lit dots from the left, ghosts after
//           "wave"  every dot lit, radius grows with value up to that dot's
//                   position (the perforated-wave idiom from the wallpapers)
Canvas {
  id: root

  property real value: 0
  property int count: 20
  property string mode: "fill"
  property real dotRadius: 2
  property real pitch: 6
  property color color: "#ffffff"
  property color offColor: "#2a2a2a"
  property real alertFrom: 0
  property color alertColor: "#d71921"

  implicitWidth: count * pitch
  implicitHeight: pitch
  antialiasing: true
  renderStrategy: Canvas.Cooperative

  readonly property var repaintKey: [value, count, mode, dotRadius, pitch, color, offColor, width, height, alertFrom, alertColor]
  onRepaintKeyChanged: requestPaint()
  onAvailableChanged: if (available) requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)

    var v = Math.max(0, Math.min(1, value))
    var lit = Math.round(v * count)
    var cy = height / 2
    var x0 = (width - count * pitch) / 2
    for (var i = 0; i < count; i++) {
      var x = x0 + i * pitch + pitch / 2
      var frac = (i + 0.5) / count
      var on = i < lit
      var alert = alertFrom > 0 && frac >= alertFrom && on
      var r = dotRadius
      if (mode === "wave") {
        // dot size follows how far the value reaches past this position
        var reach = Math.max(0, Math.min(1, (v - frac) * count + 1))
        r = dotRadius * (0.35 + 0.65 * reach)
        on = reach > 0
      }
      ctx.fillStyle = on ? (alert ? alertColor : color) : offColor
      ctx.beginPath()
      ctx.arc(x, cy, on ? r : dotRadius * 0.7, 0, Math.PI * 2)
      ctx.fill()
    }
  }
}
