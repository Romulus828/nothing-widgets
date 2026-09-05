import QtQuick

// An image rendered as a grid of dots whose size follows the pixel's
// brightness: the dithered-raster idiom Nothing uses for pictures. The
// source is cropped to a centred square, scaled down to `columns` cells,
// sampled once per cell and drawn as circles, so the result is crisp at any
// scale and costs one small getImageData per source change.
//
//   source     image URL (file://, http(s)://, data:); "" draws the ghost grid
//   columns    dots across; rows follow the item's aspect
//   minRadius  dot radius for black, maxRadius for white (fraction of pitch)
//   gamma      > 1 keeps mid-tones small, so covers read as shapes
Canvas {
  id: root

  property string source: ""
  property int columns: 22
  property real minRadius: 0.08
  property real maxRadius: 0.46
  property real gamma: 1.4
  property color color: "#ffffff"
  property color ghostColor: "#2e2e2e"
  property bool invert: false

  readonly property real pitch: width / Math.max(1, columns)
  readonly property int rows: Math.max(1, Math.round(height / pitch))

  // The pixels come through the canvas's own loader (it copes with every
  // format Qt decodes); the Image only reports the natural size for the crop.
  property bool loaded: false
  property string loadedSource: ""
  readonly property bool sized: img.status === Image.Ready && img.sourceSize.width > 0
  readonly property bool ready: loaded && sized && loadedSource === source && source !== ""
  readonly property int imageStatus: img.status
  readonly property real imageWidth: img.sourceSize.width
  property var paintInfo: ({})       // diagnostics from the last paint

  antialiasing: true
  renderStrategy: Canvas.Cooperative

  Image {
    id: img
    visible: false
    asynchronous: true
    cache: false
    source: root.source
  }

  onSourceChanged: reload()
  onAvailableChanged: if (available) reload()
  onImageLoaded: {
    loaded = source !== "" && isImageLoaded(source)
    loadedSource = loaded ? source : ""
  }

  function reload() {
    if (!available) return
    if (loadedSource && loadedSource !== source) unloadImage(loadedSource)
    loaded = false
    loadedSource = ""
    if (source === "") { requestPaint(); return }
    if (isImageLoaded(source)) { loaded = true; loadedSource = source; return }
    loadImage(source)
  }

  readonly property var repaintKey: [columns, minRadius, maxRadius, gamma, color, ghostColor, invert, width, height, ready]
  onRepaintKeyChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)
    var cols = Math.max(1, columns)
    var rws = rows
    var p = pitch

    var lum = null
    if (ready && isImageLoaded(source)) {
      // Centre crop to the cell grid's aspect, then downscale into the
      // top-left cols x rows pixels and sample them.
      var iw = img.sourceSize.width, ih = img.sourceSize.height
      var target = cols / rws
      var sw = iw, sh = ih
      if (iw / ih > target) sw = ih * target
      else sh = iw / target
      var sx = (iw - sw) / 2, sy = (ih - sh) / 2
      // Supersample: draw at ss x ss pixels per cell (as many as fit in the
      // canvas) and box-average each cell, so halftones and fine detail
      // become tone rather than aliasing.
      var ss = Math.max(1, Math.floor(p))
      var sw2 = cols * ss, sh2 = rws * ss
      ctx.imageSmoothingEnabled = true

      // Qt's Canvas draws images scaled by the output's real scale factor
      // (1.6 on a fractionally scaled Wayland display, which nothing in QML
      // reports), so calibrate: draw at half size, measure how far the
      // pixels reach, and correct the destination by that ratio.
      var probe = sw2 / 2
      ctx.drawImage(source, 0, 0, probe, probe * ih / iw)
      var pb = ctx.getImageData(0, 0, sw2, sh2)
      var reach = 0
      for (var py = 0; py < pb.height; py++) {
        var rowOff = py * pb.width * 4
        for (var px = pb.width - 1; px >= reach; px--) {
          if (pb.data[rowOff + px * 4 + 3] > 0) { if (px + 1 > reach) reach = px + 1; break }
        }
      }
      var factor = reach > 0 ? Math.max(0.5, Math.min(4, reach / probe)) : 1
      ctx.clearRect(0, 0, width, height)

      // Crop by placing the whole image so the wanted square lands on
      // (0, 0, sw2, sh2) and letting the canvas clip the rest.
      var k = sw2 / sw / factor
      ctx.drawImage(source, -sx * k, -sy * k, iw * k, ih * k)
      var buf = ctx.getImageData(0, 0, sw2, sh2)
      var data = buf.data
      var bw = buf.width, bh = buf.height
      ctx.clearRect(0, 0, width, height)
      paintInfo = { v: 7, iw: iw, ih: ih, factor: factor, reach: reach, sw2: sw2, bufW: bw, bufH: bh }
      lum = []
      for (var cy0 = 0; cy0 < rws; cy0++) {
        var y0 = Math.floor(cy0 * bh / rws), y1 = Math.max(y0 + 1, Math.floor((cy0 + 1) * bh / rws))
        for (var cx0 = 0; cx0 < cols; cx0++) {
          var x0 = Math.floor(cx0 * bw / cols), x1 = Math.max(x0 + 1, Math.floor((cx0 + 1) * bw / cols))
          var sum = 0, n = 0
          for (var yy = y0; yy < y1; yy++) {
            for (var xx = x0; xx < x1; xx++) {
              var o = (yy * bw + xx) * 4
              sum += (0.2126 * data[o] + 0.7152 * data[o + 1] + 0.0722 * data[o + 2]) / 255 * (data[o + 3] / 255)
              n++
            }
          }
          var l = n > 0 ? sum / n : 0
          lum.push(invert ? 1 - l : l)
        }
      }
    }

    for (var y = 0; y < rws; y++) {
      for (var x = 0; x < cols; x++) {
        var cx = (x + 0.5) * p
        var cy = (y + 0.5) * p
        var rad
        if (lum) {
          var v = Math.pow(lum[y * cols + x], gamma)
          rad = p * (minRadius + (maxRadius - minRadius) * v)
          ctx.fillStyle = color
        } else {
          rad = p * 0.12
          ctx.fillStyle = ghostColor
        }
        if (rad <= 0.2) continue
        ctx.beginPath()
        ctx.arc(cx, cy, rad, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }
}
