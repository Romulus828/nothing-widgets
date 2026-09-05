import QtQuick

// A Nothing-style tile: an opaque near-black rounded card that floats on the
// black desktop, a hairline border, an uppercase caption top-left, an
// optional secondary value and a small LED slot top-right.
//
//   led: "none" | "off" | "on" | "hollow"
Rectangle {
  id: root

  property string label: ""
  property string trailing: ""
  property string led: "none"
  property real unit: 1                 // global scale factor
  property color lineColor: "#262626"
  property color labelColor: "#8c8c8c"
  property color inkColor: "#f2f2f2"
  property color trailingColor: inkColor
  property color ledOnColor: "#d71921"
  property color ledOffColor: "#2e2e2e"
  property color ledHollowColor: "#5c5c5c"
  property string fontFamily: "monospace"
  property real pad: 16 * unit
  property real contentTop: 40 * unit
  default property alias content: body.data

  radius: 20 * unit
  antialiasing: true
  border.width: 1
  border.color: lineColor

  Text {
    id: caption
    x: root.pad
    y: root.pad - 3 * root.unit
    text: root.label
    color: root.labelColor
    font.family: root.fontFamily
    font.pixelSize: Math.max(8, Math.round(10 * root.unit))
    font.letterSpacing: 1.5 * root.unit
    font.capitalization: Font.AllUppercase
    renderType: Text.NativeRendering
    visible: text !== ""
  }

  Rectangle {
    id: ledDot
    visible: root.led !== "none"
    readonly property bool on: root.led === "on"
    readonly property bool hollow: root.led === "hollow"
    width: (on ? 6 : 5) * root.unit
    height: width
    radius: width / 2
    anchors.right: parent.right
    anchors.rightMargin: root.pad + 0 * root.unit
    anchors.verticalCenter: caption.verticalCenter
    color: on ? root.ledOnColor : (hollow ? "transparent" : root.ledOffColor)
    border.width: hollow ? 1 : 0
    border.color: root.ledHollowColor
  }

  Text {
    anchors.right: ledDot.visible ? ledDot.left : parent.right
    anchors.rightMargin: ledDot.visible ? 9 * root.unit : root.pad
    anchors.verticalCenter: caption.verticalCenter
    text: root.trailing
    color: root.trailingColor
    font.family: root.fontFamily
    font.pixelSize: Math.max(8, Math.round(10 * root.unit))
    font.letterSpacing: 0.3 * root.unit
    renderType: Text.NativeRendering
    visible: text !== ""
  }

  Item {
    id: body
    anchors.fill: parent
    anchors.leftMargin: root.pad
    anchors.rightMargin: root.pad
    anchors.bottomMargin: root.pad
    anchors.topMargin: root.contentTop
  }
}
