// UI consistency gate: overview is the canonical LuCI visual language.
// Only presentation is compared; UCI forms and remote actions retain their own logic.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const base = 'htdocs/luci-static/resources/view/tvguard/';
const overview = fs.readFileSync(base + 'overview.js', 'utf8');
const settings = fs.readFileSync(base + 'settings.js', 'utf8');
const remote = fs.readFileSync(base + 'remote.js', 'utf8');
const tunnel = fs.readFileSync(base + 'tunnel.js', 'utf8');
const css = fs.readFileSync(base + 'panel.css', 'utf8');
const makefile = fs.readFileSync('Makefile', 'utf8');

const version = makefile.match(/^PKG_VERSION:=(\S+)$/m)?.[1];
const release = makefile.match(/^PKG_RELEASE:=(\d+)$/m)?.[1];
assert(version && release, 'package identity missing');
const cacheKey = '?v=' + version + '-r' + release;

// Overview is deliberately left intact; other views mirror these primitives.
for (const value of [
  '.tvg-root{max-width:980px;margin:0 auto;padding:0 2px 20px;}',
  '.tvg-panel{margin:0 0 14px;padding:15px;border:1px solid rgba(127,127,127,.42);border-radius:12px;background:transparent;box-shadow:none;}',
  '.tvg-metric{min-width:0;padding:13px;border:1px solid rgba(127,127,127,.32);border-radius:10px;background:rgba(127,127,127,.08);}',
  '.tvg-page-title{font-size:1.45rem;',
  '.tvg-panel-title{font-size:1.12rem;',
  '@media(max-width:700px)'
]) assert(overview.includes(value), 'overview baseline changed: ' + value);

for (const value of [
  'max-width: 980px', '--tvg-border: rgba(127,127,127,.42)',
  '--tvg-line: rgba(127,127,127,.32)', '--tvg-soft: rgba(127,127,127,.08)',
  'border-radius: 12px; background: transparent; box-shadow: none',
  'font-size: 1.45rem', 'font-size: 1.12rem',
  'background: var(--tvg-soft)', '@media (max-width: 700px)',
  '.tvg-settings-root .cbi-section', '.tvg-console .tvg-stat'
]) assert(css.includes(value), 'shared LuCI overview design contract missing: ' + value);

for (const [name, source] of [['parent',remote],['tunnel',tunnel],['settings',settings]]) {
  assert(source.includes("STYLE + '" + cacheKey + "'"), name + ' stylesheet cache key stale');
  assert(source.includes("TV Guard · "), name + ' missing overview-style page heading');
  assert(source.includes("'aria-level': '1'"), name + ' missing accessible top heading');
}
for (const source of [remote,tunnel]) {
  assert(source.includes("'btn tvg-btn '"), 'actions should inherit overview native LuCI button styles');
  assert(source.includes("cbi-button-positive"), 'primary button action semantics missing');
  assert(source.includes("cbi-button-negative"), 'danger button semantics missing');
  assert(!source.includes('TVGUARD / REMOTE ACCESS') && !source.includes('TVGUARD / PARENT ACCESS'),
    'non-overview English eyebrow should not remain');
}
assert(settings.includes('Promise.resolve(m.render()).then('), 'native LuCI form must remain intact');
assert(settings.includes('mapNode'), 'settings form must not be rewritten');
assert(!settings.includes('m.section(form.TypedSection'), 'settings model should remain unchanged');
assert(css.includes('.tvg-console code.tvg-code') && css.includes('color: #f7faff !important'),
  'r19 pairing code contrast correction must survive');
console.log('PASS: overview-led four-page LuCI typography, panels, metrics, buttons, UCI and mobile design contract');
