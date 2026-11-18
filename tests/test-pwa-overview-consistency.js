// TVGuard Web App visual contract: align with LuCI overview without copying LuCI's scripts.
// Preserve a native, accessible standalone phone experience and iOS safe-area rules.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const pwa = 'root/usr/share/tvguard-remote/www/';
const overview = fs.readFileSync('htdocs/luci-static/resources/view/tvguard/overview.js','utf8');
const css = fs.readFileSync(pwa+'style.css','utf8');
const html = fs.readFileSync(pwa+'index.html','utf8');
const app = fs.readFileSync(pwa+'app.js','utf8');
const tokens = fs.readFileSync('htdocs/luci-static/resources/view/tvguard/panel.css','utf8');
const manifest = JSON.parse(fs.readFileSync(pwa+'manifest.webmanifest','utf8'));
const makefile = fs.readFileSync('Makefile','utf8');
const version = makefile.match(/^PKG_VERSION:=(\S+)$/m)?.[1];
const release = makefile.match(/^PKG_RELEASE:=(\d+)$/m)?.[1];
assert(version && release, 'package metadata missing');
for (const asset of ['style.css','app.js']) {
  assert(html.includes('/'+asset+'?v='+version+'-r'+release), 'stale Web App asset URL: '+asset);
}
for (const value of [
  '.tvg-panel{margin:0 0 14px;padding:15px;border:1px solid rgba(127,127,127,.42);border-radius:12px;background:transparent;box-shadow:none;}',
  '.tvg-metric{min-width:0;padding:13px;border:1px solid rgba(127,127,127,.32);border-radius:10px;background:rgba(127,127,127,.08);}',
  '.tvg-panel-title{font-size:1.12rem;',
  '@media(max-width:700px)'
]) assert(overview.includes(value), 'canonical overview changed: '+value);
for (const value of [
  '--line: rgba(127,127,127,.42)',
  '--tile-line: rgba(127,127,127,.32)',
  '--soft: rgba(127,127,127,.08)',
  'border-radius: 12px',
  'border-radius: 10px',
  'background: transparent',
  'background: var(--soft)',
  'box-shadow: none',
  'font-size: 1.45rem',
  'font-size: 1.12rem',
  '@media (max-width: 700px)'
]) assert(css.includes(value), 'PWA missing overview design token: '+value);
for (const value of [
  '--tvg-border: rgba(127,127,127,.42)',
  '--tvg-line: rgba(127,127,127,.32)',
  '--tvg-soft: rgba(127,127,127,.08)'
]) assert(tokens.includes(value), 'LuCI design tokens unexpectedly drifted: '+value);

assert(css.includes('min-height: 44px'), 'phone tap targets cannot shrink to LuCI desktop size');
assert(css.includes('@media (display-mode: standalone), (display-mode: fullscreen)'), 'home-screen display mode required');
assert(css.includes('max(88px'), 'iOS 27 zero-top-inset fallback required');
assert(css.includes('env(safe-area-inset-bottom'), 'home indicator padding required');
assert(css.includes('html.pwa-standalone .shell'), 'legacy standalone detection required');
assert(css.includes('@media (prefers-color-scheme: dark)'), 'dark mode missing');
assert(css.includes('@media (prefers-reduced-motion: reduce)'), 'reduced motion required');
assert(css.includes('button[data-action^="mode-"].is-current:disabled'), 'selected mode must remain visibly selected');
assert(css.includes('button[data-action="mode-locked"].is-current:disabled'), 'locked state distinct');
assert(css.includes('.progress.is-unlimited { display: none; }'), 'parent progress bar should stay hidden');
assert(css.includes('white-space: nowrap') && css.includes('text-overflow: ellipsis'), 'status label should not wrap');
assert(html.includes('<h1>TVGuard</h1>'), 'Web App brand header missing');
assert(html.includes('id="network"') && html.includes('aria-live="polite"'), 'connection badge must stay accessible');
assert(html.includes('id="pairCode"') && html.includes('data-action="bonus-undo"'), 'pairing and reward controls must remain');
assert(manifest.display === 'standalone' && manifest.start_url === '/', 'standalone icon launch changed');
assert(app.includes('window.navigator.standalone === true'), 'legacy iOS standalone compatibility removed');
assert(app.includes("state === '在线' ? '远程连接正常'"), 'verified concise connection wording removed');

function contrast(foreground, background) {
  function lum(color) {
    const c = color.slice(1).match(/../g).map(hex => parseInt(hex,16)/255)
      .map(x => x<=.04045 ? x/12.92 : ((x+.055)/1.055)**2.4);
    return .2126*c[0]+.7152*c[1]+.0722*c[2];
  }
  const a=lum(foreground),b=lum(background);
  return (Math.max(a,b)+.05)/(Math.min(a,b)+.05);
}
for(const [label, fg,bg] of [
  ['light text','#202b3c','#f4f6fa'],
  ['light helper text','#5c6b80','#f4f6fa'],
  ['light primary button','#ffffff','#4165d1'],
  ['dark text','#f1f5ff','#101a2a'],
  ['dark helper text','#c4d0e4','#101a2a'],
  ['dark primary button','#ffffff','#4e66cd']
]){
  assert(contrast(fg,bg)>=4.5, label+' has insufficient contrast '+contrast(fg,bg).toFixed(2));
}
console.log('PASS: overview-aligned PWA panels/metrics/typography, 44px tap targets, iOS safe areas, dark/light contrast and unchanged controls');
