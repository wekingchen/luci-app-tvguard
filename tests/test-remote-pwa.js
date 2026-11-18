// 真实运行手机 app.js：DOM/fetch 模拟断网、配对、按钮状态和防重复奖励。
'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

function node(id) {
  const classes = new Set(id === 'pair' || id === 'main' || id === 'errorBox' ? ['hidden'] : []);
  return {
    id, textContent: '', value: '', disabled: false, style: {},
    dataset: {}, handlers: {},
    classList: {
      add(c) { classes.add(c); },
      remove(c) { classes.delete(c); },
      contains(c) { return classes.has(c); },
    },
    addEventListener(event, fn) { this.handlers[event] = fn; },
  };
}
const ids = ['main','pair','network','mode','watched','remaining','quota','bar','control',
             'bonus','updated','errorBox','pairCode','pairButton','refresh'];
const els = Object.fromEntries(ids.map(id => [id, node(id)]));
const controls = ['mode-child','mode-parent','mode-locked','bonus-15','bonus-30',
                  'bonus-60','bonus-undo'].map(name => {
  const item = node(name); item.dataset.action = name; return item;
});
const queue = [];
const calls = [];
let onLoad = null;
const document = {
  hidden: false,
  getElementById(id) { assert(els[id], 'missing id ' + id); return els[id]; },
  querySelectorAll(query) { return query === '[data-action]' ? controls :
    query === 'button' ? [...controls,els.pairButton,els.refresh] : []; },
  addEventListener(event, fn) { if (event === 'DOMContentLoaded') onLoad = fn; }
};
const window = { confirm: () => true, setInterval: () => 1 };
async function fetch(url, opts) {
  calls.push({url,opts});
  assert(queue.length, 'missing response for ' + url);
  const result = queue.shift();
  if (result.error) throw new Error(result.error);
  return { ok: result.status >= 200 && result.status < 300,
           status: result.status, json: async () => result.body };
}
const context = vm.createContext({document,window,fetch,Date,Math,Number,String,Error,encodeURIComponent});
vm.runInContext(fs.readFileSync('root/usr/share/tvguard-remote/www/app.js','utf8'),context);
assert(onLoad);
function reply(status,body) { queue.push({status,body}); }
function call(expr) { return vm.runInContext(expr,context); }
const status = {mode:'child', watch_seconds:0, remaining_seconds:3600,quota_seconds:3600,
                bonus_seconds:0, bonus_limit_seconds:7200, bonus_undo_available:0,
                enforce:1, blocked:0};
const nextTick = () => new Promise(resolve => setImmediate(resolve));

(async () => {
  reply(200,status);
  onLoad();
  await nextTick();await nextTick();
  assert(els.main.classList.contains('hidden') === false);
  assert(els.pair.classList.contains('hidden'));
  assert.strictEqual(els.watched.textContent,'0 分钟');
  assert.strictEqual(els.remaining.textContent,'1 小时 0 分钟');
  assert.strictEqual(els.network.textContent,'已连接');
  assert(controls.find(c => c.dataset.action === 'mode-child').disabled,'current mode must be disabled');
  assert(controls.find(c => c.dataset.action === 'bonus-undo').disabled,'undo with zero should be disabled');

  reply(200,{...status,bonus_seconds:900,bonus_undo_available:1});
  await call("action('bonus-15')");
  assert.strictEqual(calls.at(-1).url,'/cgi-bin/tvg?action=bonus-15');
  assert.strictEqual(calls.at(-1).opts.method,'POST');
  assert.strictEqual(calls.at(-1).opts.credentials,'same-origin');
  assert.strictEqual(els.bonus.textContent,'今日已奖励 15 分钟 / 120 分钟');
  assert(!controls.find(c => c.dataset.action === 'bonus-undo').disabled);

  queue.push({error:'network interrupted'});
  await call("action('bonus-15')");
  assert.strictEqual(els.network.textContent,'操作待确认');
  assert(els.errorBox.textContent.includes('防止重复奖励'));
  assert(controls.every(c => c.disabled),'uncertain outcome must freeze all buttons');

  reply(200,status);
  await call('refresh()');
  assert.strictEqual(els.network.textContent,'已连接');
  assert(!controls.find(c => c.dataset.action === 'bonus-15').disabled);

  queue.push({error:'offline'});
  await call('refresh()');
  assert.strictEqual(els.network.textContent,'连接异常');
  assert(controls.every(c => c.disabled),'offline state must prevent actions');

  reply(401,{ok:false,error:'pair_required'});
  await call('refresh()');
  assert(!els.pair.classList.contains('hidden'));
  assert(els.main.classList.contains('hidden'));

  els.pairCode.value = 'a1'.repeat(16);
  reply(200,{ok:true,paired:true});
  reply(200,status);
  await call('pair()');
  assert.strictEqual(els.pairCode.value,'');
  assert(!els.main.classList.contains('hidden'));
  assert(calls.some(c => c.opts.method==='POST' && c.url.includes('action=pair')));

  console.log('PASS: iPhone PWA DOM/fetch, zero watch, pairing, offline, and no duplicate bonus after uncertain POST');
})().catch(err => { console.error(err); process.exitCode=1; });
