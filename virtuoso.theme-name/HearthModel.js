.pragma library

// Row parsing for the Virtuoso Hearth. Theme rows come from
// `omarchy-theme-switcher --print-rows` as "<preview>\t<thumb>" where the
// preview file name is the theme slug; wallpaper rows come from
// `omarchy-menu-images --print-rows` as "<image>\t<thumb>".

var MaxEntries = 200

function baseName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : ""
}

function stripExtension(name) {
  var text = String(name || "")
  var i = text.lastIndexOf(".")
  return i > 0 ? text.slice(0, i) : text
}

function themeSlug(previewPath) {
  return stripExtension(baseName(previewPath))
}

function prettyLabel(slug) {
  var words = String(slug || "").replace(/[_-]+/g, " ").split(" ")
  var out = []
  for (var i = 0; i < words.length; i++) {
    if (words[i] === "") continue
    out.push(words[i].charAt(0).toUpperCase() + words[i].slice(1))
  }
  return out.join(" ")
}

function normalKey(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "")
}

function parseThemeRows(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length && out.length < MaxEntries; i++) {
    if (!lines[i]) continue
    var cols = lines[i].split("\t")
    if (!cols[0]) continue
    var slug = themeSlug(cols[0])
    if (!slug) continue
    out.push({
      slug: slug,
      label: prettyLabel(slug),
      preview: cols[0],
      thumb: cols[1] || cols[0]
    })
  }
  return out
}

function parseWallpaperRows(text) {
  var lines = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length && out.length < MaxEntries; i++) {
    if (!lines[i]) continue
    var cols = lines[i].split("\t")
    if (!cols[0]) continue
    out.push({
      path: cols[0],
      label: prettyLabel(stripExtension(baseName(cols[0]))),
      thumb: cols[1] || cols[0]
    })
  }
  return out
}

function indexOfTheme(entries, themeName) {
  var key = normalKey(themeName)
  if (!key) return 0
  for (var i = 0; i < entries.length; i++) {
    if (normalKey(entries[i].slug) === key) return i
  }
  return 0
}

function indexOfPath(entries, path) {
  var wanted = String(path || "")
  if (!wanted) return 0
  for (var i = 0; i < entries.length; i++) {
    if (String(entries[i].path || "") === wanted) return i
  }
  return 0
}

function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, Number(index) || 0))
}
