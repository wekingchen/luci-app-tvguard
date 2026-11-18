#!/usr/bin/env python3
"""Guard TVGuard LuCI dark-theme contrast without relying on host theme colors."""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
css = (root / "htdocs/luci-static/resources/view/tvguard/panel.css").read_text()
remote = (root / "htdocs/luci-static/resources/view/tvguard/remote.js").read_text()
tunnel = (root / "htdocs/luci-static/resources/view/tvguard/tunnel.js").read_text()
makefile = (root / "Makefile").read_text()
version = re.search(r"^PKG_VERSION:=(\S+)$", makefile, re.M).group(1)
release = re.search(r"^PKG_RELEASE:=(\d+)$", makefile, re.M).group(1)
query = "?v=" + version + "-r" + release

def rgb(value):
    h = value.lstrip("#")
    assert len(h) == 6, value
    return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]

def luminance(color):
    channel = lambda x: x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(v) for v in rgb(color))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def contrast(fg, bg):
    a, b = sorted((luminance(fg), luminance(bg)), reverse=True)
    return (a + 0.05) / (b + 0.05)

dark = css.split("@media (prefers-color-scheme: dark)", 1)[1].split(
    "/* 家长设备行", 1
)[0]
assert "--tvg-muted:#c4d0e4" in dark, "dark mode helper text should not use dim grey"
assert ".tvg-console code.tvg-code" in dark, "dark mode pairing code needs a specific selector"
assert "color: #f7faff !important" in dark, "LuCI native code styling can override inherited text"
assert "background: #283c5a" in dark, "pairing code background missing"
assert "background: transparent !important" in dark, "theme title background reset missing"
assert ".tvg-console .tvg-details summary { color: #d1dfff; }" in dark
assert "font-family: ui-monospace" in css, "pair code should use legible monospaced glyphs"
assert "background: transparent; box-shadow: none" in css, "overview-style card background missing"
assert ".tvg-settings-root .cbi-section" in css, "settings form theme missing"

for name, foreground, background in [
    ("pairing code", "#f7faff", "#283c5a"),
    ("helper text", "#c4d0e4", "#19253a"),
    ("card title", "#f1f5ff", "#19253a"),
    ("details summary", "#d1dfff", "#19253a"),
]:
    ratio = contrast(foreground, background)
    assert ratio >= 4.5, f"{name} contrast ratio is only {ratio:.2f}:1"

for page in (remote, tunnel):
    assert "STYLE + '" + query + "'" in page, "LuCI stylesheet cache key must match IPK revision"
    assert "'role': 'heading', 'aria-level': '2'" in page, "headings must remain accessible"
    assert not re.search(r"E\('h3',\s*\{\s*'class': 'tvg-card-title'", page), (
        "LuCI native h3 global styles must not cover TVGuard cards"
    )
print("PASS: LuCI dark pairing code, heading and helper text contrast, cache key, heading semantics")
