// Number formatting for the readouts. Everything returns fixed-shape strings
// so dot-matrix numerals do not jitter between samples.
.pragma library

function isNum(v) {
  return typeof v === "number" && isFinite(v)
}

// 0..100 -> "  7" / " 48" / "100" (right-aligned in 3 columns)
function pct(v) {
  if (!isNum(v)) return "--"
  var n = Math.round(Math.max(0, Math.min(100, v)))
  return String(n)
}

// degrees -> "48" (integers only; the widget appends the degree glyph)
function deg(v) {
  if (!isNum(v)) return "--"
  return String(Math.round(v))
}

// bytes -> "5.0G", "48G", "512M", "1.2T". Short, always <= 4 chars + unit.
function bytes(v) {
  if (!isNum(v)) return "--"
  var units = ["B", "K", "M", "G", "T"]
  var n = v
  var i = 0
  while (n >= 1000 && i < units.length - 1) { n /= 1024; i++ }
  var s = n >= 100 ? String(Math.round(n)) : n >= 10 ? n.toFixed(0) : n.toFixed(1)
  if (i === 0) s = String(Math.round(n))
  return s + units[i]
}

// bytes per second -> "1.2M/S" style, or "0" when idle
function rate(v) {
  if (!isNum(v)) return "--"
  if (v < 1024) return "0"
  return bytes(v)
}

// GiB with one decimal for memory ("5.0" of "30")
function gib(v, decimals) {
  if (!isNum(v)) return "--"
  var g = v / (1024 * 1024 * 1024)
  return decimals === 0 ? String(Math.round(g)) : g.toFixed(decimals === undefined ? 1 : decimals)
}

function mib(v) {
  if (!isNum(v)) return "--"
  return String(Math.round(v))
}

// MHz -> "1.0GHZ" / "555MHZ"
function freq(mhz) {
  if (!isNum(mhz)) return "--"
  if (mhz >= 1000) return (mhz / 1000).toFixed(1) + "GHZ"
  return String(Math.round(mhz)) + "MHZ"
}

function rpm(v) {
  if (!isNum(v)) return "--"
  return String(Math.round(v))
}

function watts(v) {
  if (!isNum(v)) return "--"
  return v >= 100 ? String(Math.round(v)) : v.toFixed(1)
}

function load(v) {
  if (!isNum(v)) return "--"
  return v.toFixed(2)
}

function uptime(seconds) {
  if (!isNum(seconds)) return "--"
  var s = Math.floor(seconds)
  var d = Math.floor(s / 86400)
  var h = Math.floor((s % 86400) / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (d > 0) return d + "D " + h + "H"
  if (h > 0) return h + "H " + m + "M"
  return m + "M"
}

// Severity for a temperature against hwmon thresholds.
// Returns 0 normal, 1 warm (>= 80% of high or >= high-15), 2 hot (>= high), 3 critical (>= crit)
function tempLevel(value, high, crit) {
  if (!isNum(value)) return 0
  var h = isNum(high) ? high : (isNum(crit) ? crit - 10 : 85)
  var c = isNum(crit) ? crit : h + 10
  if (value >= c) return 3
  if (value >= h) return 2
  if (value >= h - 15) return 1
  return 0
}

function clamp01(v) {
  if (!isNum(v)) return 0
  return Math.max(0, Math.min(1, v))
}
