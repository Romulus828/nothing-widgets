import QtQuick

// A small grid of dots where each dot's radius follows one value in
// `values` (0..1): the perforated-wallpaper grammar applied to data. Used
// for the per-thread CPU load block.
Canvas {
  id: root

  property var values: []
  property int columns: 5
  property real pitch: 12
  property real minRadius: 1.5
  property real maxRadius: 4.5
  property color color: "#ffffff"
  property real opacityOn: 0.92
  // Dots for these indices (same order as values) are drawn in alertColor.
  property var alerts: []
  property color alertColor: "#d71921"

  readonly property int rows: Math.max(1, Math.ceil((values ? values.length : 0) / Math.max(1, columns)))
  implicitWidth: columns * pitch
  implicitHeight: rows * pitch
  antialiasing: true
  renderStrategy: Canvas.Cooperative

  readonly property var repaintKey: [values, columns, pitch, minRadius, maxRadius, color, opacityOn, width, height, alerts, alertColor]
  onRepaintKeyChanged: requestPaint()
  onAvailableChanged: if (available) requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)

    var list = values || []
    var hot = alerts || []
    var x0 = (width - columns * pitch) / 2
    var y0 = (height - rows * pitch) / 2
    for (var i = 0; i < list.length; i++) {
      var v = Math.max(0, Math.min(1, Number(list[i]) || 0))
      var c = i % columns
      var r = Math.floor(i / columns)
      var base = hot.indexOf(i) !== -1 ? alertColor : color
      ctx.fillStyle = Qt.rgba(base.r, base.g, base.b, opacityOn)
      ctx.beginPath()
      ctx.arc(x0 + c * pitch + pitch / 2, y0 + r * pitch + pitch / 2, minRadius + (maxRadius - minRadius) * v, 0, Math.PI * 2)
      ctx.fill()
    }
  }
}
