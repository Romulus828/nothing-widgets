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

// Hours as "4H 48M"; under an hour just "48M"
function hours(h) {
  if (!isNum(h) || h < 0) return "--"
  var total = Math.round(h * 60)
  var hh = Math.floor(total / 60)
  var mm = total % 60
  if (hh === 0) return mm + "M"
  return hh + "H " + (mm < 10 ? "0" : "") + mm + "M"
}

// Remaining time as "24:59" or "1:24:59"
function countdown(ms) {
  var total = Math.max(0, Math.ceil((Number(ms) || 0) / 1000))
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var mm = h > 0 && m < 10 ? "0" + m : String(m)
  var ss = s < 10 ? "0" + s : String(s)
  return (h > 0 ? h + ":" : "") + mm + ":" + ss
}

// Parse a timer spec into milliseconds, or NaN:
//   "25" = 25 minutes, "90s", "25m", "1h", "1h30m", "1h30", "10:00" (m:ss), "1:30:00" (h:mm:ss)
function parseDuration(spec) {
  var s = String(spec || "").trim().toLowerCase()
  if (!s) return NaN
  if (/^\d+(\.\d+)?$/.test(s)) return parseFloat(s) * 60000
  var colon = s.match(/^(\d+):(\d{1,2})(?::(\d{1,2}))?$/)
  if (colon) {
    if (colon[3] !== undefined) return ((+colon[1]) * 3600 + (+colon[2]) * 60 + (+colon[3])) * 1000
    return ((+colon[1]) * 60 + (+colon[2])) * 1000
  }
  var total = 0, matched = false
  var re = /(\d+(?:\.\d+)?)\s*(h|m|s)?/g
  var m
  var rest = s
  while ((m = re.exec(s)) !== null) {
    if (!m[0]) break
    matched = true
    var n = parseFloat(m[1])
    var unit = m[2] || "m"          // a bare trailing number is minutes ("1h30")
    total += unit === "h" ? n * 3600000 : unit === "s" ? n * 1000 : n * 60000
    rest = rest.replace(m[0], "")
  }
  if (!matched || rest.trim() !== "") return NaN
  return total
}

// Seconds as "1:23" or "1:02:03" (floors; MPRIS gives fractional seconds)
function clockTime(seconds) {
  if (!isNum(seconds) || seconds < 0) return "--"
  var total = Math.floor(seconds)
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var mm = h > 0 && m < 10 ? "0" + m : String(m)
  var ss = s < 10 ? "0" + s : String(s)
  return (h > 0 ? h + ":" : "") + mm + ":" + ss
}
