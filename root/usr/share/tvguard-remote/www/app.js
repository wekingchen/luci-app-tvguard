'use strict';
const $ = id => document.getElementById(id);
let busy = false;
let session = null;
const fmt = s => {
    const n = Math.max(0, Number(s) || 0);
    const m = Math.ceil(n / 60);
    return m >= 60 ? Math.floor(m / 60) + ' 小时 ' + (m % 60) + ' 分钟' : m + ' 分钟';
};
function error(msg) { $('errorBox').textContent = msg; $('errorBox').classList.remove('hidden'); }
function clearError() { $('errorBox').classList.add('hidden'); $('errorBox').textContent = ''; }
async function request(method, action, body) {
    const headers = {};
    if (method === 'POST') {
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    const resp = await fetch('/cgi-bin/tvg?action=' + encodeURIComponent(action), {
        method, headers, body: body || undefined, credentials: 'same-origin',
        cache: 'no-store', redirect: 'error'
    });
    let json;
    try { json = await resp.json(); } catch (_) { throw Error('设备返回的数据格式不正确'); }
    if (!resp.ok) {
        if (resp.status === 401) { showPair(); throw Error('设备授权已失效，请重新配对'); }
        throw Error('操作未完成：' + (json.error || 'HTTP ' + resp.status));
    }
    return json;
}
function showPair() { session = null; $('main').classList.add('hidden'); $('pair').classList.remove('hidden'); $('network').textContent = '待配对'; }
function showMain() { $('main').classList.remove('hidden'); $('pair').classList.add('hidden'); $('network').textContent = '已连接'; }
function paint(s) {
    session = s;
    const names = {child:'儿童模式', parent:'家长模式', locked:'已锁定'};
    $('mode').textContent = names[s.mode] || '未知状态';
    $('watched').textContent = fmt(s.watch_seconds);
    $('remaining').textContent = s.mode === 'parent' ? '不限时' :
        (s.mode === 'locked' ? '已锁定' : fmt(s.remaining_seconds));
    $('quota').textContent = '当日额度 ' + fmt(s.quota_seconds) + ' · 奖励 ' + fmt(s.bonus_seconds);
    const quota = Math.max(0, Number(s.quota_seconds) || 0);
    const used = Math.max(0, Number(s.watch_seconds) || 0);
    $('bar').style.width = (quota ? Math.min(100, used * 100 / quota) : (used ? 100 : 0)) + '%';
    $('control').textContent = !Number(s.enforce) ?
        '当前仅观察，不会正式断网' :
        (Number(s.blocked) ? '电视网络已被 TVGuard 限制' : '正式控制已启用');
    $('bonus').textContent = '今日已奖励 ' + fmt(s.bonus_seconds) + ' / ' + fmt(s.bonus_limit_seconds);
    $('updated').textContent = '上次更新：' + new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit'});
    document.querySelectorAll('[data-action]').forEach(b => {
        const a = b.dataset.action;
        b.disabled = busy || a === 'mode-' + s.mode ||
            (a === 'bonus-undo' && !Number(s.bonus_undo_available)) ||
            (a.startsWith('bonus-') && a !== 'bonus-undo' &&
                (Number(s.bonus_seconds) + Number(a.slice(6)) * 60 > Number(s.bonus_limit_seconds)));
    });
    showMain();
}
async function refresh() {
    try { const s = await request('GET','status'); clearError(); paint(s); }
    catch(e) { $('network').textContent = '连接异常'; if (!String(e.message).includes('重新配对')) error(e.message || String(e)); }
}
async function action(a) {
    if (busy) return;
    const confirmations = {
        'mode-parent':'家长模式会持续放行，直到你手动切回儿童模式。确定切换吗？',
        'mode-locked':'确定立即锁定电视网络吗？',
        'bonus-undo':'确认撤销最近一次奖励吗？'
    };
    if (confirmations[a] && !window.confirm(confirmations[a])) return;
    busy = true;
    document.querySelectorAll('button').forEach(x => { x.disabled = true; });
    try { const s=await request('POST',a);clearError();paint(s); }
    catch(e) { error(e.message || String(e)); }
    finally {busy=false;if(session) paint(session);}
}
async function pair() {
    if (busy) return;
    const code = $('pairCode').value.trim().toLowerCase();
    if (!/^[0-9a-f]{32}$/.test(code)) { error('请输入 LuCI 生成的 32 位配对码'); return; }
    busy = true; $('pairButton').disabled = true;
    try {
        await request('POST','pair','code=' + encodeURIComponent(code));
        $('pairCode').value = '';
        clearError();
        await refresh();
    } catch(e) { error(e.message || String(e)); }
    finally { busy = false; $('pairButton').disabled = false; }
}
document.addEventListener('DOMContentLoaded', () => {
    $('pairButton').addEventListener('click', pair);
    $('refresh').addEventListener('click', refresh);
    document.querySelectorAll('[data-action]').forEach(b => b.addEventListener('click', () => action(b.dataset.action)));
    refresh();
    window.setInterval(() => { if (!busy && !document.hidden) refresh(); }, 15000);
});
