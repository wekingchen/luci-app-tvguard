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
    used_seconds: 123, watch_seconds: 123, previous_day_date: '2026-11-07', previous_day_seconds: 600, quota_seconds: 7200, remaining_seconds: 7077,
    bonus_seconds: 0, bonus_undo_available: 0, bonus_limit_seconds: 7200,
    policy_reason: 'none', pps: 8, tcp_pps: 1, udp_pps: 7,
    bytes_per_second: 2900, traffic_class: 'low_traffic',
    shadow_label: 'unknown', adaptive_state: 'unready',
    adaptive_pause_hint: 'none', adaptive_pause_score: 0,
    adaptive_bp_p50: 0, adaptive_bp_p90: 0,
    calibration_phase: 'idle',
    calibration_label: 'none', calibration_app: 'none',
    calibration_duration_seconds: 0, calibration_last_duration_seconds: 0,
    calibration_last_session: 'none'
};
let commands = [];
let eventLog = [
    '1700000000|1|mode|切换为 parent',
    '1700000060|2|reward|+30 分钟',
    '1700000120|3|enforcement|enforce=0',
    '1700000180|4|calibration_start|手工标注 general/playing：120 秒',
    '1700000300|5|calibration_end|general/playing: 11 samples (completed)',
    '1700000360|6|reward_revoke|撤销奖励 #22',
    '1700000420|7|reward_revoke|-15 分钟'
].join('\n');
const mockFs = {
    exec: (name, args) => {
        commands.push([name, args]);
        if (args[0] === 'status') return Promise.resolve({code: 0, stdout: JSON.stringify(state)});
        if (args[0] === 'log') return Promise.resolve({code: 0, stdout: eventLog});
        if (args[0] === 'calibration') return Promise.resolve({code: 0, stdout: 'sample line'});
        if (args[0] === 'learning') return Promise.resolve({code: 0, stdout: '学习分析\n状态: 电视系统首页'});
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
     calibration_duration_seconds: 180, calibration_remaining_seconds: 130, calibration_elapsed_seconds: 50,
     calibration_percent: 27, calibration_samples: 5, calibration_active: 1},
    {calibration_phase: 'finishing', calibration_label: 'system_home', calibration_app: 'system',
     calibration_duration_seconds: 180, calibration_remaining_seconds: 0, calibration_elapsed_seconds: 180,
     calibration_percent: 100, calibration_samples: 18, calibration_active: 0},
    {calibration_phase: 'completed', calibration_label: 'none', calibration_app: 'none',
     calibration_last_app: 'system', calibration_last_label: 'system_home',
     calibration_last_samples: 18, calibration_last_duration_seconds: 180,
     calibration_last_session: '12345-1'},
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
    assert.equal(initial.length, 5);
    const root = page.render(initial);
    assert.equal(root.tag, 'div');
    assert.equal(root.props.class, 'tvg-root');
    assert.match(source, /tvg-summary-grid\{grid-template-columns:repeat\(4/);
    assert.match(source, /@media\(max-width:700px\)/);
    assert.match(source, /tvg-summary-grid\{grid-template-columns:repeat\(2,minmax\(0,1fr\)\)/);
    assert.match(source, /tvg-mode-row>\.btn:last-child\{grid-column:1\/-1/);
    assert.match(source, /background:rgba\(127,127,127,\.08\)/);
    assert.match(source, /metric\('儿童剩余'/);
    assert.match(source, /设置 → 每日观看日报 · Bark/);
    assert.doesNotMatch(source, /设置入口在“时间规则”/);
    assert.match(source, /tvg-state-note-good/);
    assert.doesNotMatch(source, /background:var\(--background-color-high,#fafafa\)/);
    assert.equal(polls.size, 1);
    assert.equal(page._calibrationNodes.start.disabled, false);
    assert.equal(page._calibrationNodes.stop.disabled, true);
    assert.equal(page._calibrationNodes.start.props.type, 'button');
    assert.equal(page._calibrationNodes.stop.props.type, 'button');
    assert.equal(page._calibrationNodes.duration.props['aria-label'], '学习采集时长');
    assert.equal(page._calibrationNodes.sceneButtons.length, 4);
    assert.equal(page._calibrationNodes.selectedScene.children[0], '电视系统首页');
    assert.match(String(page._calibrationNodes.report.children[0] || ''), /学习分析/);
    assert.equal(page._overviewNodes.childButton.props.type, 'button');
    assert.equal(page._overviewNodes.parentButton.props.type, 'button');
    assert.equal(page._overviewNodes.lockButton.props.type, 'button');
    assert.equal(page._uiSummary.mode, '儿童模式');
    assert.equal(page._uiSummary.control, '观察模式');
    assert.equal(page._uiSummary.isolationSafe, true);
    assert.equal(page._uiSummary.canEnableEnforcement, false);
    assert.equal(page._eventSummary.length, 7);
    assert.equal(page._eventSummary[0].title, '撤销奖励');
    assert.equal(page._eventSummary[0].note, '已撤销 15 分钟奖励');
    assert.equal(page._eventSummary[1].title, '撤销奖励');
    assert.equal(page._eventSummary[1].note, '已撤销最近一笔奖励');
    assert.equal(page._eventSummary[2].title, '标注结束');
    assert.match(page._eventSummary[2].note, /通用采样/);
    assert.match(page._eventSummary[2].note, /正常播放/);
    assert.match(page._eventSummary[2].note, /11 条样本/);
    assert.equal(page._eventSummary[3].title, '开始标注');
    assert.match(page._eventSummary[3].note, /记录 120 秒/);
    assert.equal(page._eventSummary[4].title, '控制策略');
    assert.match(page._eventSummary[4].note, /观察模式/);
    assert.equal(page._eventSummary[6].title, '模式切换');
    assert.match(page._eventSummary[6].note, /家长模式/);
    assert.match(page._isolationStatus.label, /通过/);
    assert.match(page._isolationStatus.label, /nat \/ mangle \/ filter/);

    page.render([state, '', '', '暂无学习分析', {code: 1, text: 'unsafe:test_violation'}]);
    assert.equal(page._uiSummary.isolationSafe, false);
    assert.equal(page._uiSummary.canEnableEnforcement, false);
    assert.match(page._isolationStatus.label, /异常/);
    assert.match(page._isolationStatus.label, /unsafe:test_violation/);
    page.render([state, '', '', '暂无学习分析', {code: 2, text: 'unavailable:raw_table'}]);
    assert.match(page._isolationStatus.label, /无法验证/);
    assert.match(page._isolationStatus.label, /不等于已确认安全/);
    // Armed + safe is the only front-end state that permits formal control.
    state.armed = 1;
    page.render([state, '', '', '暂无学习分析', {code: 0, text: 'ok'}]);
    assert.equal(page._uiSummary.canEnableEnforcement, true);
    state.armed = 0;
    // Restore normal render for the remaining interaction checks.
    page.render([state, '', '', '暂无学习分析', {code: 0, text: 'ok'}]);

    // Main household-facing state must live-refresh, not only diagnostics.
    // New parent mode is persistent and has no countdown.
    Object.assign(state, {
        mode: 'parent',
        parent_until: 0,
        server_epoch: 1000,
        used_seconds: 3600,
        quota_seconds: 7200,
        remaining_seconds: 3600,
        bonus_seconds: 900,
        bonus_undo_available: 1,
        bonus_limit_seconds: 7200,
        policy_reason: 'none',
        shadow_label: 'playing',
        traffic_class: 'high_traffic',
        pps: 120,
        bytes_per_second: 2048
    });
    page.updateOverviewUI(state);
    assert.equal(page._uiSummary.mode, '家长模式');
    assert.equal(page._uiSummary.quotaPercent, 50);
    assert.match(page._overviewNodes.modeNote.textContent, /不计儿童额度/);
    assert.match(page._overviewNodes.parentNotice.textContent, /持续生效/);
    assert.equal(page._overviewNodes.parentNotice.style.display, '');
    assert.equal(page._overviewNodes.parentButton.disabled, true);
    assert.match(page._overviewNodes.parentButton.textContent, /当前/);
    assert.equal(page._overviewNodes.undoButton.disabled, false);
    assert.match(page._overviewNodes.rewardLimit.textContent, /15 \/ 120 分钟/);
    assert.equal(page._overviewNodes.rewardButtons[0].node.disabled, false);
    assert.match(page._overviewNodes.shadowValue.textContent, /疑似播放/);
    assert.match(page._overviewNodes.trafficNote.textContent, /2\.0 KB\/s/);

    // Phase 2A pause prototypes are visible but explicitly remain diagnostic.
    Object.assign(state, {
        adaptive_state: 'active',
        adaptive_pause_hint: 'high_ratio_pause',
        adaptive_pause_score: 95,
        adaptive_bp_p50: 1450,
        adaptive_bp_p90: 2400
    });
    page.updateOverviewUI(state);
    assert.match(page._overviewNodes.shadowValue.textContent, /自适应活跃/);
    assert.match(page._overviewNodes.shadowNote.textContent, /高 B\/P 行为/);
    assert.match(page._overviewNodes.shadowNote.textContent, /规则分 95/);
    assert.match(page._overviewNodes.shadowNote.textContent, /不代表暂停概率/);
    Object.assign(state, {
        adaptive_state: 'unready',
        adaptive_pause_hint: 'none',
        adaptive_pause_score: 0,
        adaptive_bp_p50: 0,
        adaptive_bp_p90: 0
    });

    // A legacy timed parent session remains visibly temporary until it expires,
    // and the parent button offers an explicit migration to the new semantics.
    Object.assign(state, {
        mode: 'parent',
        parent_until: 1600,
        server_epoch: 1000
    });
    page.updateOverviewUI(state);
    assert.match(page._overviewNodes.modeNote.textContent, /旧版定时家长模式/);
    assert.match(page._overviewNodes.modeNote.textContent, /10 分钟/);
    assert.equal(page._overviewNodes.parentButton.disabled, false);
    assert.equal(page._overviewNodes.parentButton.textContent, '切换为长期家长模式');

    Object.assign(state, {
        mode: 'child',
        parent_until: 0,
        server_epoch: 1000,
        used_seconds: 123,
        quota_seconds: 7200,
        remaining_seconds: 7077,
        bonus_seconds: 0,
        bonus_undo_available: 0,
        bonus_limit_seconds: 7200,
        policy_reason: 'none',
        shadow_label: 'unknown',
        traffic_class: 'low_traffic',
        pps: 8,
        bytes_per_second: 2900
    });
    page.updateOverviewUI(state);
    assert.equal(page._overviewNodes.parentNotice.style.display, 'none');
    assert.equal(page._overviewNodes.undoButton.disabled, true);

    // Near the daily reward cap, only additions that fit must remain clickable.
    Object.assign(state, {
        bonus_seconds: 6300,
        bonus_undo_available: 1,
        bonus_limit_seconds: 7200,
        policy_reason: 'quota',
        remaining_seconds: 0
    });
    page.updateOverviewUI(state);
    assert.match(page._overviewNodes.rewardLimit.textContent, /105 \/ 120 分钟/);
    assert.equal(page._overviewNodes.rewardButtons[0].node.disabled, false);
    assert.equal(page._overviewNodes.rewardButtons[1].node.disabled, true);
    assert.equal(page._overviewNodes.rewardButtons[2].node.disabled, true);
    assert.match(page._overviewNodes.modeNote.textContent, /额度已用完/);

    Object.assign(state, {
        bonus_seconds: 0,
        bonus_undo_available: 0,
        bonus_limit_seconds: 7200,
        policy_reason: 'window',
        remaining_seconds: 7077
    });
    page.updateOverviewUI(state);
    assert.match(page._overviewNodes.modeNote.textContent, /不在允许时段/);

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
        assert.equal(n.duration.disabled, active);
        n.sceneButtons.forEach(item => assert.equal(item.node.disabled, active));
        assert.ok(n.title.textContent.length > 0);
        if (phase.calibration_phase === 'running')
            assert.match(n.title.textContent, /电视系统|小米系统首页闲置/);
    }
    assert.equal(page._calibrationNodes.title.textContent, '准备学习');

    Object.assign(state, updates[0]);
    await page.refreshCalibration();
    assert.equal(page._calibrationNodes.bar.value, 27);
    assert.match(page._calibrationNodes.detail.textContent, /剩余 130 秒/);
    Object.assign(state, updates[2]);
    await page.refreshCalibration();
    assert.equal(page._calibrationNodes.bar.value, 100);
    assert.equal(page._calibrationNodes.samples.textContent, 'sample line');
    assert.match(page._calibrationNodes.report.textContent, /学习分析/);
    assert.match(page._calibrationNodes.title.textContent, /完成/);

    // Household buttons must dispatch the exact product semantics.
    const parentButton = page._overviewNodes.parentButton;
    await parentButton.props.click();
    const parentCalls = commands.filter(([n, args]) =>
        n === '/usr/libexec/tvguardctl' && args[0] === 'mode' && args[1] === 'parent');
    assert.equal(parentCalls.length, 1);
    assert.deepEqual(parentCalls[0][1], ['mode', 'parent']);

    const reward15 = page._overviewNodes.rewardButtons[0].node;
    await reward15.props.click();
    assert.ok(commands.some(([n, args]) =>
        n === '/usr/libexec/tvguardctl' && args.join(' ') === 'bonus 15'));

    // Learning start uses only one of four scene labels plus a duration.
    Object.assign(state, updates[5]);
    page.updateCalibrationUI(state);
    page._calibrationNodes.duration.value = '180';
    await page._calibrationNodes.start.props.click();
    assert.ok(commands.some(([n, args]) =>
        n === '/usr/libexec/tvguardctl' && args.join(' ') === 'calibrate system_home 180'));

    // Calibration stop remains an independent action.
    state = {...state, ...updates[0]};
    page.updateCalibrationUI(state);
    const stopped = page._calibrationNodes.stop;
    await stopped.props.click();
    assert.ok(commands.some(([n, args]) =>
        n === '/usr/libexec/tvguardctl' && args.join(' ') === 'calibrate stop'));
    assert.equal(reloads, 4);
    console.log('PASS: LuCI hierarchy, exact mode/reward commands, live state, four-state learning center and safety summary');
})().catch(err => { console.error(err); process.exitCode = 1; });
