'use strict';
'require view';
'require fs';
'require ui';
'require poll';

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, Number(value) || 0));
}

function minutes(seconds) {
    return Math.ceil(Math.max(0, Number(seconds) || 0) / 60);
}

function duration(seconds) {
    var value = Math.max(0, Number(seconds) || 0);
    if (value < 60)
        return value > 0 ? '不足 1 分钟' : '0 分钟';
    var m = Math.ceil(value / 60);
    if (m < 60)
        return m + ' 分钟';
    var h = Math.floor(m / 60);
    var rest = m % 60;
    return h + ' 小时' + (rest ? ' ' + rest + ' 分钟' : '');
}

function byteRate(value) {
    var n = Math.max(0, Number(value) || 0);
    if (n >= 1024 * 1024)
        return (n / 1024 / 1024).toFixed(1) + ' MB/s';
    if (n >= 1024)
        return (n / 1024).toFixed(1) + ' KB/s';
    return n + ' B/s';
}

function panel(title, subtitle, children, extraStyle) {
    var heading = [
        E('div', { 'class': 'tvg-panel-title' }, title)
    ];
    if (subtitle)
        heading.push(E('div', {
            'class': 'description tvg-panel-subtitle'
        }, subtitle));

    return E('section', {
        'class': 'tvg-panel',
        'style': extraStyle || ''
    }, [E('div', { 'class': 'tvg-panel-head' }, heading)].concat(children || []).filter(function(node) {
        return node != null;
    }));
}

function metric(label, value, note, emphasis) {
    var children = [
        E('div', { 'class': 'description tvg-metric-label' }, label),
        E('div', {
            'class': emphasis ? 'tvg-metric-value tvg-metric-value-primary' : 'tvg-metric-value'
        }, value)
    ];
    if (note)
        children.push(E('div', {
            'class': 'description tvg-metric-note'
        }, note));

    return E('div', { 'class': 'tvg-metric' }, children);
}
function badge(text, tone) {
    var palette = {
        good: 'border-color:#66bb6a',
        warn: 'border-color:#f9a825',
        bad: 'border-color:#ef5350',
        neutral: 'border-color:var(--border-color-medium,#bbb)'
    };
    return E('span', {
        'style': [
            'display:inline-flex',
            'align-items:center',
            'padding:4px 9px',
            'border:1px solid',
            'border-radius:999px',
            'color:inherit',
            'background:transparent',
            palette[tone] || palette.neutral
        ].join(';')
    }, text);
}

function detailBlock(summary, children, open) {
    var attrs = {
        'style': 'margin-top:12px;border-top:1px solid var(--border-color-medium,#ddd);padding-top:10px'
    };
    if (open)
        attrs.open = 'open';

    return E('details', attrs, [
        E('summary', {
            'style': 'cursor:pointer;font-weight:600;padding:4px 0;user-select:none'
        }, summary),
        E('div', { 'style': 'padding-top:10px' }, (children || []).filter(function(node) {
            return node != null;
        }))
    ]);
}

function grid(children, minWidth, extraClass) {
    return E('div', {
        'class': 'tvg-grid' + (extraClass ? ' ' + extraClass : ''),
        'style': '--tvg-min:' + (minWidth || 160) + 'px'
    }, children);
}

function buttonRow(children, extraClass) {
    return E('div', {
        'class': 'tvg-button-row' + (extraClass ? ' ' + extraClass : '')
    }, children);
}

function responsiveStyles() {
    return E('style', {}, [
        '.tvg-root{max-width:980px;margin:0 auto;padding:0 2px 20px;}',
        '.tvg-page-head{margin:0 0 14px;}',
        '.tvg-page-title{font-size:1.45rem;font-weight:700;line-height:1.25;margin:0 0 5px;}',
        '.tvg-panel{margin:0 0 14px;padding:15px;border:1px solid rgba(127,127,127,.42);border-radius:12px;background:transparent;box-shadow:none;}',
        '.tvg-panel-head{margin-bottom:12px;}',
        '.tvg-panel-title{font-size:1.12rem;font-weight:700;line-height:1.3;margin:0 0 4px;}',
        '.tvg-panel-subtitle{margin:0;line-height:1.55;}',
        '.tvg-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(var(--tvg-min),1fr));gap:10px;}',
        '.tvg-summary-grid{grid-template-columns:repeat(4,minmax(0,1fr));margin-bottom:14px;}',
        '.tvg-metric{min-width:0;padding:13px;border:1px solid rgba(127,127,127,.32);border-radius:10px;background:rgba(127,127,127,.08);}',
        '.tvg-metric-label{margin-bottom:5px;}',
        '.tvg-metric-value{font-size:1.13rem;font-weight:700;line-height:1.25;overflow-wrap:anywhere;}',
        '.tvg-metric-value-primary{font-size:1.55rem;}',
        '.tvg-metric-note{margin-top:6px;line-height:1.42;}',
        '.tvg-button-row{display:flex;flex-wrap:wrap;gap:8px;align-items:center;}',
        '.tvg-button-row>.btn{margin:0;min-height:36px;}',
        '.tvg-soft-box{padding:12px;border:1px solid rgba(127,127,127,.32);border-radius:9px;background:rgba(127,127,127,.08);}',
        '.tvg-state-note{padding:10px 12px;border:1px solid rgba(127,127,127,.4);border-radius:9px;background:rgba(127,127,127,.06);line-height:1.45;}',
        '.tvg-state-note-good{border-color:rgba(46,204,113,.72);}',
        '.tvg-advanced-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;}',
        '.tvg-learning-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:9px;margin:10px 0;}',
        '.tvg-learning-grid>.btn{min-height:48px;white-space:normal;font-weight:600;}',
        '.tvg-root details>summary{line-height:1.4;}',
        '@media(max-width:700px){',
        ' .tvg-root{padding:0 0 16px;}',
        ' .tvg-page-head{margin-bottom:10px;}',
        ' .tvg-page-title{font-size:1.28rem;}',
        ' .tvg-panel{padding:12px;margin-bottom:12px;border-radius:10px;}',
        ' .tvg-panel-head{margin-bottom:9px;}',
        ' .tvg-panel-title{font-size:1.05rem;}',
        ' .tvg-panel-subtitle{font-size:.9rem;line-height:1.48;}',
        ' .tvg-summary-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;margin-bottom:12px;}',
        ' .tvg-metric{padding:10px;min-height:88px;}',
        ' .tvg-metric-value{font-size:1.04rem;}',
        ' .tvg-metric-value-primary{font-size:1.38rem;}',
        ' .tvg-metric-note{font-size:.85rem;line-height:1.35;}',
        ' .tvg-button-row{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;}',
        ' .tvg-button-row>.btn{width:100%;min-width:0;white-space:normal;line-height:1.25;padding-left:8px;padding-right:8px;}',
        ' .tvg-mode-row>.btn:last-child{grid-column:1/-1;}',
        ' .tvg-calibration-row{grid-template-columns:1fr;}',
        ' .tvg-calibration-row select,.tvg-calibration-row>.btn{width:100%;min-width:0;}',
        ' .tvg-smart-grid{grid-template-columns:repeat(2,minmax(0,1fr));}',
        ' .tvg-advanced-grid{grid-template-columns:1fr;}',
        ' .tvg-learning-grid{grid-template-columns:1fr 1fr;}',
        ' .alert-message{padding:10px 12px!important;line-height:1.45!important;}',
        '}',
        '@media(max-width:360px){',
        ' .tvg-summary-grid,.tvg-smart-grid{grid-template-columns:1fr 1fr;}',
        ' .tvg-button-row{grid-template-columns:1fr 1fr;}',
        ' .tvg-metric{padding:9px;}',
        '}'
    ].join('\n'));
}

