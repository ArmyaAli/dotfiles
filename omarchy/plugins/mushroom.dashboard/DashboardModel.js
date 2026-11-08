.pragma library

// ---------------------------------------------------------------------------
// Mushroom Grove Dashboard - data helpers
//
// Pure JS: weather parsing (wttr.in), RSS/Atom news parsing, and small
// formatting helpers. No QML or network here.
// ---------------------------------------------------------------------------

// RSS/Atom feeds (Hacker News comes from the official API instead so its
// order matches the site).
var feeds = [
  { name: "BBC World", url: "https://feeds.bbci.co.uk/news/world/rss.xml", accent: "#72b39e" },
  { name: "Ars Technica", url: "https://feeds.arstechnica.com/arstechnica/index", accent: "#9dbb6d" },
  { name: "The Verge", url: "https://www.theverge.com/rss/index.xml", accent: "#e5b65d" }
]

// ------------------------------------------------------------------ weather

function parseLocation(raw) {
  var unset = { name: "", latitude: null, longitude: null }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return unset
    var lat = parseFloat(data.latitude)
    var lon = parseFloat(data.longitude)
    var has = !isNaN(lat) && !isNaN(lon)
    return {
      name: typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : "",
      latitude: has ? lat : null,
      longitude: has ? lon : null
    }
  } catch (e) {
    return unset
  }
}

function locationQuery(loc) {
  if (!loc) return ""
  var lat = parseFloat(String(loc.latitude))
  var lon = parseFloat(String(loc.longitude))
  if (!isNaN(lat) && !isNaN(lon)) return lat + "," + lon
  var name = String(loc.name || "").replace(/^\s+|\s+$/g, "")
  return name === "" ? "" : encodeURIComponent(name)
}

function iconForCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  switch (c) {
    case 113: return night ? "\ue32b" : "\ue30d"
    case 116: return night ? "\ue32e" : "\ue302"
    case 119: case 122: return "\ue33d"
    case 143: case 248: case 260: return night ? "\ue346" : "\ue313"
    case 176: case 263: case 353: return night ? "\ue333" : "\ue308"
    case 179: case 227: case 230: case 323: case 326: case 368: return night ? "\ue327" : "\ue30a"
    case 182: case 185: case 281: case 284: case 311: case 314:
    case 317: case 320: case 350: case 362: case 365: case 374: case 377: return "\ue3ad"
    case 200: case 386: case 389: case 392: case 395: return "\ue31d"
    case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359: return "\ue318"
    case 329: case 332: case 335: case 338: case 371: return "\ue31a"
    default: return "\ue33d"
  }
}

function dayIcon(day) {
  if (!day || !day.hourly || day.hourly.length === 0) return "\ue33d"
  var best = day.hourly[0]
  var bestDist = 9999
  for (var i = 0; i < day.hourly.length; i++) {
    var t = parseInt(String(day.hourly[i].time || "0"), 10)
    var dist = Math.abs(t - 1200)
    if (dist < bestDist) { bestDist = dist; best = day.hourly[i] }
  }
  return iconForCode(best.weatherCode, false)
}

function dayDesc(day) {
  if (!day || !day.hourly || day.hourly.length === 0) return ""
  var best = day.hourly[0]
  var bestDist = 9999
  for (var i = 0; i < day.hourly.length; i++) {
    var t = parseInt(String(day.hourly[i].time || "0"), 10)
    var dist = Math.abs(t - 1200)
    if (dist < bestDist) { bestDist = dist; best = day.hourly[i] }
  }
  return best.weatherDesc && best.weatherDesc[0] ? best.weatherDesc[0].value : ""
}

function dayName(dateString) {
  var d = new Date(String(dateString || "") + "T12:00:00")
  if (isNaN(d.getTime())) return ""
  return Qt.formatDate(d, "ddd")
}

// Current conditions plus the next few days from a wttr.in j1 report.
function weatherFromReport(report, configuredName) {
  if (!report) return null
  var cur = report.current_condition && report.current_condition[0]
  if (!cur) return null
  var area = report.nearest_area && report.nearest_area[0]
  var days = []
  var raw = report.weather || []
  for (var i = 0; i < raw.length && days.length < 4; i++) {
    days.push({
      date: raw[i].date,
      name: dayName(raw[i].date),
      maxC: raw[i].maxtempC,
      minC: raw[i].mintempC,
      icon: dayIcon(raw[i]),
      desc: dayDesc(raw[i])
    })
  }
  return {
    tempC: cur.temp_C,
    feelsC: cur.FeelsLikeC,
    desc: cur.weatherDesc && cur.weatherDesc[0] ? cur.weatherDesc[0].value : "",
    humidity: cur.humidity,
    windKmph: cur.windspeedKmph,
    pressure: cur.pressure,
    icon: iconForCode(cur.weatherCode, false),
    location: configuredName || (area && area.areaName && area.areaName[0] ? area.areaName[0].value : ""),
    region: area && area.country && area.country[0] ? area.country[0].value : "",
    days: days
  }
}

