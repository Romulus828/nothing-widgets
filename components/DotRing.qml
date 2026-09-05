import QtQuick

// A ring of dots used as a gauge. Lit dots fill clockwise from the top;
// unlit dots stay as faint ghosts, like a Glyph ring at rest.
//
//   value     0..1 fill fraction
//   count     number of dots around the ring
//   sweep     degrees of arc the ring covers (360 full, 270 leaves a gap at the bottom)
Canvas {
  id: root

  property real value: 0
  property int count: 36
  property real sweep: 360
  property real dotRadius: 2.2
  // The last lit dot (the "head") is drawn a little larger, like a bead.
  property real headRadius: dotRadius * 1.35
  property color color: "#ffffff"
  property color offColor: "#2a2a2a"
  // Dots past this fraction switch to alertColor (0 disables).
  property real alertFrom: 0
  property color alertColor: "#d71921"

  implicitWidth: 96
  implicitHeight: 96
  antialiasing: true
  renderStrategy: Canvas.Cooperative

  readonly property var repaintKey: [value, count, sweep, dotRadius, headRadius, color, offColor, width, height, alertFrom, alertColor]
  onRepaintKeyChanged: requestPaint()
  onAvailableChanged: if (available) requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)

    var cx = width / 2
    var cy = height / 2
    var radius = Math.min(width, height) / 2 - Math.max(dotRadius, headRadius)
    var lit = Math.round(Math.max(0, Math.min(1, value)) * count)
    var full = sweep >= 360
    var step = full ? 360 / count : sweep / Math.max(1, count - 1)
    var start = -90 - (full ? 0 : sweep / 2)

    for (var i = 0; i < count; i++) {
      var a = (start + i * step) * Math.PI / 180
      var x = cx + radius * Math.cos(a)
      var y = cy + radius * Math.sin(a)
      var on = i < lit
      var head = on && i === lit - 1
      var alert = on && alertFrom > 0 && (i / count) >= alertFrom
      ctx.fillStyle = on ? (alert ? alertColor : color) : offColor
      ctx.beginPath()
      ctx.arc(x, y, head ? headRadius : (on ? dotRadius : dotRadius * 0.8), 0, Math.PI * 2)
      ctx.fill()
    }
  }
}
