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
    var heading = [E('h3', { 'style': 'margin:0 0 4px;font-size:1.15rem' }, title)];
    if (subtitle)
        heading.push(E('div', {
            'class': 'description',
            'style': 'margin:0;line-height:1.55'
        }, subtitle));

    return E('section', {
        'class': 'cbi-section',
        'style': [
            'margin:0 0 16px',
            'padding:16px',
            'border:1px solid var(--border-color-medium,#ddd)',
            'border-radius:12px',
            'box-shadow:0 1px 2px rgba(0,0,0,.04)',
            extraStyle || ''
        ].join(';')
    }, [E('div', { 'style': 'margin-bottom:12px' }, heading)].concat(children || []).filter(function(node) {
        return node != null;
    }));
}

function metric(label, value, note, emphasis) {
    var children = [
        E('div', {
            'class': 'description',
            'style': 'margin-bottom:6px'
        }, label),
        E('div', {
            'style': 'font-size:' + (emphasis ? '1.65rem' : '1.2rem') +
                ';font-weight:700;line-height:1.2;overflow-wrap:anywhere'
        }, value)
    ];
    if (note)
        children.push(E('div', {
            'class': 'description',
            'style': 'margin-top:6px;line-height:1.45'
        }, note));

    return E('div', {
        'style': [
            'min-width:0',
            'padding:14px',
            'border:1px solid var(--border-color-medium,#ddd)',
            'border-radius:10px',
            'background:var(--background-color-high,#fafafa)'
        ].join(';')
    }, children);
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
            'background:var(--background-color-high,transparent)',
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

function grid(children, minWidth) {
    return E('div', {
        'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(' +
            (minWidth || 160) + 'px,1fr));gap:10px'
    }, children);
}

function buttonRow(children) {
    return E('div', {
        'style': 'display:flex;flex-wrap:wrap;gap:8px;align-items:center'
    }, children);
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
        paused: '疑似暂停',
        app_home: '疑似应用首页',
        system_home: '疑似系统首页',
        sleep: '疑似待机',
        unknown: '暂时无法判断'
    }[value] || '暂时无法判断';
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
    return '儿童额度会按联网活动估算消耗';
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
            fs.exec('/usr/libexec/tvguard-status', ['calibration']).then(function(r) {
                return r.stdout || '';
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
                '不消耗儿童额度，不受儿童时段限制；直到手动切回儿童模式') :
            (state.mode === 'locked' ?
                (state.enforce ? '正式控制下会阻断电视联网' : '观察模式下只记录锁定意图，不断网') :
                childPolicyNote(state));
        var activityName = {
            active: '检测到联网活动',
            silent: '当前网络静默',
            unknown: '等待首次采样'
        }[state.activity] || '状态未知';
        var quota = Math.max(0, Number(state.quota_seconds) || 0);
        var used = Math.max(0, Number(state.used_seconds) || 0);
        var quotaPercent = quota > 0 ? clamp(used * 100 / quota, 0, 100) : 0;

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

        n.shadowValue.textContent = shadowName(state.shadow_label);
        n.shadowNote.textContent = state.shadow_label === 'unknown' ?
            '当前证据不足或样本重叠，不做推断。' :
            '仅作为实验候选，不会自动免计时。';
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
        var elapsed = clamp(state.calibration_elapsed_seconds, 0, 120);
        var remaining = Math.max(0, Number(state.calibration_remaining_seconds) || 0);
        var count = Math.max(0, Number(state.calibration_samples) || 0);
        var progress = clamp(state.calibration_percent, 0, 100);

        n.bar.value = active ? progress : (phase === 'completed' ? 100 : 0);
        n.bar.setAttribute('aria-valuenow', String(n.bar.value));
        n.start.disabled = active;
        n.stop.disabled = !active;
        n.selection.disabled = active;
        n.scene.disabled = active;
        n.bar.style.display = active || phase === 'completed' ? '' : 'none';

        if (phase === 'running') {
            n.title.textContent = '正在记录 · ' + appName(state.calibration_app) +
                ' · ' + sceneName(state.calibration_label);
            n.detail.textContent = '已进行 ' + elapsed + ' / 120 秒 · 剩余 ' + remaining +
                ' 秒 · 已保存 ' + count + ' 条样本';
            n.hint.textContent = '保持电视当前状态不变即可，页面会自动更新。';
        }
        else if (phase === 'finishing') {
            n.title.textContent = '采样结束，正在整理结果…';
            n.detail.textContent = '已保存 ' + count + ' 条样本，等待后台完成最后一次结算。';
            n.hint.textContent = '无需重复点击，结果会自动刷新。';
        }
        else if (phase === 'completed' || phase === 'stopped' || phase === 'interrupted') {
            n.title.textContent = phase === 'completed' ? '本次标注已完成' :
                (phase === 'stopped' ? '本次标注已提前结束' : '本次标注被中断');
            n.detail.textContent = '场景：' + sceneName(state.calibration_last_label) +
                ' · 标签：' + appName(state.calibration_last_app) +
                ' · 保存 ' + String(state.calibration_last_samples || 0) + ' 条样本';
            n.hint.textContent = phase === 'completed' ?
                '数据已保存。一次标注只用于验证算法，不代表系统已经学会自动判断。' :
                '已有数据会保留，之后可以重新开始。';
        }
        else {
            n.title.textContent = '未在采样';
            n.detail.textContent = '需要验证算法时再使用；日常管理电视不需要做这一步。';
            n.hint.textContent = '标注只记录网络特征，不改变计时，也不会封禁电视。';
        }
    },

    refreshCalibration: function() {
        return fs.exec('/usr/libexec/tvguard-status', ['status']).then(L.bind(function(r) {
            if (r.code)
                throw new Error(r.stderr || '后台状态读取失败');

            var s = JSON.parse(r.stdout);
            this.updateOverviewUI(s);
            this.updateCalibrationUI(s);
            this.updateTrafficUI(s);

            var n = this._calibrationNodes;
            var session = s.calibration_last_session || 'none';
            if (n && session !== 'none' && n.lastSession !== session) {
                n.lastSession = session;
                return fs.exec('/usr/libexec/tvguard-status', ['calibration']).then(function(result) {
                    if (!result.code)
                        n.samples.textContent = (result.stdout || '').split('\n').slice(-12).join('\n') ||
                            '暂无标注样本';
                });
            }
        }, this)).catch(L.bind(function() {
            if (this._calibrationNodes)
                this._calibrationNodes.hint.textContent =
                    '实时更新暂时失败；已有数据不会丢失，可稍后刷新页面。';
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
        var isolation = result[3] || { code: 2, text: 'unavailable' };
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
                '不消耗儿童额度，不受儿童时段限制；直到手动切回儿童模式') :
            (s.mode === 'locked' ?
                (s.enforce ? '正式控制下会阻断电视联网' : '观察模式下只记录锁定意图，不断网') :
                childPolicyNote(s));

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
                'class': 'alert-message success',
                'style': 'margin:0 0 16px;line-height:1.55'
            }, '当前为观察模式：可以计时、切换模式和记录奖励，但 TV Guard 不会主动断开电视网络。');
        }

        var appSelect = E('select', {
            'class': 'cbi-input-select',
            'aria-label': '标注应用标签',
            'style': 'min-width:190px;flex:1'
        }, [
            E('option', { 'value': 'general' }, '通用采样（推荐）'),
            E('option', { 'value': 'tencent' }, '腾讯极光（验证标签）'),
            E('option', { 'value': 'iqiyi' }, '爱奇艺（验证标签）'),
            E('option', { 'value': 'mango' }, '芒果 TV（验证标签）'),
            E('option', { 'value': 'other' }, '其他视频应用（验证标签）')
        ]);

        var sceneSelect = E('select', {
            'class': 'cbi-input-select',
            'aria-label': '标注电视场景',
            'style': 'min-width:170px;flex:1'
        }, [
            E('option', { 'value': 'playing' }, '正常播放'),
            E('option', { 'value': 'paused' }, '视频暂停'),
            E('option', { 'value': 'app_home' }, '应用首页闲置'),
            E('option', { 'value': 'system_home' }, '小米系统首页闲置'),
            E('option', { 'value': 'sleep' }, '熄屏待机')
        ]);

        var startCalibration = E('button', {
            'type': 'button',
            'class': 'btn cbi-button-action',
            'style': 'min-height:36px',
            'click': ui.createHandlerFn(this, function(ev) {
                var label = sceneSelect.value, app = appSelect.value;
                return this.handleAction(
                    ['calibrate', label, app],
                    '请确认电视当前确实处于“' +
                        sceneSelect.options[sceneSelect.selectedIndex].text +
                        '”。接下来会记录 120 秒，请暂时不要操作遥控器。',
                    ev
                );
            })
        }, '开始 120 秒标注');

        var stopCalibration = this.actionButton('提前结束', ['calibrate', 'stop'], {
            title: '停止后已采到的数据仍会保留'
        });
        var calTitle = E('strong', {}, '未在采样');
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
        var samplePreview = E('pre', {
            'style': [
                'max-height:150px',
                'overflow:auto',
                'white-space:pre-wrap',
                'word-break:break-word',
                'font-size:.85rem',
                'padding:10px',
                'border-radius:8px',
                'background:var(--background-color-high,#f7f7f7)'
            ].join(';')
        }, (samples || '').split('\n').slice(-12).join('\n') || '暂无标注样本');

        this._calibrationNodes = {
            title: calTitle,
            detail: calDetail,
            bar: calProgress,
            hint: calHint,
            start: startCalibration,
            stop: stopCalibration,
            selection: appSelect,
            scene: sceneSelect,
            samples: samplePreview,
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
            'class': 'alert-message success',
            'style': 'margin:12px 0 0;' + (s.mode === 'parent' ? '' : 'display:none')
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
        var shadowValueNode = E('span', {}, shadowName(s.shadow_label));
        var shadowNoteNode = E('span', {}, s.shadow_label === 'unknown' ?
            '当前证据不足或样本重叠，不做推断。' :
            '仅作为实验候选，不会自动免计时。');
        var trafficValueNode = E('span', {}, trafficName(s.traffic_class));
        var trafficNoteNode = E('span', {}, String(s.pps || 0) + ' PPS · ' +
            byteRate(s.bytes_per_second || 0));

        this._overviewNodes = {
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
            E('div', { 'style': 'margin-bottom:14px' }, [
                E('h2', { 'style': 'margin-bottom:4px' }, 'TV Guard · 电视时间管理'),
                E('div', {
                    'class': 'description',
                    'style': 'font-size:.95rem;line-height:1.5'
                }, '先把日常管理做简单；网络诊断和算法实验都收在页面下方，需要时再展开。')
            ]),
            statusBanner,

            grid([
                metric('今日剩余', remainingNode, '儿童额度剩余', true),
                metric('当前模式', modeNode, modeNoteNode, false),
                metric('控制状态', controlName, controlNote, false),
                E('div', {
                    'style': 'min-width:0;padding:14px;border:1px solid var(--border-color-medium,#ddd);' +
                        'border-radius:10px;background:var(--background-color-high,#fafafa)'
                }, [
                    E('div', { 'class': 'description', 'style': 'margin-bottom:7px' }, '网络安全'),
                    badge(isolationShort, isolationTone),
                    E('div', {
                        'class': 'description',
                        'style': 'margin-top:7px;line-height:1.45'
                    }, activityNode)
                ])
            ], 180),

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

            panel('观看模式', '儿童模式按额度和时段管理；家长模式持续生效且不消耗儿童额度，直到手动切回；锁定是否真的断网取决于“正式控制”是否开启。', [
                buttonRow(modeButtons),
                parentNoticeNode
            ]),

            panel('儿童奖励时间', '孩子临时多看一会儿就加奖励时间。奖励只增加今天的儿童额度，不改变模式；如果点错，可以撤销最近一笔奖励。', [
                buttonRow([
                    reward15Button,
                    reward30Button,
                    reward60Button,
                    undoButton
                ]),
                rewardLimitNode
            ]),

            panel('智能识别 · 实验', '用于验证“播放 / 暂停 / 首页 / 待机”的通用网络特征。当前结果只展示，不参与计时和封禁。', [
                grid([
                    metric('当前候选', shadowValueNode, shadowNoteNode, false),
                    metric('网络活动强度', trafficValueNode, trafficNoteNode, false)
                ], 220),
                detailBlock('手工标注与样本', [
                    E('div', {
                        'style': 'padding:12px;border:1px solid var(--border-color-medium,#ddd);border-radius:9px;' +
                            'background:var(--background-color-high,#fafafa);margin-bottom:10px'
                    }, [calTitle, calDetail, calProgress, calHint]),
                    E('p', {
                        'class': 'description',
                        'style': 'line-height:1.55'
                    }, '日常使用不需要逐个标注 App。默认选“通用采样”；具体 App 只作为算法泛化验证标签。'),
                    buttonRow([appSelect, sceneSelect, startCalibration, stopCalibration]),
                    detailBlock('查看最近原始样本', [samplePreview], false)
                ], s.calibration_phase === 'running' || s.calibration_phase === 'finishing')
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
                E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px' }, [
                    E('div', {
                        'style': 'padding:12px;border:1px solid var(--border-color-medium,#ddd);border-radius:9px'
                    }, [
                        E('strong', {}, '电视向 N1 发包'),
                        E('div', { 'style': 'margin-top:6px' }, trafficNodes.outgoing),
                        E('div', { 'class': 'description', 'style': 'margin-top:4px' }, trafficNodes.outgoingProtocol)
                    ]),
                    E('div', {
                        'style': 'padding:12px;border:1px solid var(--border-color-medium,#ddd);border-radius:9px'
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
                            'background:var(--background-color-high,#f7f7f7)'
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

        return E('div', {}, page);
    },

    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
