# Roadmap

Widgets that would fit the collection, grouped by how well they suit the
dot-matrix style and what data an Omarchy box already has. Shipped ones are
ticked.

## Strong fits, easy data

- [x] **System monitor.** CPU, GPU, memory, thermal, disk and network tiles.
- [x] **Battery.** Charge ring, time left or to full, draw, health, cycles.
- [x] **Clock and timer.** Dot-matrix time with no seconds; a timer or an
      Omarchy reminder takes over the tile with a draining ring.
- [ ] **Media.** Quickshell has an MPRIS service, so track, artist, play
      state and a dot progress bar come for free. Album art as a dithered dot
      raster would be very on-brand.
- [ ] **Weather.** Omarchy's bar has a weather widget with a data source to
      reuse. Temperature as the hero numeral, a dot bar for the day's high and
      low, a row of conditions per hour.
- [ ] **Calendar.** A month as a 7-column dot grid with today as the red LED
      and past days dimmed. Small and quiet, good for stacking under the
      battery.
- [ ] **World clock.** A second-city variant of the clock tile.

## Useful on a Linux desktop

- [ ] **Network.** SSID, signal as a dot bar, link speed, VPN or Tailscale
      state, and a rolling rx/tx history strip. Some of this is already in
      the collector.
- [ ] **Updates and uptime.** Pending pacman and AUR packages as a numeral,
      uptime, last boot. Clicking runs the updater.
- [ ] **Storage.** One row per mount with a dot bar, for machines with more
      than a root partition. Could be a mode of the existing DISK tile.

## More speculative

- [ ] **Containers or services.** Running Docker containers or failed
      systemd units, with the LED going red on a failure.
- [ ] **Audio.** Output device and a volume dot bar, plus mic mute state.

## Framework

- [ ] **`order` key** so widgets sharing a corner can be arranged, instead of
      the fixed monitor, battery, clock order.
- [ ] **Hysteresis** on alert thresholds so a value hovering at a limit does
      not flicker between white and red.
- [ ] **NET history strips** in the DISK · NET tile.

Suggested order of work: media, then weather, then calendar. Media and
weather each give the collection a widget that changes through the day
rather than one that mostly sits still.
