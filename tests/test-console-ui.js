// 家长遥控 / 远程访问：真实执行 LuCI 页面逻辑并检查桌面与手机响应式契约。
'use strict';
const assert = require('assert');
const fs = require('fs');

function E(tag, attrs, children) {
    const node = {
        tag, attrs: attrs || {}, children: [],
        style: {}, disabled: false, textContent: '', className: (attrs || {}).class || '',
        href: (attrs || {}).href || '',
        appendChild(child) { this.children.push(child); },
        replaceChildren(...items) { this.children = items; },
        removeAttribute(prop) { delete this[prop]; }
    };
    if (children !== undefined) {
        if (typeof children === 'string') node.textContent = children;
        node.children = Array.isArray(children) ? children : [children];
    }
    return node;
}
function all(root, fn, out=[]) {
    if (root && typeof root === 'object') {
        if (fn(root)) out.push(root);
        for (const child of root.children || []) all(child, fn, out);
    }
    return out;
}
function strings(root) {
    return all(root, x => typeof x === 'object').flatMap(x => [
        x.textContent || '',
        ...(x.children || []).filter(y => typeof y === 'string')
    ]).join(' ');
}
function find(root, tag, text) {
    const matches = all(root, x => x.tag === tag && (!text || strings(x).includes(text)));
    assert(matches.length, 'missing '+tag+' '+text);
    return matches[0];
}
function create(path, state, fakeAction) {
    const calls = [], notifications = [];
    const ex = { exec: async (cmd, args) => {
        calls.push({cmd,args});
        if (cmd.includes('-manage')) return {code:0,stdout:fakeAction(args)};
        if (args[0] === 'logs') return {code:0,stdout:'2026-11-18 connected'};
        return {code:0,stdout:JSON.stringify(state())};
    }};
    const ui = { addNotification:(_,node,level)=>notifications.push({node,level}) };
    const window = { confirm:()=>true };
    const view = { extend:x=>x };
    const source = fs.readFileSync(path,'utf8');
    const page = new Function('view','fs','ui','E','window',source)(view,ex,ui,E,window);
    const tree = page.render(state());
    return {tree,calls,notifications};
}
function nodeWithClass(root, name) {
    return all(root,x=>typeof x.className==='string'&&x.className.split(/\s+/).includes(name));
}
(async () => {
    const css = fs.readFileSync('htdocs/luci-static/resources/view/tvguard/panel.css','utf8');
    assert(css.includes('.tvg-console') && css.includes('.tvg-status-grid'));
    assert(css.includes('.tvg-page-heading') && css.includes('background: transparent'), 'isolated heading styling is missing');
    assert(css.includes('grid-template-columns: repeat(2, minmax(0,1fr))'), 'desktop two columns missing');
    assert(css.includes('@media (max-width: 850px)') && css.includes('@media (max-width: 560px)'));
    assert(css.includes('.tvg-device { flex-direction: column'), 'mobile device controls need vertical layout');
    assert(css.includes('.tvg-address { align-items: stretch; flex-direction: column'), 'mobile address stacking missing');

    let parent = {enabled:true,listener:true,lan_enabled:true,
        lan_url:'http://192.168.101.99:18765/',paired:2,
        devices:[
            {id:'0123456789abcdef',name:'iPhone Chrome',paired_at:1795000000,expires:0},
            {id:'fedcba9876543210',name:'iPad Browser',paired_at:0,expires:0}
        ]};
    let confirmed = false;
    const p=create('htdocs/luci-static/resources/view/tvguard/remote.js',()=>parent,args=>{
        if (args[0]==='pair') return '配对码：'+'ab'.repeat(16);
        if (args[0]==='revoke-device') {
            assert.strictEqual(args.length,2);
            assert(/^[a-f0-9]{16}$/.test(args[1]));
            parent={...parent,devices:parent.devices.filter(x=>x.id!==args[1]),paired:1};
            confirmed = true;
            return '设备已撤销';
        }
        if (args[0]==='disable-lan') { parent={...parent,lan_enabled:false}; return '局域网已关闭'; }
        return 'ok';
    });
    assert(nodeWithClass(p.tree,'tvg-console').length === 1);
    assert(nodeWithClass(p.tree,'tvg-stat').length === 3);
    assert(nodeWithClass(p.tree,'tvg-card').length === 4);
    assert(find(p.tree,'link').attrs.href.includes('panel.css'));
    assert(find(p.tree,'link').attrs.href.includes('?v=0.1.16-r19'), 'LuCI parent CSS cache key stale');
    const code = nodeWithClass(p.tree,'tvg-code')[0];
    assert(code && code.tag === 'code', 'pairing code must remain selectable code');
    const parentHeadings = nodeWithClass(p.tree,'tvg-card-title');
    assert(parentHeadings.length === 4, 'parent card title count changed');
    assert(parentHeadings.every(x => x.tag === 'div' && x.attrs.role === 'heading' && x.attrs['aria-level'] === '2'),
      'avoid theme-global h3 selectors while keeping accessible card headings');
    assert(all(p.tree,x=>x.tag==='header'||x.tag==='h2').length===0,'theme global selectors must not cover page title');
    assert(all(p.tree,x=>x.className==='tvg-page-heading'&&strings(x).includes('家长遥控')).length===1);
    assert(strings(p.tree).includes('192.168.101.99:18765'));
    assert(strings(p.tree).includes('iPhone Chrome'));
    assert(strings(p.tree).includes('长期有效'));
    assert(strings(p.tree).includes('fedcba9876543210'));
    assert(all(p.tree,x=>x.tag==='details').length>=2);
    assert(all(p.tree,x=>x.tag==='button').some(x=>x.textContent==='停止服务'&&!x.disabled));
    await find(p.tree,'button','生成 5 分钟配对码').attrs.click();
    assert(strings(p.tree).includes('ab'.repeat(16)),'generated code not visible');
    assert(strings(p.tree).includes('剩余 5 分 00 秒'),'pair countdown did not start');
    await find(p.tree,'button','撤销此设备').attrs.click();
    assert(confirmed);
    assert(!strings(p.tree).includes('0123456789abcdef'));
    assert(strings(p.tree).includes('iPad Browser'));
    await find(p.tree,'button','关闭局域网入口').attrs.click();
    assert(!strings(p.tree).includes('http://192.168.101.99:18765/'), 'disabled LAN link still visible');

    let tunnel = {configured:true,storage_ready:true,docker_ready:true,
        image_present:true,container:'running',metrics_local:true};
    const t=create('htdocs/luci-static/resources/view/tvguard/tunnel.js',()=>tunnel,args=>{
        if (args[0]==='stop') {tunnel={...tunnel,container:'exited'};return '已停止';}
        return 'ok';
    });
    assert(nodeWithClass(t.tree,'tvg-console').length === 1);
    assert(all(t.tree,x=>x.tag==='header'||x.tag==='h2').length===0,'tunnel title must avoid LuCI global header selectors');
    assert(all(t.tree,x=>x.className==='tvg-page-heading'&&strings(x).includes('远程访问')).length===1);
    assert(nodeWithClass(t.tree,'tvg-stat').length === 3);
    assert(nodeWithClass(t.tree,'tvg-card').length === 3);
    assert(find(t.tree,'link').attrs.href.includes('?v=0.1.16-r19'), 'LuCI tunnel CSS cache key stale');
    const tunnelHeadings = nodeWithClass(t.tree,'tvg-card-title');
    assert(tunnelHeadings.length === 3 && tunnelHeadings.every(x =>
        x.tag === 'div' && x.attrs.role === 'heading' && x.attrs['aria-level'] === '2'),
        'tunnel title strips must avoid theme h3 styling');
    assert(strings(t.tree).includes('tv.rqqr.de'));
    assert(strings(t.tree).includes('127.0.0.1:20241'));
    assert(strings(t.tree).includes('Token 已配置'));
    assert(find(t.tree,'button','启动 Tunnel').disabled,'running container should not be startable');
    await find(t.tree,'button','停止 Tunnel').attrs.click();
    assert(strings(t.tree).includes('已停止'));
    assert(!find(t.tree,'button','启动 Tunnel').disabled);
    await find(t.tree,'button','读取日志').attrs.click();
    assert(strings(t.tree).includes('2026-11-18 connected'));
    assert(!t.calls.some(x=>x.cmd.includes('tvguardctl')||x.cmd.includes('uci')));
    console.log('PASS: LuCI parent/tunnel responsive design, desktop cards, mobile breakpoints, controls and security boundaries');
})().catch(e=>{console.error(e); process.exitCode=1;});
