import QtQuick
import "DotFont.js" as DotFont

// Dot-matrix text: every character is a 5x7 grid of circles, the way Nothing's
// Ndot 57 face is built. Rendered on a Canvas so a whole readout is one
// texture, however many dots it has.
//
//   pitch       distance between dot centres (logical px)
//   weight      dot radius as a fraction of pitch (0.42 regular, 0.5 bold)
//   ghost       alpha of the unlit grid positions (0 disables), for the
//               LED-matrix feel where the dark dots are faintly visible
//   minColumns  reserve width for at least this many columns so a value
//               that shrinks ("100" -> "9") does not shift its neighbours
Canvas {
  id: root

  property string text: ""
  property real pitch: 4
  property real weight: 0.42
  property color color: "#ffffff"
  property real ghost: 0
  property color ghostColor: color
  property int minColumns: 0
  property int horizontalAlignment: Text.AlignLeft

  readonly property var layoutData: DotFont.layout(text)
  readonly property int columns: Math.max(layoutData.columns, minColumns)
  readonly property int rows: DotFont.ROWS
  readonly property real dotRadius: pitch * weight

  implicitWidth: Math.max(1, columns * pitch)
  implicitHeight: rows * pitch

  antialiasing: true
  renderStrategy: Canvas.Cooperative

  readonly property var repaintKey: [text, pitch, weight, color, ghost, ghostColor, minColumns,
    horizontalAlignment, width, height]
  onRepaintKeyChanged: requestPaint()
  onAvailableChanged: if (available) requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)

    var data = layoutData
    var used = data.columns * pitch
    var x0 = 0
    if (horizontalAlignment === Text.AlignRight) x0 = width - used
    else if (horizontalAlignment === Text.AlignHCenter) x0 = (width - used) / 2
    var y0 = (height - rows * pitch) / 2
    var r = dotRadius

    if (ghost > 0) {
      ctx.fillStyle = Qt.rgba(ghostColor.r, ghostColor.g, ghostColor.b, ghost)
      var cols = Math.max(data.columns, minColumns)
      var gx0 = horizontalAlignment === Text.AlignRight ? width - cols * pitch
        : horizontalAlignment === Text.AlignHCenter ? (width - cols * pitch) / 2 : 0
      for (var gc = 0; gc < cols; gc++) {
        for (var gr = 0; gr < rows; gr++) {
          ctx.beginPath()
          ctx.arc(gx0 + gc * pitch + pitch / 2, y0 + gr * pitch + pitch / 2, r, 0, Math.PI * 2)
          ctx.fill()
        }
      }
    }

    ctx.fillStyle = color
    var dots = data.dots
    for (var i = 0; i < dots.length; i++) {
      ctx.beginPath()
      ctx.arc(x0 + dots[i].col * pitch + pitch / 2, y0 + dots[i].row * pitch + pitch / 2, r, 0, Math.PI * 2)
      ctx.fill()
    }
  }
}
