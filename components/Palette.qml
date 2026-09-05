import QtQuick
import qs.Commons

// The widget palette, derived from the active Omarchy theme so every widget
// shares one set of greys and stays coherent on themes other than Nothing.
// Comments give the values that fall out on the Nothing theme.
QtObject {
  id: pal

  property real tileAlpha: 1.0

  readonly property color fg: Color.foreground
  readonly property color bg: Color.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family

  function mix(k) {
    return Qt.rgba(bg.r + (fg.r - bg.r) * k, bg.g + (fg.g - bg.g) * k, bg.b + (fg.b - bg.b) * k, 1)
  }
  readonly property real fgLuma: 0.2126 * fg.r + 0.7152 * fg.g + 0.0722 * fg.b
  readonly property color dotOn: fgLuma > 0.9 ? "#ffffff" : fg          // lit dots
  readonly property color ink: fg                                        // text values      #f2f2f2
  readonly property color labelColor: mix(0.58)                          // labels           #8c8c8c
  readonly property color tertiary: mix(0.38)                            // missing / stale  #5c5c5c
  readonly property color dotOff: mix(0.19)                              // unlit dots       #2e2e2e
  readonly property color line: mix(0.15)                                // hairline         #262626
  readonly property color tileFill: {
    var c = mix(0.09)                                                    // tile             #161616
    return Qt.rgba(c.r, c.g, c.b, tileAlpha)
  }
  readonly property color redText: Qt.lighter(accent, 1.3)
}
