'use strict';
// Minimal LuCI DOM/runtime contract test. This executes render() and every
// progress phase, not merely JS syntax parsing.
const assert = require('node:assert/strict');
const fsNode = require('node:fs');
const source = fsNode.readFileSync(
    'htdocs/luci-static/resources/view/tvguard/overview.js', 'utf8'
);
const polls = new Map();
let reloads = 0;
let state = {
    mode: 'child', activity: 'active', firewall_state: 'allowed',
    date: '2026-11-08', enforce: 0, armed: 0, blocked: 0,
    used_seconds: 123, quota_seconds: 7200, remaining_seconds: 7077,
    bonus_seconds: 0, pps: 8, tcp_pps: 1, udp_pps: 7,
    bytes_per_second: 2900, traffic_class: 'low_traffic',
    shadow_label: 'unknown', calibration_phase: 'idle',
    calibration_label: 'none', calibration_app: 'none',
    calibration_last_session: 'none'
};
let commands = [];
const mockFs = {
    exec: (name, args) => {
        commands.push([name, args]);
        if (args[0] === 'status') return Promise.resolve({code: 0, stdout: JSON.stringify(state)});
        if (args[0] === 'log') return Promise.resolve({code: 0, stdout: ''});
        if (args[0] === 'calibration') return Promise.resolve({code: 0, stdout: 'sample line'});
        if (args[0] === 'isolation') return Promise.resolve({code: 0, stdout: 'ok\n'});
        if (name === '/usr/libexec/tvguardctl') return Promise.resolve({code: 0, stdout: ''});
        throw Error('unexpected command: ' + name + ' ' + args.join(' '));
    }
};
function E(tag, props, children) {
    if (props == null || Array.isArray(props) || typeof props !== 'object') {
        children = props;
        props = {};
    }
    const n = {
        tag, props, children: Array.isArray(children) ? children : [children],
        style: {}, disabled: false, textContent: '', value: props.value || '',
        attributes: {},
        setAttribute(k, v) { this.attributes[k] = v; },
    };
    if (tag === 'select') {
        n.options = n.children;
        n.selectedIndex = 0;
        n.value = n.options[0]?.props?.value || '';
    }
    if (tag === 'option') n.text = n.children.join('');
    return n;
}
const ui = {
    createHandlerFn(ctx, method, ...fixed) {
        return function(...rest) {
            const f = typeof method === 'string' ? ctx[method] : method;
            return f.apply(ctx, [...fixed, ...rest]);
        };
    },
    addNotification() {}
};
const poll = {
    add(fn, secs) { assert.equal(secs, 2); polls.set(fn, secs); },
    remove(fn) { polls.delete(fn); }
};
const L = { bind: (fn, ctx) => fn.bind(ctx) };
const win = { confirm: () => true, location: { reload: () => reloads++ } };
const view = { extend: (value) => value };
const factory = new Function('view', 'fs', 'ui', 'poll', 'L', 'E', 'window', source);
const page = factory(view, mockFs, ui, poll, L, E, win);
const updates = [
    {calibration_phase: 'running', calibration_label: 'system_home', calibration_app: 'system',
     calibration_remaining_seconds: 70, calibration_elapsed_seconds: 50,
     calibration_percent: 41, calibration_samples: 5, calibration_active: 1},
    {calibration_phase: 'finishing', calibration_label: 'system_home', calibration_app: 'system',
     calibration_remaining_seconds: 0, calibration_elapsed_seconds: 120,
     calibration_percent: 100, calibration_samples: 11, calibration_active: 0},
    {calibration_phase: 'completed', calibration_label: 'none', calibration_app: 'none',
     calibration_last_app: 'system', calibration_last_label: 'system_home',
     calibration_last_samples: 11, calibration_last_session: '12345-1'},
    {calibration_phase: 'stopped', calibration_label: 'none', calibration_app: 'none',
     calibration_last_app: 'mango', calibration_last_label: 'paused',
     calibration_last_samples: 3, calibration_last_session: '12345-2'},
    {calibration_phase: 'interrupted', calibration_label: 'none', calibration_app: 'none',
     calibration_last_app: 'tencent', calibration_last_label: 'playing',
     calibration_last_samples: 2, calibration_last_session: '12345-3'},
    {calibration_phase: 'idle', calibration_label: 'none', calibration_app: 'none'}
];
(async () => {
    const initial = await page.load();
    assert.equal(initial.length, 4);
    const root = page.render(initial);
    assert.equal(root.tag, 'div');
    assert.equal(polls.size, 1);
    assert.equal(page._calibrationNodes.start.disabled, false);
    assert.equal(page._calibrationNodes.stop.disabled, true);
    assert.equal(page._uiSummary.mode, '儿童模式');
    assert.equal(page._uiSummary.control, '观察模式');
    assert.equal(page._uiSummary.isolationSafe, true);
    assert.equal(page._uiSummary.canEnableEnforcement, false);
    assert.match(page._isolationStatus.label, /通过/);
    assert.match(page._isolationStatus.label, /nat \/ mangle \/ filter/);

    page.render([state, '', '', {code: 1, text: 'unsafe:test_violation'}]);
    assert.equal(page._uiSummary.isolationSafe, false);
    assert.equal(page._uiSummary.canEnableEnforcement, false);
    assert.match(page._isolationStatus.label, /异常/);
    assert.match(page._isolationStatus.label, /unsafe:test_violation/);
    page.render([state, '', '', {code: 2, text: 'unavailable:raw_table'}]);
    assert.match(page._isolationStatus.label, /无法验证/);
    assert.match(page._isolationStatus.label, /不等于已确认安全/);
    // Armed + safe is the only front-end state that permits formal control.
    state.armed = 1;
    page.render([state, '', '', {code: 0, text: 'ok'}]);
    assert.equal(page._uiSummary.canEnableEnforcement, true);
    state.armed = 0;
    // Restore normal render for the remaining interaction checks.
    page.render([state, '', '', {code: 0, text: 'ok'}]);
    assert.match(page._trafficNodes.outgoing.textContent, /8 PPS/);
    assert.match(page._trafficNodes.replyStatus.textContent, /未启用|暂不可用/);
    Object.assign(state, {
        reply_observer: 'ready',
        reply_sample_status: 'observed',
        reply_prerouting_pps: 15,
        reply_prerouting_bps: 20000,
        reply_local_pps: 5,
        reply_local_bps: 4000
    });
    assert.doesNotThrow(() => page.updateTrafficUI(state));
    assert.match(page._trafficNodes.replyStatus.textContent, /检测到回程流量/);
    assert.match(page._trafficNodes.prerouting.textContent, /15 PPS/);
    assert.match(page._trafficNodes.local.textContent, /5 PPS/);
    state.reply_observer = 'unavailable';
    page.updateTrafficUI(state);
    assert.match(page._trafficNodes.replyStatus.textContent, /暂不可用/);
    assert.equal(page._trafficNodes.local.textContent, '—');
    for (const phase of updates) {
        Object.assign(state, phase);
        assert.doesNotThrow(() => page.updateCalibrationUI(state), phase.calibration_phase);
        const n = page._calibrationNodes;
        const active = phase.calibration_phase === 'running' || phase.calibration_phase === 'finishing';
        assert.equal(n.start.disabled, active, phase.calibration_phase);
        assert.equal(n.stop.disabled, !active, phase.calibration_phase);
        assert.equal(n.selection.disabled, active);
        assert.equal(n.scene.disabled, active);
        assert.ok(n.title.textContent.length > 0);
    }
    assert.equal(page._calibrationNodes.title.textContent, '未在采样');

    Object.assign(state, updates[0]);
    await page.refreshCalibration();
    assert.equal(page._calibrationNodes.bar.value, 41);
    assert.match(page._calibrationNodes.detail.textContent, /剩余 70 秒/);
    Object.assign(state, updates[2]);
    await page.refreshCalibration();
    assert.equal(page._calibrationNodes.bar.value, 100);
    assert.equal(page._calibrationNodes.samples.textContent, 'sample line');
    assert.match(page._calibrationNodes.title.textContent, /完成/);

    // Clicking a button should dispatch the action and not throw during UI update.
    state = {...state, ...updates[0]};
    page.updateCalibrationUI(state);
    const stopped = page._calibrationNodes.stop;
    await stopped.props.click();
    assert.ok(commands.some(([n, args]) => n === '/usr/libexec/tvguardctl' && args.join(' ') === 'calibrate stop'));
    assert.equal(reloads, 1);
    console.log('PASS: LuCI hierarchy, safety summary, calibration phases, polling and button dispatch');
})().catch(err => { console.error(err); process.exitCode = 1; });