// --------------------------------------------------------------------- news

function decodeEntities(value) {
  var s = String(value || "")
  s = s.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
  s = s.replace(/<[^>]+>/g, "")
  s = s.replace(/&lt;/g, "<").replace(/&gt;/g, ">")
  s = s.replace(/&quot;/g, "\"").replace(/&#0?39;/g, "'").replace(/&apos;/g, "'")
  s = s.replace(/&nbsp;/g, " ")
  s = s.replace(/&#x([0-9a-fA-F]+);/g, function(_, h) {
    return String.fromCharCode(parseInt(h, 16))
  })
  s = s.replace(/&#([0-9]+);/g, function(_, d) {
    return String.fromCharCode(parseInt(d, 10))
  })
  s = s.replace(/&amp;/g, "&")
  return s.replace(/\s+/g, " ").trim()
}

function tagText(block, name) {
  var re = new RegExp("<" + name + "[^>]*>([\\s\\S]*?)<\\/" + name + ">", "i")
  var m = block.match(re)
  return m ? decodeEntities(m[1]) : ""
}

function atomLink(block) {
  var alt = block.match(/<link[^>]*rel=["']alternate["'][^>]*href=["']([^"']+)["']/i)
  if (alt) return decodeEntities(alt[1])
  var any = block.match(/<link[^>]*href=["']([^"']+)["']/i)
  return any ? decodeEntities(any[1]) : ""
}

function parseDate(value) {
  var s = String(value || "").trim()
  if (!s) return 0
  var t = Date.parse(s)
  return isNaN(t) ? 0 : t
}

function parseFeed(xml, source, limit) {
  var out = []
  var max = limit || 12
  var re = /<(item|entry)[\s>][\s\S]*?<\/\1>/gi
  var m
  while ((m = re.exec(String(xml || ""))) && out.length < max) {
    var block = m[0]
    var atom = /^<entry/i.test(block)
    var title = tagText(block, "title")
    if (!title) continue
    var link = atom ? atomLink(block) : tagText(block, "link")
    var date = atom
      ? (tagText(block, "updated") || tagText(block, "published"))
      : tagText(block, "pubDate")
    out.push({
      title: title,
      link: link,
      source: source,
      timestamp: parseDate(date),
      date: date
    })
  }
  return out
}

// Merge feed batches into one list. Items are interleaved round-robin rather
// than time-sorted, so each source keeps its own order (Hacker News matches the
// front page). De-duplicated by title and capped at `limit`.
function mergeNews(batches, limit) {
  var seen = {}
  var out = []
  var maxLen = 0
  for (var b = 0; b < batches.length; b++) {
    if (batches[b] && batches[b].length > maxLen) maxLen = batches[b].length
  }
  for (var i = 0; i < maxLen; i++) {
    for (var f = 0; f < batches.length; f++) {
      var list = batches[f] || []
      var item = list[i]
      if (!item) continue
      var key = item.title.toLowerCase()
      if (seen[key]) continue
      seen[key] = true
      out.push(item)
      if (out.length >= (limit || 40)) return out
    }
  }
  return out
}

// Parse the tab-separated output of hn.py: title, url, time, score, comments.
function parseHn(raw) {
  var out = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var parts = line.split("\t")
    if (parts.length < 3) continue
    var title = parts[0].trim()
    if (!title) continue
    var ts = parseInt(parts[2], 10) || 0
    out.push({
      title: title,
      link: parts[1],
      source: "Hacker News",
      timestamp: ts * 1000,
      points: parseInt(parts[3], 10) || 0,
      comments: parseInt(parts[4], 10) || 0,
      date: ""
    })
  }
  return out
}

function relativeTime(timestamp, nowMs) {
  if (!timestamp) return ""
  var diff = Math.max(0, Math.floor(((nowMs || Date.now()) - timestamp) / 1000))
  if (diff < 60) return "now"
  if (diff < 3600) return Math.floor(diff / 60) + "m"
  if (diff < 86400) return Math.floor(diff / 3600) + "h"
  return Math.floor(diff / 86400) + "d"
}
