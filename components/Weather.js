.pragma library

// Weather helpers for the weather tile. Data comes from open-meteo using the
// coordinates Omarchy's bar weather widget stores in
// ~/.local/state/omarchy/settings/weather.json, so both agree on the place.

// Glyphs live in DotFont.js under these private-use characters.
var GLYPH = {
  sun: "",
  moon: "",
  partly: "",
  partlyNight: "",
  cloud: "",
  fog: "",
  rain: "",
  snow: "",
  storm: ""
}

// WMO weather code -> { label, glyph, severe }
function condition(code, isDay) {
  var c = parseInt(String(code === undefined || code === null ? "-1" : code), 10)
  var day = isDay !== 0 && isDay !== false
  if (c === 0) return { label: "clear", glyph: day ? GLYPH.sun : GLYPH.moon, severe: false }
  if (c === 1) return { label: "mostly clear", glyph: day ? GLYPH.partly : GLYPH.partlyNight, severe: false }
  if (c === 2) return { label: "partly cloudy", glyph: day ? GLYPH.partly : GLYPH.partlyNight, severe: false }
  if (c === 3) return { label: "overcast", glyph: GLYPH.cloud, severe: false }
  if (c === 45 || c === 48) return { label: "fog", glyph: GLYPH.fog, severe: false }
  if (c >= 51 && c <= 57) return { label: "drizzle", glyph: GLYPH.rain, severe: false }
  if (c >= 61 && c <= 67) return { label: c >= 66 ? "freezing rain" : "rain", glyph: GLYPH.rain, severe: c >= 65 }
  if (c >= 71 && c <= 77) return { label: "snow", glyph: GLYPH.snow, severe: c === 75 }
  if (c >= 80 && c <= 82) return { label: "showers", glyph: GLYPH.rain, severe: c === 82 }
  if (c === 85 || c === 86) return { label: "snow showers", glyph: GLYPH.snow, severe: c === 86 }
  if (c === 95) return { label: "thunderstorm", glyph: GLYPH.storm, severe: true }
  if (c === 96 || c === 99) return { label: "hail storm", glyph: GLYPH.storm, severe: true }
  return { label: "", glyph: GLYPH.cloud, severe: false }
}

// Same rule as Omarchy's bar widget: explicit unit, else the locale.
function useImperial(unitSetting, localeName) {
  var unit = String(unitSetting || "").trim().toLowerCase()
  if (unit === "imperial") return true
  if (unit === "metric") return false
  var name = String(localeName || "").replace(".", "_")
  return /^en[_-]US($|[_.-])/.test(name) || /^en[_-]LR($|[_.-])/.test(name) || /^my($|[_.-])/.test(name)
}

function parseLocation(raw) {
  try {
    var obj = JSON.parse(String(raw || "").trim() || "{}")
    var lat = parseFloat(String(obj.latitude))
    var lon = parseFloat(String(obj.longitude))
    return {
      name: String(obj.name || ""),
      latitude: isNaN(lat) ? null : lat,
      longitude: isNaN(lon) ? null : lon
    }
  } catch (e) {
    return { name: "", latitude: null, longitude: null }
  }
}

function forecastUrl(lat, lon, imperial) {
  return "https://api.open-meteo.com/v1/forecast"
    + "?latitude=" + encodeURIComponent(String(lat))
    + "&longitude=" + encodeURIComponent(String(lon))
    + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day,precipitation"
    + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
    + "&hourly=temperature_2m,weather_code,precipitation_probability"
    + "&forecast_days=4&forecast_hours=12&timezone=auto"
    + (imperial ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "&wind_speed_unit=kmh")
}

// Reduce an open-meteo response to what the tile draws.
function summarize(report) {
  if (!report || !report.current) return null
  var cur = report.current
  var out = {
    temp: num(cur.temperature_2m),
    feels: num(cur.apparent_temperature),
    humidity: num(cur.relative_humidity_2m),
    wind: num(cur.wind_speed_10m),
    code: num(cur.weather_code),
    isDay: cur.is_day !== 0,
    precip: num(cur.precipitation),
    days: [],
    hours: []
  }
  var d = report.daily
  if (d && Array.isArray(d.time)) {
    for (var i = 0; i < d.time.length; i++) {
      out.days.push({
        date: String(d.time[i]),
        code: num(d.weather_code ? d.weather_code[i] : null),
        max: num(d.temperature_2m_max ? d.temperature_2m_max[i] : null),
        min: num(d.temperature_2m_min ? d.temperature_2m_min[i] : null),
        rain: num(d.precipitation_probability_max ? d.precipitation_probability_max[i] : null)
      })
    }
  }
  var h = report.hourly
  if (h && Array.isArray(h.time)) {
    for (var j = 0; j < h.time.length; j++) {
      out.hours.push({
        time: String(h.time[j]),
        temp: num(h.temperature_2m ? h.temperature_2m[j] : null),
        code: num(h.weather_code ? h.weather_code[j] : null),
        rain: num(h.precipitation_probability ? h.precipitation_probability[j] : null)
      })
    }
  }
  return out
}

function num(v) {
  var n = Number(v)
  return v === null || v === undefined || isNaN(n) ? NaN : n
}

function dayName(dateString, todayString) {
  if (dateString === todayString) return "today"
  var parts = String(dateString).split("-")
  if (parts.length !== 3) return ""
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
  return ["sun", "mon", "tue", "wed", "thu", "fri", "sat"][d.getDay()]
}
