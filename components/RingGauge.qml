import QtQuick

// Ring gauge with a dot numeral centred inside and a unit caption under it.
// Colours are passed in so the gauge has no opinion about the theme.
Item {
  id: root

  property real value: 0            // 0..1
  property string text: "--"
  property string unit: "%"
  property bool active: true
  property bool stale: false
  property real scale: 1
  property real size: 88 * scale
  property color dots: "#ffffff"    // numeral colour while active
  property color ringColor: "#ffffff"
  property color offColor: "#2e2e2e"
  property color tertiary: "#5c5c5c"
  property color captionColor: "#8c8c8c"
  property string fontFamily: "monospace"

  function u(px) { return Math.round(px * scale) }

  implicitWidth: size
  implicitHeight: size

  DotRing {
    id: ring
    anchors.fill: parent
    value: root.active ? root.value : 0
    count: 36
    dotRadius: Math.max(1.5, 2.0 * root.scale)
    headRadius: Math.max(2, 2.75 * root.scale)
    color: root.stale ? root.tertiary : root.ringColor
    offColor: root.offColor
  }
  DotText {
    anchors.horizontalCenter: ring.horizontalCenter
    anchors.verticalCenter: ring.verticalCenter
    anchors.verticalCenterOffset: -root.u(5)
    text: root.active ? root.text : "-"
    pitch: String(root.text).length >= 3 ? root.u(4) : root.u(6)
    weight: 0.39
    color: root.active ? root.dots : root.tertiary
    horizontalAlignment: Text.AlignHCenter
  }
  Text {
    anchors.horizontalCenter: ring.horizontalCenter
    anchors.verticalCenter: ring.verticalCenter
    anchors.verticalCenterOffset: root.u(24)
    text: root.unit
    color: root.captionColor
    font.family: root.fontFamily
    font.pixelSize: Math.max(8, root.u(9))
    font.letterSpacing: 1.0 * root.scale
    font.capitalization: Font.AllUppercase
    renderType: Text.NativeRendering
  }
}