function trafficName(value) {
    return {
        no_packets: '无新数据',
        low_traffic: '低',
        medium_traffic: '中',
        high_traffic: '高',
        unknown: '未知'
    }[value] || '未知';
}

function shadowName(value) {
    return {
        playing: '疑似播放',
        idle: '已确认闲置',
        paused: '疑似暂停',
        app_home: '疑似应用首页',
        system_home: '疑似系统首页',
        sleep: '疑似待机',
        unknown: '暂时无法判断'
    }[value] || '暂时无法判断';
}

function adaptiveName(value) {
    return {
        idle: '自适应闲置',
        active: '自适应活跃',
        ambiguous: '自适应模糊',
        warming: '正在建立窗口',
        unready: '模型未就绪'
    }[value] || '自适应未知';
}

function pauseHintName(value) {
    return {
        high_ratio_pause: '高 B/P 重叠候选',
        bursty_pause: '突发型暂停重叠候选',
        idle_overlap: '低活跃暂停 / 首页重叠',
        none: '无暂停线索'
    }[value] || '无暂停线索';
}

function sceneName(value) {
    return {
        playing: '正常播放',
        paused: '视频暂停',
        app_home: '应用首页闲置',
        system_home: '小米系统首页闲置',
        sleep: '熄屏待机',
        none: '未选择'
    }[value] || '未知场景';
}

function appName(value) {
    return {
        general: '通用采样',
        tencent: '腾讯极光',
        iqiyi: '爱奇艺',
        mango: '芒果 TV',
        other: '其他视频应用',
        system: '电视系统',
        none: '未标注'
    }[value] || '未知标签';
}

function eventName(value) {
    return {
        mode: '模式切换',
        reward: '时间奖励',
        reward_revoke: '撤销奖励',
        calibration_start: '开始标注',
        calibration_end: '标注结束',
        daily_reset: '每日重置',
        parent_expired: '旧版定时家长模式结束',
        enforcement: '控制策略',
        recovery_lock: '恢复保护'
    }[value] || '系统记录';
}

function eventNote(type, note) {
    var value = String(note || '');
    if (type === 'mode') {
        if (value.indexOf('child') >= 0)
            return '已切换为儿童模式';
        if (value.indexOf('parent') >= 0)
            return '已切换为家长模式';
        if (value.indexOf('locked') >= 0)
            return '已切换为锁定模式';
    }
    if (type === 'enforcement') {
        if (value.indexOf('enforce=1') >= 0)
            return '已开启正式网络控制';
        if (value.indexOf('enforce=0') >= 0)
            return '已关闭正式网络控制，恢复观察模式';
    }
    if (type === 'reward_revoke') {
        var revoked = value.match(/^-([0-9]+) 分钟$/);
        if (revoked)
            return '已撤销 ' + revoked[1] + ' 分钟奖励';
        if (/^撤销奖励 #[0-9]+$/.test(value))
            return '已撤销最近一笔奖励';
    }
    if (type === 'calibration_start') {
        var started = value.match(/手工标注 ([^/]+)\/([^：]+)：120 秒/);
        if (started)
            return appName(started[1]) + ' · ' + sceneName(started[2]) + ' · 记录 120 秒';
        var systemStarted = value.match(/手工标注 ([^：]+)：120 秒/);
        if (systemStarted)
            return sceneName(systemStarted[1]) + ' · 记录 120 秒';
    }
    if (type === 'calibration_end') {
        var ended = value.match(/^([^/]+)\/([^:]+): ([0-9]+) samples \(([^)]+)\)$/);
        if (ended) {
            var reason = {
                completed: '已完成',
                stopped: '提前结束',
                interrupted: '被中断'
            }[ended[4]] || ended[4];
            return appName(ended[1]) + ' · ' + sceneName(ended[2]) +
                ' · ' + ended[3] + ' 条样本 · ' + reason;
        }
    }
    return value || '—';
}

function parseEvents(raw) {
    var rows = [];
    String(raw || '').split('\n').forEach(function(line) {
        if (!line)
            return;
        var parts = line.split('|');
        if (parts.length < 4)
            return;
        var epoch = Number(parts[0]) || 0;
        var type = parts[2];
        var note = parts.slice(3).join('|');
        rows.push({
            epoch: epoch,
            type: type,
            title: eventName(type),
            note: eventNote(type, note)
        });
    });
    return rows.slice(-12).reverse();
}

function renderEvents(rows) {
    if (!rows.length)
        return E('div', { 'class': 'description' }, '暂无操作记录');

    return E('div', {}, rows.map(function(row) {
        var time = row.epoch > 0 ?
            new Date(row.epoch * 1000).toLocaleString() : '时间未知';
        return E('div', {
            'style': 'display:grid;grid-template-columns:minmax(110px,auto) 1fr;' +
                'gap:10px;padding:9px 0;border-bottom:1px solid var(--border-color-medium,#ddd)'
        }, [
            E('div', { 'class': 'description', 'style': 'white-space:nowrap' }, time),
            E('div', {}, [
                E('strong', {}, row.title),
                E('div', { 'class': 'description', 'style': 'margin-top:3px;line-height:1.45' }, row.note)
            ])
        ]);
    }));
}

function childPolicyNote(state) {
    if (state.policy_reason === 'quota')
        return state.enforce ? '今日儿童额度已用完，正式控制会阻断联网' : '今日儿童额度已用完；观察模式下仍不会断网';
    if (state.policy_reason === 'window')
        return state.enforce ? '当前不在允许使用时段，正式控制会阻断联网' : '当前不在允许使用时段；观察模式下仍不会断网';
    if (state.billing_state === 'idle_verified')
        return '已连续确认闲置，儿童计时已暂停；一旦无法确认会立即恢复计时';
    if (state.billing_state === 'idle_grace')
        return '已确认闲置后出现短暂低活跃模糊帧，最多保持 20 秒不扣时；明确播放会立即恢复计时';
    if (state.billing_state === 'idle_silent')
        return '当前网络静默，儿童计时已暂停';
    return '当前未确认闲置，按儿童使用时间继续计时';
}

