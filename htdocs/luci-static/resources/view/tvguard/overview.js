'use strict';
'require view';
'require fs';
'require ui';
'require poll';

function minutes(seconds) {
    return Math.ceil(Number(seconds || 0) / 60);
}

function panel(title, children) {
    return E('div', {
        'class': 'cbi-section',
        'style': 'margin-bottom:16px;padding:14px;border:1px solid var(--border-color-medium,#ddd);border-radius:8px'
    }, [ E('h3', title) ].concat(children));
}

return view.extend({
    load: function() {
        return Promise.all([
            fs.exec('/usr/libexec/tvguard-status', ['status']).then(function(r) {
                if (r.code) throw new Error(r.stderr || '读取状态失败');
                return JSON.parse(r.stdout);
            }),
            fs.exec('/usr/libexec/tvguard-status', ['log']).then(function(r) {
                return r.stdout || '';
            }),
            fs.exec('/usr/libexec/tvguard-status', ['calibration']).then(function(r) {
                return r.stdout || '';
            })
        ]);
    },

    updateCalibrationUI: function(state) {
        var n = this._calibrationNodes;
        if (!n)
            return;
        var phase = String(state.calibration_phase || 'idle');
        var active = phase === 'running' || phase === 'finishing';
        var elapsed = Math.max(0, Math.min(120, Number(state.calibration_elapsed_seconds) || 0));
        var remaining = Math.max(0, Number(state.calibration_remaining_seconds) || 0);
        var count = Math.max(0, Number(state.calibration_samples) || 0);
        var progress = Math.max(0, Math.min(100, Number(state.calibration_percent) || 0));

        n.bar.value = active ? progress : (phase === 'completed' ? 100 : 0);
        n.bar.setAttribute('aria-valuenow', String(n.bar.value));
        n.start.disabled = active;
        n.stop.disabled = !active;
        n.selection.disabled = active;
        n.scene.disabled = active;
        n.bar.style.display = active || phase === 'completed' ? '' : 'none';

        if (phase === 'running') {
            n.title.textContent = '正在采样 · ' + state.calibration_app + ' / ' + state.calibration_label;
            n.detail.textContent = '已进行 ' + elapsed + ' / 120 秒 · 还剩 ' + remaining +
                ' 秒 · 已记录 ' + count + ' 条样本（每约 10 秒一条）';
            n.hint.textContent = '正在自动更新，无需停留或刷新页面；保持电视状态不变。';
        }
        else if (phase === 'finishing') {
            n.title.textContent = '采样时间已到，正在汇总…';
            n.detail.textContent = '已记录 ' + count + ' 条样本，等待后台下一次采样完成结算。';
            n.hint.textContent = '正常情况下几秒后自动显示结果，无需重复点击开始。';
        }
        else if (phase === 'completed' || phase === 'stopped' || phase === 'interrupted') {
            n.title.textContent = phase === 'completed' ? '本次采样已完成' :
                (phase === 'stopped' ? '本次采样已手动停止' : '采样被中断');
            n.detail.textContent = '应用/场景：' + state.calibration_last_app + ' / ' +
                state.calibration_last_label + ' · 已保存 ' +
                String(state.calibration_last_samples || 0) + ' 条样本';
            n.hint.textContent = phase === 'completed' ?
                '采样数据已保存，可继续选择其他场景。一次标注不代表已能准确识别。' :
                '本次结果已记录，后续可重新开始校准。';
        }
        else {
            n.title.textContent = '等待开始采样';
            n.detail.textContent = '选择电视应用与当前场景，点击开始后将自动显示进度。';
            n.hint.textContent = '校准仅记录网络特征，不自动暂停计时，也不会封禁电视。';
        }
    },

    refreshCalibration: function() {
        return fs.exec('/usr/libexec/tvguard-status', ['status']).then(L.bind(function(r) {
            if (r.code)
                throw new Error(r.stderr || '后台状态读取失败');
            var s = JSON.parse(r.stdout);
            this.updateCalibrationUI(s);
            var n = this._calibrationNodes;
            var session = s.calibration_last_session || 'none';
            if (n && session !== 'none' && n.lastSession !== session) {
                n.lastSession = session;
                return fs.exec('/usr/libexec/tvguard-status', ['calibration']).then(function(result) {
                    if (!result.code)
                        n.samples.textContent = (result.stdout || '').split('\n').slice(-12).join('\n') || '暂无标注样本';
                });
            }
        }, this)).catch(L.bind(function(err) {
            if (this._calibrationNodes)
                this._calibrationNodes.hint.textContent = '实时更新暂时失败，请检查 N1 连接；已有样本不会因此丢失。';
        }, this));
    },

    handleAction: function(args, warning, ev) {
        if (!window.confirm(warning))
            return Promise.resolve();

        return fs.exec('/usr/libexec/tvguardctl', args).then(function(r) {
            if (r.code)
                throw new Error(r.stderr || r.stdout || '操作失败');
            window.location.reload();
        }).catch(function(err) {
            ui.addNotification(null, E('p', {}, String(err)), 'error');
        });
    },

    actionButton: function(label, args, prompt, danger) {
        return E('button', {
            'class': danger ? 'btn cbi-button-negative' : 'btn cbi-button-action',
            'style': 'margin:4px 8px 4px 0',
            'click': ui.createHandlerFn(this, 'handleAction', args, prompt)
        }, label);
    },

    render: function(result) {
        var s = result[0], events = result[1], samples = result[2];
        var mode = { child: '儿童模式', parent: '家长模式', locked: '手动锁定' }[s.mode] || '未知';
        var activity = { active: '检测到网络活动', silent: '网络静默', unknown: '尚未检测' }[s.activity] || '未知';
        var fwState = {
            blocked: 'N1 上的 TV Guard 规则正在丢弃电视数据包',
            allowed: 'N1 上的 TV Guard 规则允许电视数据包继续处理',
            absent: '未找到 TV Guard 入口规则',
            unknown: '无法核实当前 TV Guard 防火墙规则'
        }[s.firewall_state] || '未知';
        var blocks = (s.enforce ? '正式控制' : '观察模式') + ' · ' + fwState;
        var appSelect = E('select', { 'class': 'cbi-input-select', 'style': 'margin:4px' }, [
            E('option', { 'value': 'tencent' }, '腾讯极光'),
            E('option', { 'value': 'iqiyi' }, '爱奇艺'),
            E('option', { 'value': 'mango' }, '芒果 TV'),
            E('option', { 'value': 'other' }, '其他视频应用')
        ]);
        var sceneSelect = E('select', { 'class': 'cbi-input-select', 'style': 'margin:4px' }, [
            E('option', { 'value': 'playing' }, '正常播放'),
            E('option', { 'value': 'paused' }, '视频暂停'),
            E('option', { 'value': 'app_home' }, '应用首页闲置'),
            E('option', { 'value': 'system_home' }, '小米系统首页闲置'),
            E('option', { 'value': 'sleep' }, '熄屏待机')
        ]);
        var startCalibration = E('button', {
            'class': 'btn cbi-button-action',
            'click': ui.createHandlerFn(this, function() {
                var label = sceneSelect.value, app = appSelect.value;
                return this.handleAction(['calibrate', label, app],
                    '请确认电视当前实际状态为“' + sceneSelect.options[sceneSelect.selectedIndex].text +
                    '”。接下来记录 120 秒，期间不要操作遥控器。');
            })
        }, '开始 120 秒标注');
        var stopCalibration = this.actionButton('停止校准', ['calibrate', 'stop'], '提前结束本次采样吗？');
        var calTitle = E('strong', {}, '等待开始采样');
        var calDetail = E('div', { 'style': 'margin:8px 0' }, '');
        var calProgress = E('progress', { 'max': '100', 'value': '0',
            'style': 'width:100%;height:18px;display:none', 'role': 'progressbar',
            'aria-valuemin': '0', 'aria-valuemax': '100', 'aria-valuenow': '0' });
        var calHint = E('p', { 'class': 'description', 'style': 'margin-top:8px' }, '');
        var samplePreview = E('pre', {
            'style': 'max-height:160px;overflow:auto;white-space:pre-wrap;word-break:break-word'
        }, (samples || '').split('\n').slice(-12).join('\n') || '暂无标注样本');
        this._calibrationNodes = {
            title: calTitle, detail: calDetail, bar: calProgress, hint: calHint,
            start: startCalibration, stop: stopCalibration, selection: appSelect,
            scene: sceneSelect, samples: samplePreview,
            lastSession: s.calibration_last_session || 'none'
        };
        var page = [
            E('h2', 'TV Guard · 电视时间管理'),
            E('p', { 'class': 'alert-message warning' },
                '当前版本仅按网络活动估算使用会话；尚不能可靠识别系统首页、App 首页或视频暂停。默认观察模式，不会自动断网。'),
            panel('当前状态', [
                E('p', [ E('strong', '使用模式：'), mode ]),
                E('p', [ E('strong', '网络状态：'), activity ]),
                E('p', [ E('strong', '防火墙状态：'), blocks ]),
                E('p', [ E('strong', '日期：'), s.date ])
            ]),
            panel('网络采样与手工校准（观察模式）', [
                E('p', { 'class': 'description' },
                    '这些只是网络活动统计，不能证明电视目前属于哪个视频 App、是否暂停或是否有人观看。校准标签由家长手动确认，绝不自动免计时。'),
                E('p', [ E('strong', '最近 10 秒总包频率：'), String(s.pps || 0) + ' PPS' ]),
                E('p', [
                    E('strong', 'TCP：'), String(s.tcp_pps || 0) + ' PPS · ',
                    E('strong', 'UDP：'), String(s.udp_pps || 0) + ' PPS · ',
                    E('strong', '速率：'), String(s.bytes_per_second || 0) + ' B/s'
                ]),
                E('p', [ E('strong', '网络强度：'), String(s.traffic_class || 'unknown') ]),
                E('p', [ E('strong', '网络指纹候选：'),
                    ({ playing:'疑似播放', paused:'疑似暂停', app_home:'疑似应用首页',
                       system_home:'疑似小米系统首页', sleep:'疑似熄屏网络静默',
                       unknown:'无法判断' })[s.shadow_label] || '无法判断',
                    ' · 参考应用：' + (s.shadow_app || 'none'),
                    ' · 匹配分数：' + String(s.shadow_score || 0) + '（不是准确率）'
                ]),
                E('p', { 'class':'description' },
                    '候选识别必须积累多次独立标注样本，且目前仅显示诊断结果，不会改变儿童计时或封禁策略。'),
                E('div', { 'style': 'padding:12px;margin:12px 0;border:1px solid #bbb;border-radius:8px' }, [
                    calTitle, calDetail, calProgress, calHint
                ]),
                E('p', '先在电视上打开并保持对应状态；请选择 App 和状态，手工标注 120 秒。只是采集样本，不会自动免计时。'),
                E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:6px;margin-bottom:8px' },
                    [appSelect, sceneSelect, startCalibration, stopCalibration]),
                samplePreview
            ]),
            panel('今日儿童额度', [
                E('p', [ E('strong', '已计时：'), minutes(s.used_seconds) + ' 分钟' ]),
                E('p', [ E('strong', '当日额度：'), minutes(s.quota_seconds) + ' 分钟' ]),
                E('p', [ E('strong', '剩余：'), minutes(s.remaining_seconds) + ' 分钟' ]),
                E('p', [ E('strong', '今日奖励：'), '+' + minutes(s.bonus_seconds) + ' 分钟' ]),
                E('p', { 'class': 'description' },
                    '统计的是经过 N1 的联网活动推算的时长，并非真实屏幕观看时间。')
            ]),
            panel('观看模式', [
                this.actionButton('儿童模式', ['mode', 'child'], '切换为儿童模式？'),
                this.actionButton('家长 30 分钟', ['mode', 'parent', '30'], '授权家长观看 30 分钟？'),
                this.actionButton('家长 60 分钟', ['mode', 'parent', '60'], '授权家长观看 60 分钟？'),
                this.actionButton('家长 120 分钟', ['mode', 'parent', '120'], '授权家长观看 120 分钟？'),
                this.actionButton('立即锁定', ['mode', 'locked'], '将电视切换为锁定模式？开启正式控制后会阻断联网。', true)
            ]),
            panel('儿童时间奖励', [
                this.actionButton('+15 分钟', ['bonus', '15'], '确认奖励今天的儿童额度 15 分钟？'),
                this.actionButton('+30 分钟', ['bonus', '30'], '确认奖励今天的儿童额度 30 分钟？'),
                this.actionButton('+60 分钟', ['bonus', '60'], '确认奖励今天的儿童额度 60 分钟？'),
                this.actionButton('撤销上次奖励', ['bonus', 'undo'], '撤销今日最后一笔未撤销的奖励？', true)
            ]),
            panel('执行策略', [
                E('p', s.enforce ?
                    '正式控制已开启。网络封禁仅覆盖经过 N1 的 IPv4 数据包。' :
                    '目前只观察和计时，手动锁定也不会阻断电视。'),
                s.enforce ?
                    this.actionButton('关闭控制，恢复观察模式', ['enforce', 'off'],
                        '确认关闭所有 TV Guard 自动封禁？', true) :
                    (s.armed ?
                        this.actionButton('开启正式网络控制', ['enforce', 'on'],
                            '即将实际阻断经过 N1 的电视 IPv4 数据包。确认已完成现场测试并准备好恢复方案吗？', true) :
                        E('p', { 'class': 'alert-message warning' },
                            '正式控制尚未解锁。开发版默认只观察；待实机验证完成后，管理员才能通过 UCI 显式授权开启。'))
            ]),
            panel('最近操作记录', [
                E('pre', {
                    'style': 'max-height:250px;overflow:auto;white-space:pre-wrap;word-break:break-word'
                }, events || '尚无操作记录')
            ])
        ];
        this.updateCalibrationUI(s);
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
