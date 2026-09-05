import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Commons
import "../components"
import "../components/Format.js" as F

// The media widget: one 300 x 172 tile, a little taller than the others so
// a two-line title, the artist, the buttons and the bar never collide. Album art as a dot raster on the
// left; title, artist, a dot progress bar and times on the right. Follows
// Omarchy's own media service (omarchy.media) for which player is active,
// so it agrees with the bar and the OSD; falls back to MPRIS directly.
//
// Transport buttons sit between the artist line and the progress bar. The
// tile itself also answers: left click play / pause, right click next,
// middle click previous.
Item {
  id: root

  property var host: null           // Desktop.qml root, for the media service handle
  property real scale: 1
  property real tileAlpha: 1.0
  property bool hideWhenIdle: true  // hide the tile when nothing is loaded
  property string clickCommand: ""  // run on left click when nothing is playing

  Palette { id: pal; tileAlpha: root.tileAlpha }

  function u(px) { return Math.round(px * scale) }
  readonly property real widgetWidth: u(300)
  readonly property real tileH: u(172)

  // ----------------------------------------------------------- player

  readonly property var service: host ? host.mediaService : null
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    if (service && service.activePlayer !== undefined) return service.activePlayer
    // no service: the first playing player, else the first with a title
    var first = null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue
      if (p.isPlaying) return p
      if (!first && (p.trackTitle || p.trackArtist)) first = p
    }
    return first
  }
  readonly property bool hasMedia: player !== null && !!(player.trackTitle || player.trackArtist)
  readonly property bool playing: player !== null && !!player.isPlaying
  readonly property string title: player ? String(player.trackTitle || "") : ""
  readonly property string artist: player ? String(player.trackArtist || "") : ""
  readonly property string artUrl: player && player.trackArtUrl ? String(player.trackArtUrl) : ""
  readonly property string identity: player ? String(player.identity || player.desktopEntry || "") : ""
  readonly property bool hasLength: player !== null && player.lengthSupported && player.length > 0
  readonly property real length: hasLength ? player.length : 0
  readonly property real position: player !== null && player.positionSupported ? player.position : 0
  readonly property real progress: hasLength ? F.clamp01(position / length) : 0

  readonly property bool wanted: hasMedia || !hideWhenIdle
  readonly property var debugInfo: ({ artUrl: artUrl, imageStatus: art.imageStatus, imageWidth: art.imageWidth, ready: art.ready, identity: identity, paint: art.paintInfo })
  implicitWidth: widgetWidth
  implicitHeight: wanted ? tileH : 0

  // MPRIS position only moves when the player reports it, so nudge it once a
  // second while something plays.
  Timer {
    interval: 1000
    running: root.visible && root.playing && root.player !== null && root.player.positionSupported
    repeat: true
    onTriggered: root.player.positionChanged()
  }

  readonly property bool canPrev: player !== null && !!player.canGoPrevious
  readonly property bool canNext: player !== null && !!player.canGoNext
  readonly property bool canToggle: player !== null && !!(player.canTogglePlaying || player.canPlay || player.canPause)

  function act(action) {
    if (service && typeof service.runAction === "function") { service.runAction(action, false); return }
    var p = player
    if (!p) return
    if (action === "next" && p.canGoNext) p.next()
    else if (action === "previous" && p.canGoPrevious) p.previous()
    else if (action === "playPause" && p.canTogglePlaying) p.togglePlaying()
  }

  // A dot-glyph transport button.
  component TransportButton: Item {
    id: btn
    property string glyph: "\u25B6"
    property bool enabled: true
    property bool emphasis: false
    signal pressed()
    width: icon.implicitWidth + root.u(12)
    height: icon.implicitHeight + root.u(8)
    DotText {
      id: icon
      anchors.centerIn: parent
      text: btn.glyph
      pitch: root.u(3)
      weight: 0.42
      color: !btn.enabled ? pal.dotOff : (hover.containsMouse ? pal.dotOn : (btn.emphasis ? pal.dotOn : pal.labelColor))
    }
    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      enabled: btn.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.pressed()
    }
  }

  component Caption: Text {
    color: pal.labelColor
    font.family: pal.fontFamily
    font.pixelSize: Math.max(8, root.u(9))
    font.letterSpacing: 1.0 * root.scale
    font.capitalization: Font.AllUppercase
    renderType: Text.NativeRendering
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: root.hasMedia || root.clickCommand ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(mouse) {
      if (root.hasMedia) {
        if (mouse.button === Qt.RightButton) root.act("next")
        else if (mouse.button === Qt.MiddleButton) root.act("previous")
        else root.act("playPause")
      } else if (mouse.button === Qt.LeftButton && root.clickCommand) {
        Util.execDetached(root.clickCommand)
      }
    }
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
    label: "media"
    // The LED is the play indicator: lit while playing, hollow while paused.
    led: root.hasMedia ? (root.playing ? "on" : "hollow") : "off"
    trailing: root.identity.toLowerCase()
    trailingColor: pal.labelColor

    DotImage {
      id: art
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.topMargin: root.u(1)
      width: root.u(88)
      height: root.u(88)
      columns: 22
      source: root.artUrl
      color: pal.dotOn
      ghostColor: pal.dotOff
    }

    Item {
      anchors.left: art.right
      anchors.leftMargin: root.u(16)
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom

      Text {
        id: titleText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        text: root.hasMedia ? root.title || root.identity : "nothing playing"
        color: root.hasMedia ? pal.ink : pal.tertiary
        font.family: pal.fontFamily
        font.pixelSize: Math.max(9, root.u(12))
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.Wrap
        renderType: Text.NativeRendering
      }
      Caption {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: titleText.bottom
        anchors.topMargin: root.u(3)
        text: root.artist
        elide: Text.ElideRight
      }

      Row {
        id: transport
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: bar.top
        anchors.bottomMargin: root.u(4)
        spacing: root.u(10)
        TransportButton { glyph: "\u23EE"; enabled: root.canPrev; onPressed: root.act("previous") }
        TransportButton { glyph: root.playing ? "\u23F8" : "\u25B6"; enabled: root.canToggle; emphasis: true; onPressed: root.act("playPause") }
        TransportButton { glyph: "\u23ED"; enabled: root.canNext; onPressed: root.act("next") }
      }

      DotBar {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: times.top
        anchors.bottomMargin: root.u(5)
        height: root.u(8)
        count: 24
        pitch: width / 24
        dotRadius: Math.max(1.4, 1.9 * root.scale)
        mode: "fill"
        value: root.progress
        color: root.playing ? pal.dotOn : pal.tertiary
        offColor: pal.dotOff
      }
      Item {
        id: times
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.u(14)
        DotText {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.hasMedia && root.player.positionSupported ? F.clockTime(root.position) : ""
          pitch: root.u(2)
          weight: 0.5
          color: root.playing ? pal.dotOn : pal.tertiary
        }
        DotText {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.hasLength ? F.clockTime(root.length) : ""
          pitch: root.u(2)
          weight: 0.5
          horizontalAlignment: Text.AlignRight
          color: pal.labelColor
        }
      }
    }
  }
}