function childPolicySummary(state) {
    if (state.policy_reason === 'quota')
        return '儿童额度已用完';
    if (state.policy_reason === 'window')
        return '当前不在允许时段';
    if (state.billing_state === 'idle_verified')
        return state.idle_reason === 'adaptive' ? 'Adaptive 高置信闲置 · 已暂停计时' :
            (state.idle_reason === 'system_home' ? '系统首页 · 已暂停计时' :
            (state.idle_reason === 'nonplaying' ? '已确认非播放 · 已暂停计时' :
            (state.idle_reason === 'paused' ? '视频暂停 · 已暂停计时' :
            (state.idle_reason === 'app_home' ? 'App 首页 · 已暂停计时' : '已确认闲置 · 暂停计时'))));
    if (state.billing_state === 'idle_grace')
        return '短暂无法判断 · 保持暂停计时';
    if (state.billing_state === 'idle_silent')
        return '网络静默 · 暂停计时';
    return '按儿童额度和时段管理';
}

return view.extend({
    load: function() {
        return Promise.all([
            fs.exec('/usr/libexec/tvguard-status', ['status']).then(function(r) {
                if (r.code)
                    throw new Error(r.stderr || '读取状态失败');
                return JSON.parse(r.stdout);
            }),
            fs.exec('/usr/libexec/tvguard-status', ['log']).then(function(r) {
                return r.stdout || '';
            }),
            fs.exec('/usr/libexec/tvguard-status', ['calibration-v5']).then(function(r) {
                return r.stdout || '';
            }),
            fs.exec('/usr/libexec/tvguard-status', ['learning']).then(function(r) {
                return r.stdout || '暂无学习分析';
            }),
            fs.exec('/usr/libexec/tvguard-status', ['isolation']).then(function(r) {
                return {
                    code: Number(r.code || 0),
                    text: String(r.stdout || r.stderr || '').trim()
                };
            }).catch(function() {
                return { code: 2, text: 'unavailable:rpc' };
            })
        ]);
    },

    updateOverviewUI: function(state) {
        var n = this._overviewNodes;
        if (!n)
            return;

        var parentLeft = Math.max(0, Number(state.parent_until || 0) - Number(state.server_epoch || 0));
        var legacyTimedParent = state.mode === 'parent' && Number(state.parent_until || 0) > 0;
        var modeName = {
            child: '儿童模式',
            parent: '家长模式',
            locked: '已锁定'
        }[state.mode] || '未知模式';
        var modeNote = state.mode === 'parent' ?
            (legacyTimedParent ?
                '旧版定时家长模式 · 剩余 ' + duration(parentLeft) :
                '不计儿童额度 · 不受儿童时段限制') :
            (state.mode === 'locked' ?
                (state.enforce ? '正式控制下会断网' : '观察模式下不会断网') :
                childPolicySummary(state));
        var activityName = {
            active: '检测到联网活动',
            silent: '当前网络静默',
            unknown: '等待首次采样'
        }[state.activity] || '状态未知';
        var quota = Math.max(0, Number(state.quota_seconds) || 0);
        var used = Math.max(0, Number(state.used_seconds) || 0);
        var quotaPercent = quota > 0 ? clamp(used * 100 / quota, 0, 100) : 0;

        n.watchToday.textContent = duration(state.watch_seconds || 0);
        n.watchYesterday.textContent = state.previous_day_date && state.previous_day_date !== 'none' ?
            (state.previous_day_date + '：' + duration(state.previous_day_seconds || 0)) : '尚无完整自然日记录';
        n.remaining.textContent = duration(state.remaining_seconds);
        n.mode.textContent = modeName;
        n.modeNote.textContent = modeNote;
        n.activity.textContent = activityName;
        n.used.textContent = '已计时 ' + duration(state.used_seconds);
        n.quota.textContent = '总额度 ' + duration(state.quota_seconds);
        n.quotaProgress.value = quotaPercent;
        n.quotaProgress.setAttribute('aria-valuenow', String(Math.round(quotaPercent)));
        n.quotaRemaining.textContent = '剩余 ' + duration(state.remaining_seconds);
        n.quotaBonus.textContent = '今日奖励 +' + minutes(state.bonus_seconds) + ' 分钟';

        n.parentNotice.style.display = state.mode === 'parent' ? '' : 'none';
        n.parentNotice.textContent = state.mode === 'parent' ?
            (legacyTimedParent ?
                '旧版定时家长模式进行中 · 剩余 ' + duration(parentLeft) +
                    '；可点“切换为长期家长模式”改用新版语义' :
                '家长模式持续生效，直到手动切回儿童模式') : '';

        n.childButton.disabled = state.mode === 'child';
        n.childButton.textContent = state.mode === 'child' ? '儿童模式 · 当前' : '儿童模式';
        n.parentButton.disabled = state.mode === 'parent' && !legacyTimedParent;
        n.parentButton.textContent = legacyTimedParent ? '切换为长期家长模式' :
            (state.mode === 'parent' ? '家长模式 · 当前' : '家长模式');
        n.lockButton.disabled = state.mode === 'locked';
        n.lockButton.textContent = state.mode === 'locked' ? '已锁定 · 当前' : '立即锁定';

        n.undoButton.disabled = !Number(state.bonus_undo_available || 0);
        n.undoButton.title = n.undoButton.disabled ? '当前没有可撤销的最近一笔奖励' : '撤销最近一笔尚未撤销的奖励';

        var bonusSeconds = Math.max(0, Number(state.bonus_seconds) || 0);
        var bonusLimit = Math.max(0, Number(state.bonus_limit_seconds) || 0);
        n.rewardLimit.textContent = bonusLimit > 0 ?
            '今日已奖励 ' + minutes(bonusSeconds) + ' / ' + minutes(bonusLimit) + ' 分钟' :
            '今天的额外奖励上限为 0 分钟';
        n.rewardButtons.forEach(function(item) {
            var wouldExceed = bonusSeconds + item.minutes * 60 > bonusLimit;
            item.node.disabled = wouldExceed;
            item.node.title = wouldExceed ? '添加后会超过今天的最大奖励额度' : '';
        });

        n.shadowValue.textContent = state.adaptive_state &&
            state.adaptive_state !== 'unready' ?
            adaptiveName(state.adaptive_state) : shadowName(state.shadow_label);
        if (state.adaptive_pause_hint === 'high_ratio_pause')
            n.shadowNote.textContent = '实验重叠线索：高 B/P 行为 · 规则分 ' +
                String(state.adaptive_pause_score || 0) + '；B/P P50 ' +
                String(state.adaptive_bp_p50 || 0) +
                '。该特征已知可与低码率播放重叠，只做旁路观察，不代表暂停概率。';
        else if (state.adaptive_pause_hint === 'bursty_pause')
            n.shadowNote.textContent = '实验重叠线索：突发型行为；只做旁路观察，目前仍按模糊状态保守计时。';
        else if (state.adaptive_pause_hint === 'idle_overlap')
            n.shadowNote.textContent = '当前行为与低活跃暂停画像吻合，但和首页闲置重叠，不强行猜前台场景。';
        else if (state.billing_state === 'idle_verified')
            n.shadowNote.textContent = '滚动窗口已确认闲置约 ' +
                String(state.idle_streak_seconds || 0) + ' 秒；当前暂停儿童计时。';
        else if (state.billing_state === 'idle_grace')
            n.shadowNote.textContent = '当前窗口暂时模糊，但仍处于已确认闲置后的 ' +
                String(state.idle_grace_seconds || 0) + '/20 秒保持窗口。';
        else if (state.adaptive_state === 'active')
            n.shadowNote.textContent = '滚动窗口支持活跃/播放；继续计时。';
        else if (state.adaptive_state === 'ambiguous' || state.adaptive_state === 'warming')
            n.shadowNote.textContent = '自适应证据尚不足以确认闲置；按保守策略继续计时。';
        else if (state.shadow_label === 'unknown')
            n.shadowNote.textContent = '当前证据不足或样本重叠；按保守策略继续计时。';
        else
            n.shadowNote.textContent = '当前没有可靠闲置证据；继续计时。';
        n.trafficValue.textContent = trafficName(state.traffic_class);
        n.trafficNote.textContent = String(state.pps || 0) + ' PPS · ' +
            byteRate(state.bytes_per_second || 0);

        this._uiSummary.mode = modeName;
        this._uiSummary.quotaPercent = quotaPercent;
    },

    updateTrafficUI: function(state) {
        var n = this._trafficNodes;
        if (!n)
            return;

        n.outgoing.textContent = String(state.pps || 0) + ' PPS · ' +
            byteRate(state.bytes_per_second || 0);
        n.outgoingProtocol.textContent = 'TCP ' + String(state.tcp_pps || 0) +
            ' PPS · UDP ' + String(state.udp_pps || 0) + ' PPS';

        var observer = String(state.reply_observer || 'unavailable');
        if (observer === 'ready') {
            var status = {
                observed: '检测到回程流量',
                no_packets: '本次采样没有检测到回程包',
                warming_up: '正在建立采样基线'
            }[state.reply_sample_status] || '等待采样';

            n.replyStatus.textContent = status + ' · 路径完整性仍未验证';
            n.prerouting.textContent = String(state.reply_prerouting_pps || 0) +
                ' PPS · ' + byteRate(state.reply_prerouting_bps || 0);
            n.local.textContent = String(state.reply_local_pps || 0) +
                ' PPS · ' + byteRate(state.reply_local_bps || 0);
        }
        else {
            n.replyStatus.textContent = observer === 'disabled' ?
                '未启用（默认状态）' :
                '观测点暂不可用；不会把 0 流量当作熄屏';
            n.prerouting.textContent = '—';
            n.local.textContent = '—';
        }
    },

    updateCalibrationUI: function(state) {
        var n = this._calibrationNodes;
        if (!n)
            return;

        var phase = String(state.calibration_phase || 'idle');
        var active = phase === 'running' || phase === 'finishing';
        var configuredDuration = Math.max(1, Number(state.calibration_duration_seconds ||
            state.calibration_last_duration_seconds || n.duration.value || 180));
        var elapsed = clamp(state.calibration_elapsed_seconds, 0, configuredDuration);
        var remaining = Math.max(0, Number(state.calibration_remaining_seconds) || 0);
        var count = Math.max(0, Number(state.calibration_samples) || 0);
        var progress = clamp(state.calibration_percent, 0, 100);
        var agentFresh = state.agent_state === 'fresh';
        var contextQuality = String(state.agent_context_quality || 'unknown');
        var contextFull = agentFresh && contextQuality === 'full';
        this._lastCalibrationState = state;

        n.agentStatus.textContent = agentFresh ?
            ('电视 Agent 已连接 · ' + String(state.agent_age_seconds || 0) + ' 秒前上报 · ' +
                (contextQuality === 'full' ? '前台识别完整' :
                    (contextQuality === 'package_only' ? '仅识别到应用' : '前台上下文未确认'))) :
            (state.agent_state === 'stale' ? '电视 Agent 上报已过期' :
                (state.agent_state === 'invalid' ? '电视 Agent 上报异常' : '电视 Agent 暂无上报'));
        n.agentContext.textContent = agentFresh ?
            '当前应用：' + String(state.agent_package || 'unknown') +
                ' · 页面：' + String(state.agent_activity || 'unknown') +
                ' · 音频：' + (Number(state.agent_audio_active || 0) ? '活跃' : '无') +
                ' · 屏幕：' + (Number(state.agent_screen_on || 0) ? '亮' : '灭') +
                ' · 权限判断：' + String(state.agent_usage_access || 'legacy') +
                ' · 来源：' + String(state.agent_foreground_source || 'legacy') +
                ' · 诊断：' + String(state.agent_foreground_status || 'legacy') :
            '本次仍可学习网络特征，但不会伪装成 Agent 联合高可信样本。';

        n.bar.value = active ? progress : (phase === 'completed' ? 100 : 0);
        n.bar.setAttribute('aria-valuenow', String(n.bar.value));
        n.start.disabled = active;
        n.stop.disabled = !active;
        n.duration.disabled = active;
        n.sceneButtons.forEach(function(item) {
            item.node.disabled = active;
        });
        n.bar.style.display = active || phase === 'completed' ? '' : 'none';

        if (phase === 'running') {
            n.title.textContent = '正在学习 · ' + sceneName(state.calibration_label);
            n.detail.textContent = '已进行 ' + elapsed + ' / ' + configuredDuration +
                ' 秒 · 剩余 ' + remaining + ' 秒 · 已保存 ' + count + ' 条有效窗口';
            n.hint.textContent = contextFull ?
                '保持电视当前状态不变即可；网络窗口会和完整 App / Activity / 音频 / 屏幕上下文同步保存。' :
                '保持电视当前状态不变即可；当前 Agent 上下文不完整，网络样本照常保存，但不会标成联合高可信。';
        }
        else if (phase === 'finishing') {
            n.title.textContent = '采集完成，正在自动分析…';
            n.detail.textContent = '已保存 ' + count + ' 条有效窗口，后台正在生成统计画像。';
            n.hint.textContent = '无需再次点击，分析完成后这里会自动刷新。';
        }
        else if (phase === 'completed' || phase === 'stopped' || phase === 'interrupted') {
            n.title.textContent = phase === 'completed' ? '本次学习已完成' :
                (phase === 'stopped' ? '本次学习已提前结束' : '本次学习被中断');
            n.detail.textContent = '状态：' + sceneName(state.calibration_last_label) +
                ' · 计划 ' + String(state.calibration_last_duration_seconds || 0) +
                ' 秒 · 保存 ' + String(state.calibration_last_samples || 0) + ' 条有效窗口';
            n.hint.textContent = '程序已自动分析并保存会话。高质量人工样本将作为 Adaptive Engine 的可信训练资料。';
        }
        else {
            n.title.textContent = '准备学习';
            n.detail.textContent = '先选择电视当前真实状态，再选择采集时长。推荐 3 分钟；App 和页面由电视 Agent 自动识别。';
            n.hint.textContent = contextFull ?
                'Agent 前台上下文完整。本次会同步保存网络与电视端证据；人工选择的状态仍是唯一真值。' :
                (agentFresh ?
                    'Agent 传输在线，但前台上下文尚不完整。本次可以学习网络特征，不会冒充高可信联合样本。' :
                    'Agent 当前不可用也可以开始，但本次只会作为兼容网络学习样本。');
        }
    },

    refreshCalibration: function() {
        return fs.exec('/usr/libexec/tvguard-status', ['status']).then(L.bind(function(r) {
            if (r.code)
                throw new Error(r.stderr || '后台状态读取失败');

            var state = JSON.parse(r.stdout);
            this.updateOverviewUI(state);
            this.updateCalibrationUI(state);
            this.updateTrafficUI(state);

            var n = this._calibrationNodes;
            var session = state.calibration_last_session || 'none';
            if (n && session !== 'none' && n.lastSession !== session) {
                n.lastSession = session;
                return Promise.all([
                    fs.exec('/usr/libexec/tvguard-status', ['calibration-v5']),
                    fs.exec('/usr/libexec/tvguard-status', ['learning'])
                ]).then(function(results) {
                    if (!results[0].code)
                        n.samples.textContent = (results[0].stdout || '').split('\n').slice(-12).join('\n') ||
                            '暂无原始样本';
                    if (!results[1].code)
                        n.report.textContent = results[1].stdout || '暂无学习分析';
                });
            }
        }, this)).catch(L.bind(function() {
            if (this._calibrationNodes)
                this._calibrationNodes.hint.textContent =
                    '实时更新暂时失败；已有学习数据不会丢失，可稍后刷新页面。';
        }, this));
    },

    handleAction: function(args, warning, ev) {
        if (warning && !window.confirm(warning))
            return Promise.resolve();

        var button = ev && ev.currentTarget ? ev.currentTarget : null;
        if (button)
            button.disabled = true;

        return fs.exec('/usr/libexec/tvguardctl', args).then(function(r) {
            if (r.code)
                throw new Error(r.stderr || r.stdout || '操作失败');
            window.location.reload();
        }).catch(function(err) {
            if (button)
                button.disabled = false;
            ui.addNotification(null, E('p', {}, String(err)), 'error');
        });
    },

    actionButton: function(label, args, options) {
        options = options || {};
        var cls = options.danger ? 'btn cbi-button-negative' :
            (options.primary ? 'btn cbi-button-positive' : 'btn cbi-button-action');
        var attrs = {
            'type': 'button',
            'class': cls,
            'style': 'min-height:36px;margin:0',
            'click': ui.createHandlerFn(this, 'handleAction', args, options.confirm || null)
        };
        if (options.disabled)
            attrs.disabled = 'disabled';
        if (options.title)
            attrs.title = options.title;

        return E('button', attrs, label);
    },

    render: function(result) {
        var s = result[0], events = result[1], samples = result[2];
        var learning = result[3] || '暂无学习分析';
        var isolation = result[4] || { code: 2, text: 'unavailable' };
        var isolationText = String(isolation.text || 'unknown');
        var isolationSafe = isolation.code === 0 && isolationText === 'ok';
        var isolationTone = isolationSafe ? 'good' :
            (isolationText.indexOf('unsafe:') === 0 ? 'bad' : 'warn');
        var isolationShort = isolationSafe ? '代理隔离通过' :
            (isolationTone === 'bad' ? '代理隔离异常' : '代理隔离未验证');

        var modeName = {
            child: '儿童模式',
            parent: '家长模式',
            locked: '已锁定'
        }[s.mode] || '未知模式';

        var parentLeft = Math.max(0, Number(s.parent_until || 0) - Number(s.server_epoch || 0));
        var legacyTimedParent = s.mode === 'parent' && Number(s.parent_until || 0) > 0;
        var modeNote = s.mode === 'parent' ?
            (legacyTimedParent ?
                '旧版定时家长模式 · 剩余 ' + duration(parentLeft) :
                '不计儿童额度 · 不受儿童时段限制') :
            (s.mode === 'locked' ?
                (s.enforce ? '正式控制下会断网' : '观察模式下不会断网') :
                childPolicySummary(s));

        var controlName = s.enforce ? '正式控制' : '观察模式';
        var controlNote = s.enforce ?
            '满足规则时会实际控制电视联网' :
            '不会因为额度、锁定或时段主动断网';

        var activityName = {
            active: '检测到联网活动',
            silent: '当前网络静默',
            unknown: '等待首次采样'
        }[s.activity] || '状态未知';

        var quota = Math.max(0, Number(s.quota_seconds) || 0);
        var used = Math.max(0, Number(s.used_seconds) || 0);
        var quotaPercent = quota > 0 ? clamp(used * 100 / quota, 0, 100) : 0;

        var statusBanner;
        if (!isolationSafe) {
            statusBanner = E('div', {
                'class': isolationTone === 'bad' ? 'alert-message error' : 'alert-message warning',
                'style': 'margin:0 0 16px;line-height:1.55'
            }, isolationTone === 'bad' ?
                '代理隔离检查发现异常。当前不要开启正式控制或实验回程观测。' :
                '代理隔离状态暂时无法完整验证。未知状态不会被当作安全状态。');
        }
        else if (s.enforce) {
            statusBanner = E('div', {
                'class': 'alert-message warning',
                'style': 'margin:0 0 16px;line-height:1.55'
            }, '正式网络控制已开启。TV Guard 可能按额度、时段或锁定状态阻断这台电视经过 N1 的 IPv4 流量。');
        }
        else {
            statusBanner = E('div', {
                'class': 'tvg-state-note tvg-state-note-good',
                'style': 'margin:0 0 14px'
            }, '当前为观察模式：可以计时、切换模式和记录奖励，但不会主动断开电视网络。');
        }

        var selectedScene = 'system_home';
        var selectedSceneName = '电视系统首页';
        var selectedSceneNode = E('strong', {}, selectedSceneName);
        var sceneButtons = [];

        function chooseScene(value, name) {
            selectedScene = value;
            selectedSceneName = name;
            selectedSceneNode.textContent = name;
            sceneButtons.forEach(function(item) {
                item.node.setAttribute('aria-pressed', item.value === value ? 'true' : 'false');
            });
        }

        function learningSceneButton(value, name) {
            var node = E('button', {
                'type': 'button',
                'class': 'btn cbi-button-neutral tvg-learning-choice',
                'aria-pressed': value === selectedScene ? 'true' : 'false',
                'click': function(ev) {
                    if (ev)
                        ev.preventDefault();
                    chooseScene(value, name);
                }
            }, name);
            sceneButtons.push({ value: value, name: name, node: node });
            return node;
        }

        var systemHomeButton = learningSceneButton('system_home', '电视系统首页');
        var appHomeButton = learningSceneButton('app_home', '视频 App 首页');
        var playingButton = learningSceneButton('playing', '视频正常播放');
        var pausedButton = learningSceneButton('paused', '视频暂停');

        var durationSelect = E('select', {
            'class': 'cbi-input-select',
            'aria-label': '学习采集时长',
            'style': 'min-width:150px'
        }, [
            E('option', { 'value': '60' }, '1 分钟'),
            E('option', { 'value': '180', 'selected': 'selected' }, '3 分钟（推荐）'),
            E('option', { 'value': '300' }, '5 分钟')
        ]);
        durationSelect.value = '180';

        var startCalibration = E('button', {
            'type': 'button',
            'class': 'btn cbi-button-action',
            'style': 'min-height:40px',
            'click': ui.createHandlerFn(this, function(ev) {
                var seconds = durationSelect.value || '180';
                var minutes = Math.round(Number(seconds) / 60);
                var live = this._lastCalibrationState || s;
                var liveQuality = String(live.agent_context_quality || 'unknown');
                var agentNote = live.agent_state === 'fresh' ?
                    ('电视 Agent 当前识别：' + String(live.agent_package || 'unknown') +
                        ' / ' + String(live.agent_activity || 'unknown') +
                        '（' + (liveQuality === 'full' ? '完整前台上下文' :
                            (liveQuality === 'package_only' ? '仅应用包' : '上下文未确认')) + '）。' +
                        (liveQuality === 'full' ? '' :
                            ' 本次不会标成联合高可信。')) :
                    '电视 Agent 当前不可用，本次会保留网络学习样本，但不会标成联合高可信。';
                return this.handleAction(
                    ['calibrate', selectedScene, seconds],
                    '请确认电视当前确实处于“' + selectedSceneName + '”。' + agentNote +
                        ' 接下来会自动采集约 ' + minutes +
                        ' 分钟，到时自动结束并分析；采集期间请不要操作遥控器。',
                    ev
                );
            })
        }, '开始学习');

        var stopCalibration = this.actionButton('提前结束', ['calibrate', 'stop'], {
            title: '停止后已有样本仍会保存并生成分析结果'
        });
        var calTitle = E('strong', {}, '未在学习');
        var calDetail = E('div', { 'style': 'margin:7px 0' }, '');
        var calProgress = E('progress', {
            'max': '100',
            'value': '0',
            'style': 'width:100%;height:16px;display:none',
            'role': 'progressbar',
            'aria-valuemin': '0',
            'aria-valuemax': '100',
            'aria-valuenow': '0'
        });
        var calHint = E('p', {
            'class': 'description',
            'style': 'margin:7px 0 0;line-height:1.5'
        }, '');
        var agentStatusNode = E('strong', {}, '读取电视 Agent…');
        var agentContextNode = E('div', {
            'class': 'description',
            'style': 'margin-top:5px;line-height:1.5;word-break:break-word'
        }, '正在读取当前应用与页面');
        var learningReport = E('pre', {
            'style': [
                'max-height:260px',
                'overflow:auto',
                'white-space:pre-wrap',
                'word-break:break-word',
                'font-size:.88rem',
                'line-height:1.55',
                'padding:11px',
                'border-radius:8px',
                'background:rgba(127,127,127,.08)'
            ].join(';')
        }, learning || '暂无学习分析');
        var samplePreview = E('pre', {
            'style': [
                'max-height:150px',
                'overflow:auto',
                'white-space:pre-wrap',
                'word-break:break-word',
                'font-size:.82rem',
                'padding:10px',
                'border-radius:8px',
                'background:rgba(127,127,127,.08)'
            ].join(';')
        }, (samples || '').split('\n').slice(-12).join('\n') || '暂无原始样本');

        this._calibrationNodes = {
            title: calTitle,
            detail: calDetail,
            bar: calProgress,
            hint: calHint,
            start: startCalibration,
            stop: stopCalibration,
            duration: durationSelect,
            sceneButtons: sceneButtons,
            selectedScene: selectedSceneNode,
            report: learningReport,
            samples: samplePreview,
            agentStatus: agentStatusNode,
            agentContext: agentContextNode,
            lastSession: s.calibration_last_session || 'none'
        };

        var trafficNodes = {
            outgoing: E('span', {}, '读取中…'),
            outgoingProtocol: E('span', {}, '读取中…'),
            replyStatus: E('span', {}, '读取中…'),
            prerouting: E('span', {}, '—'),
            local: E('span', {}, '—')
        };
        this._trafficNodes = trafficNodes;

        var childModeButton = this.actionButton(
            s.mode === 'child' ? '儿童模式 · 当前' : '儿童模式',
            ['mode', 'child'], { disabled: s.mode === 'child', primary: s.mode === 'child' }
        );
        var parentModeButton = this.actionButton(
            legacyTimedParent ? '切换为长期家长模式' :
                (s.mode === 'parent' ? '家长模式 · 当前' : '家长模式'),
            ['mode', 'parent'], {
                disabled: s.mode === 'parent' && !legacyTimedParent,
                primary: s.mode === 'parent' && !legacyTimedParent,
                title: '家长模式不消耗儿童额度，也不受儿童可用时段限制'
            }
        );
        var lockModeButton = this.actionButton(
            s.mode === 'locked' ? '已锁定 · 当前' : '立即锁定',
            ['mode', 'locked'], {
                danger: true,
                disabled: s.mode === 'locked',
                confirm: '确认切换为锁定模式？' +
                    (s.enforce ? '正式控制已开启，电视联网可能立即被阻断。' :
                        '当前仍是观察模式，因此只记录锁定状态，不会断网。')
            }
        );
        var modeButtons = [
            childModeButton,
            parentModeButton,
            lockModeButton
        ];

        var canEnable = !!s.armed && isolationSafe;
        var enforcementAction;
        if (s.enforce) {
            enforcementAction = this.actionButton('关闭正式控制，回到观察模式', ['enforce', 'off'], {
                primary: true,
                confirm: '确认关闭 TV Guard 的实际网络控制？关闭后额度和锁定仍会继续记录，但不会主动断网。'
            });
        }
        else if (canEnable) {
            enforcementAction = this.actionButton('开启正式网络控制', ['enforce', 'on'], {
                danger: true,
                confirm: '这会让 TV Guard 开始实际控制这台电视经过 N1 的 IPv4 流量。请确认已经完成 N1 实机兼容验收并准备好恢复方案。'
            });
        }
        else {
            enforcementAction = this.actionButton('正式控制暂不可开启', ['enforce', 'on'], {
                disabled: true,
                title: !s.armed ? '尚未完成管理员解锁' : '代理隔离审计未通过'
            });
        }

        var watchTodayNode = E('strong', { 'style': 'font-size:1.35rem' }, duration(s.watch_seconds || 0));
        var watchYesterdayNode = E('span', { 'class': 'description' },
            s.previous_day_date && s.previous_day_date !== 'none' ?
                (s.previous_day_date + '：' + duration(s.previous_day_seconds || 0)) : '尚无完整自然日记录');
        var remainingNode = E('span', {}, duration(s.remaining_seconds));
        var modeNode = E('span', {}, modeName);
        var modeNoteNode = E('span', {}, modeNote);
        var activityNode = E('span', {}, activityName);
        var usedNode = E('strong', {}, '已计时 ' + duration(s.used_seconds));
        var quotaNode = E('span', {}, '总额度 ' + duration(s.quota_seconds));
        var quotaProgressNode = E('progress', {
            'max': '100',
            'value': String(quotaPercent),
            'style': 'width:100%;height:18px',
            'aria-label': '今日额度使用进度',
            'aria-valuenow': String(Math.round(quotaPercent))
        });
        var quotaRemainingNode = E('span', { 'class': 'description' },
            '剩余 ' + duration(s.remaining_seconds));
        var quotaBonusNode = E('span', { 'class': 'description' },
            '今日奖励 +' + minutes(s.bonus_seconds) + ' 分钟');
        var parentNoticeNode = E('div', {
            'class': 'tvg-state-note tvg-state-note-good',
            'style': 'margin:10px 0 0;' + (s.mode === 'parent' ? '' : 'display:none')
        }, s.mode === 'parent' ?
            (legacyTimedParent ?
                '旧版定时家长模式进行中 · 剩余 ' + duration(parentLeft) +
                    '；可切换为新版长期家长模式' :
                '家长模式持续生效，直到手动切回儿童模式') : '');
        var reward15Button = this.actionButton('+15 分钟', ['bonus', '15']);
        var reward30Button = this.actionButton('+30 分钟', ['bonus', '30']);
        var reward60Button = this.actionButton('+60 分钟', ['bonus', '60']);
        var undoButton = this.actionButton('撤销上次奖励', ['bonus', 'undo'], {
            disabled: !Number(s.bonus_undo_available || 0),
            title: Number(s.bonus_undo_available || 0) ?
                '撤销最近一笔尚未撤销的奖励' : '当前没有可撤销的最近一笔奖励'
        });
        var rewardLimitNode = E('div', {
            'class': 'description',
            'style': 'margin-top:10px;line-height:1.45'
        }, '');
        var shadowValueNode = E('span', {},
            s.adaptive_state && s.adaptive_state !== 'unready' ?
                adaptiveName(s.adaptive_state) : shadowName(s.shadow_label));
        var shadowNoteNode = E('span', {}, s.adaptive_pause_hint &&
            s.adaptive_pause_hint !== 'none' ?
            ('实验重叠线索：' + pauseHintName(s.adaptive_pause_hint) +
                ' · 规则分仅表示原型持续满足，不是暂停概率，也不会因此自动免计时。') :
            (s.adaptive_state === 'idle' ?
                '滚动窗口已确认闲置。' :
                (s.shadow_label === 'unknown' ?
                    '当前证据不足或样本重叠，不做精确场景推断。' :
                    '当前候选仅用于辅助诊断。')));
        var trafficValueNode = E('span', {}, trafficName(s.traffic_class));
        var trafficNoteNode = E('span', {}, String(s.pps || 0) + ' PPS · ' +
            byteRate(s.bytes_per_second || 0));

        this._overviewNodes = {
            watchToday: watchTodayNode,
            watchYesterday: watchYesterdayNode,
            remaining: remainingNode,
            mode: modeNode,
            modeNote: modeNoteNode,
            activity: activityNode,
            used: usedNode,
            quota: quotaNode,
            quotaProgress: quotaProgressNode,
            quotaRemaining: quotaRemainingNode,
            quotaBonus: quotaBonusNode,
            parentNotice: parentNoticeNode,
            childButton: childModeButton,
            parentButton: parentModeButton,
            lockButton: lockModeButton,
            undoButton: undoButton,
            rewardLimit: rewardLimitNode,
            rewardButtons: [
                { node: reward15Button, minutes: 15 },
                { node: reward30Button, minutes: 30 },
                { node: reward60Button, minutes: 60 }
            ],
            shadowValue: shadowValueNode,
            shadowNote: shadowNoteNode,
            trafficValue: trafficValueNode,
            trafficNote: trafficNoteNode
        };

        var parsedEvents = parseEvents(events);
        this._eventSummary = parsedEvents;

        var page = [
            responsiveStyles(),
            E('div', { 'class': 'tvg-page-head' }, [
                E('div', { 'class': 'tvg-page-title' }, 'TV Guard · 电视时间管理'),
                E('div', {
                    'class': 'description',
                    'style': 'font-size:.92rem;line-height:1.48'
                }, '日常管理放在前面；网络诊断和算法实验收在页面下方，需要时再展开。')
            ]),
            statusBanner,

            grid([
                metric('儿童剩余', remainingNode, '今日儿童额度', true),
                metric('当前模式', modeNode, modeNoteNode, false),
                metric('控制状态', controlName, controlNote, false),
                E('div', {
                    'class': 'tvg-metric'
                }, [
                    E('div', { 'class': 'description', 'style': 'margin-bottom:7px' }, '网络安全'),
                    badge(isolationShort, isolationTone),
                    E('div', {
                        'class': 'description',
                        'style': 'margin-top:7px;line-height:1.45'
                    }, activityNode)
                ])
            ], 180, 'tvg-summary-grid'),

            panel('今日儿童模式累计观看', '只统计儿童模式；观察模式下即使超出额度也会继续累计。家长模式不计入。统计来自现有联网计时规则，不等于准确的视频播放时长。', [
                E('div', { 'style': 'margin-bottom:6px' }, watchTodayNode),
                E('div', { 'class': 'description' }, ['上一完整自然日：', watchYesterdayNode]),
                E('div', { 'class': 'description', 'style': 'margin-top:8px' },
                    '每天定时发送上一完整自然日的 Bark 日报，可在“设置 → 每日观看日报 · Bark”中配置。')
            ], 'margin-top:16px'),

            panel('今日儿童额度', '这里显示的是根据经过 N1 的联网活动估算的使用时长，不等同于真实亮屏或观看时间。', [
                E('div', {
                    'style': 'display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-bottom:7px'
                }, [
                    usedNode,
                    quotaNode
                ]),
                quotaProgressNode,
                E('div', {
                    'style': 'display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;margin-top:7px'
                }, [
                    quotaRemainingNode,
                    quotaBonusNode
                ])
            ], 'margin-top:16px'),

            panel('观看模式', '儿童模式按额度和时段；家长模式不计儿童额度，持续到手动切回；锁定是否真正断网取决于正式控制是否开启。', [
                buttonRow(modeButtons, 'tvg-mode-row'),
                parentNoticeNode
            ]),

            panel('儿童奖励时间', '孩子临时多看一会儿就加奖励时间。奖励只增加今天的儿童额度，不改变模式；如果点错，可以撤销最近一笔奖励。', [
                buttonRow([
                    reward15Button,
                    reward30Button,
                    reward60Button,
                    undoButton
                ], 'tvg-reward-row'),
                rewardLimitNode
            ]),

            panel('智能识别学习', 'Adaptive Engine 会继续学习连续行为画像。普通暂停线索不改变计时；只有已学习媒体上下文中连续新鲜证据明确确认的暂停才免计时。', [
                grid([
                    metric('当前自动判断', shadowValueNode, shadowNoteNode, false),
                    metric('网络活动强度', trafficValueNode, trafficNoteNode, false)
                ], 220, 'tvg-smart-grid'),
                E('div', { 'class': 'tvg-soft-box', 'style': 'margin-top:10px' }, [
                    E('div', { 'style': 'margin-bottom:10px;padding-bottom:10px;border-bottom:1px solid rgba(127,127,127,.28)' }, [
                        agentStatusNode,
                        agentContextNode
                    ]),
                    E('strong', {}, '1. 选择电视当前状态'),
                    E('div', { 'class': 'tvg-learning-grid' }, [
                        systemHomeButton, appHomeButton, playingButton, pausedButton
                    ]),
                    E('div', {
                        'style': 'display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:10px 0'
                    }, [
                        E('span', { 'class': 'description' }, '当前选择：'),
                        selectedSceneNode,
                        E('span', { 'class': 'description', 'style': 'margin-left:auto' }, '采集时长'),
                        durationSelect
                    ]),
                    E('div', { 'class': 'tvg-button-row' }, [startCalibration, stopCalibration])
                ]),
                E('div', {
                    'class': 'tvg-soft-box',
                    'style': 'margin-top:10px'
                }, [calTitle, calDetail, calProgress, calHint]),
                detailBlock('最近一次自动分析', [learningReport], true),
                detailBlock('高级 · 最近 Agent 联合原始样本', [samplePreview], false)
            ]),

            panel('正式控制', '这是高风险区域。只有管理员已解锁，而且代理隔离审计通过时，才允许开启实际网络控制。', [
                E('div', {
                    'style': 'display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:10px'
                }, [
                    badge(controlName, s.enforce ? 'warn' : 'good'),
                    badge(isolationShort, isolationTone),
                    badge(s.armed ? '管理员已解锁' : '管理员未解锁', s.armed ? 'warn' : 'neutral')
                ]),
                E('p', {
                    'class': 'description',
                    'style': 'line-height:1.55'
                }, s.enforce ?
                    '正式控制已开启。仍只覆盖实际经过 N1 的电视 IPv4 流量。' :
                    (!s.armed ?
                        '开发候选默认不提供页面内解锁入口，避免误触。完成实机验收后才应由管理员显式授权。' :
                        (isolationSafe ?
                            '隔离审计已通过，但在完成实机代理兼容验收前仍不建议开启。' :
                            '隔离审计未通过或无法验证，因此前端和后端都会拒绝开启。'))),
                enforcementAction
            ]),

            detailBlock('高级网络诊断', [
                E('div', { 'class': 'tvg-advanced-grid' }, [
                    E('div', {
                        'class': 'tvg-soft-box'
                    }, [
                        E('strong', {}, '电视向 N1 发包'),
                        E('div', { 'style': 'margin-top:6px' }, trafficNodes.outgoing),
                        E('div', { 'class': 'description', 'style': 'margin-top:4px' }, trafficNodes.outgoingProtocol)
                    ]),
                    E('div', {
                        'class': 'tvg-soft-box'
                    }, [
                        E('strong', {}, '实验回程观测'),
                        E('div', { 'style': 'margin-top:6px' }, trafficNodes.replyStatus),
                        E('div', { 'class': 'description', 'style': 'margin-top:4px' }, [
                            'PREROUTING：', trafficNodes.prerouting, E('br'), '本地 OUTPUT：', trafficNodes.local
                        ])
                    ])
                ]),
                E('div', {
                    'class': isolationTone === 'bad' ? 'alert-message error' :
                        (isolationSafe ? 'alert-message success' : 'alert-message warning'),
                    'style': 'margin:10px 0 0;line-height:1.55'
                }, isolationSafe ?
                    '代理隔离审计通过：TV Guard 未发现进入 nat / mangle / filter 的自身规则。' :
                    '代理隔离审计：' + isolationText + '。未知或异常都不会被当作安全。'),
                E('p', {
                    'class': 'description',
                    'style': 'line-height:1.55'
                }, '回程观测默认关闭，只用于实验计数；即使有数据，也不能证明电视所有流量都经过 N1。')
            ], false),

            detailBlock('最近操作记录', [
                renderEvents(parsedEvents),
                detailBlock('查看原始记录', [
                    E('pre', {
                        'style': [
                            'max-height:180px',
                            'overflow:auto',
                            'white-space:pre-wrap',
                            'word-break:break-word',
                            'font-size:.82rem',
                            'padding:10px',
                            'border-radius:8px',
                            'background:rgba(127,127,127,.08)'
                        ].join(';')
                    }, events || '暂无原始记录')
                ], false)
            ], false)
        ];

        this._uiSummary = {
            mode: modeName,
            control: controlName,
            isolation: isolationShort,
            isolationSafe: isolationSafe,
            quotaPercent: quotaPercent,
            canEnableEnforcement: canEnable
        };

        this._isolationStatus = {
            label: isolationSafe ?
                '通过：TV Guard 规则仅位于允许的 raw 隔离范围，未发现进入 nat / mangle / filter。' :
                (isolationTone === 'bad' ?
                    '异常：' + isolationText + '。请勿启用实验观测或正式控制。' :
                    '无法验证代理隔离状态：' + isolationText + '。这不等于已确认安全。'),
            cssClass: isolationTone
        };

        this.updateOverviewUI(s);
        this.updateCalibrationUI(s);
        this.updateTrafficUI(s);

        if (this._calibrationPoll)
            poll.remove(this._calibrationPoll);
        this._calibrationPoll = L.bind(this.refreshCalibration, this);
        poll.add(this._calibrationPoll, 2);

        return E('div', { 'class': 'tvg-root' }, page);
    },

    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
