'use strict';
'require view';
'require fs';
'require ui';

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
            })
        ]);
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
        var s = result[0], events = result[1];
        var mode = { child: '儿童模式', parent: '家长模式', locked: '手动锁定' }[s.mode] || '未知';
        var activity = { active: '检测到网络活动', silent: '网络静默', unknown: '尚未检测' }[s.activity] || '未知';
        var blocks = s.enforce ? (s.blocked ? '已封禁' : '允许联网') : '观察模式：不会封禁';
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
                    this.actionButton('开启正式网络控制', ['enforce', 'on'],
                        '即将实际阻断电视的网络访问。请先完成现场测试，并确认主路由绕过风险。继续吗？', true)
            ]),
            panel('最近操作记录', [
                E('pre', {
                    'style': 'max-height:250px;overflow:auto;white-space:pre-wrap;word-break:break-word'
                }, events || '尚无操作记录')
            ])
        ];
        return E('div', {}, page);
    },

    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
