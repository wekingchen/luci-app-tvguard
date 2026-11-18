'use strict';
'require view';
'require fs';
'require ui';

// 仅管理 TVGuard 专用容器；Token 不进入 UCI、浏览器 URL 或 Docker 参数。
var READ = '/usr/libexec/tvguard-tunnel-read';
var MANAGE = '/usr/libexec/tvguard-tunnel-manage';
var PENDING = '/tmp/tvguard-tunnel/token.pending';
var STYLE = (typeof L !== 'undefined' && L.resource)
    ? L.resource('view/tvguard/panel.css') : '/luci-static/resources/view/tvguard/panel.css';
var PUBLIC_URL = 'https://tv.rqqr.de';

function exec(script, args) {
    return fs.exec(script, args).then(function(r) {
        if (r.code) throw new Error(String(r.stderr || r.stdout || '执行失败').trim());
        return String(r.stdout || '').trim();
    });
}
function button(text, callback, type) {
    return E('button', { 'type': 'button',
        'class': 'btn tvg-btn ' + (type === 'is-primary' ? 'cbi-button-positive' :
            (type === 'is-danger' ? 'cbi-button-negative' : 'cbi-button-action')) +
            (type ? ' ' + type : ''), 'click': callback }, text);
}
function badge(text, kind) {
    return E('span', { 'class': 'tvg-pill' + (kind ? ' ' + kind : '') }, text);
}
function stat(label) {
    var value = E('div', { 'class': 'tvg-stat-value' }, '—');
    var detail = E('div', { 'class': 'tvg-stat-detail' }, '正在读取');
    return { node: E('div', { 'class': 'tvg-stat' }, [
        E('div', { 'class': 'tvg-stat-label' }, label), value, detail
    ]), value: value, detail: detail };
}
function copyText(text, feedback) {
    if (typeof navigator !== 'undefined' && navigator.clipboard && navigator.clipboard.writeText) {
        return navigator.clipboard.writeText(text).then(function() {
            feedback('地址已复制');
        }).catch(function() { feedback('复制失败，请长按链接手动复制', true); });
    }
    feedback('浏览器暂不支持自动复制，请长按链接手动复制');
    return Promise.resolve();
}

return view.extend({
    load: function() {
        return exec(READ, ['status']).then(function(text) { return JSON.parse(text); })
            .catch(function() { return null; });
    },
    render: function(initial) {
        var connected = stat('专用容器'), tokenInfo = stat('Tunnel Token'),
            metrics = stat('Metrics 安全');
        var runBadge = badge('状态未知'), detailsBadge = badge('高级设置');
        var input = E('input', {
            'type': 'password',
            'class': 'tvg-field',
            'autocomplete': 'new-password',
            'spellcheck': 'false',
            'placeholder': '更换 Token 时在此粘贴',
            'aria-label': 'Cloudflare Tunnel Token'
        });
        var logs = E('pre', { 'class': 'tvg-log', 'aria-live': 'polite' },
            '展开后点击“读取日志”，仅显示 TVGuard 专用容器的最近日志。');
        var logActions = E('div', { 'class': 'tvg-controls' }, []);
        var logPanel = E('details', { 'class': 'tvg-details' }, [
            E('summary', {}, '查看最近运行日志'),
            E('p', { 'class': 'tvg-card-desc', 'style': 'margin-top:12px' },
                '只读取专用容器的最后 60 行日志，最多显示 16 KiB；不会操作其他 Docker 服务。'),
            logActions, logs
        ]);
        var address = E('a', {
            'href': PUBLIC_URL, 'class': 'tvg-url',
            'target': '_blank', 'rel': 'noopener noreferrer'
        }, PUBLIC_URL);
        var busy = false, current = null, buttons = [],
            summaryText = E('p', { 'class': 'tvg-card-desc' }, '读取 Tunnel 运行状态中…'),
            inline = E('p', { 'class': 'tvg-message', 'role': 'status', 'aria-live': 'polite' }, '');
        var tokenPanel = E('details', { 'class': 'tvg-details' }, []);
        var start, stop, restart, save, refreshBtn, logButton;

        function inform(message, isError) {
            inline.textContent = String(message || '');
            inline.className = 'tvg-message' + (isError ? ' is-error' : '');
            if (isError) ui.addNotification(null, E('p', {}, message), 'error');
        }
        function busyUI(value) {
            busy = value;
            applyButtons();
        }
        function applyButtons() {
            buttons.forEach(function(b) { b.disabled = !!busy; });
            if (!current || busy) {
                if (!current) buttons.forEach(function(x) { x.disabled = x !== refreshBtn; });
                return;
            }
            var running = current.container === 'running';
            var ready = !!current.configured && !!current.storage_ready && !!current.docker_ready;
            var owned = current.container !== 'foreign' && current.container !== 'unavailable';
            start.disabled = running || !ready || !owned ||
                (current.container === 'missing' && !current.image_present);
            restart.disabled = !ready || !owned || current.container === 'missing';
            stop.disabled = !running;
            save.disabled = !current.storage_ready;
            logButton.disabled = current.container === 'missing' || !owned;
        }
        function renderState(s) {
            current = s;
            if (!s) {
                connected.value.textContent = '读取失败';
                connected.detail.textContent = '请检查 N1 / RPCD';
                tokenInfo.value.textContent = '—';
                tokenInfo.detail.textContent = '状态暂不可用';
                metrics.value.textContent = '—';
                metrics.detail.textContent = '状态暂不可用';
                runBadge.textContent = '无法确认';
                runBadge.className = 'tvg-pill is-warn';
                summaryText.textContent = '无法读取状态，请刷新或检查路由器管理权限。';
                applyButtons();
                return;
            }
            var labels = {
                running: '运行中', exited: '已停止', created: '已创建',
                restarting: '正在重连', paused: '已暂停', dead: '异常',
                missing: '未创建', foreign: '非 TVGuard 容器',
                unavailable: 'Docker 不可用', unknown: '状态未知'
            };
            var state = labels[s.container] || '状态未知';
            connected.value.textContent = state;
            // Shows the configured connector transport, not a claim of live
            // Cloudflare reachability (verify actual edge registration in logs).
            connected.detail.textContent = '容器：tvguard-cloudflared' +
                (s.transport === 'http2' ? ' · HTTP/2（TCP 7844）' :
                 s.transport === 'auto' ? ' · 自动协议（旧容器）' : '');
            tokenInfo.value.textContent = s.configured ? '已保存' : '未配置';
            tokenInfo.detail.textContent = s.configured ? '凭据仅保留在 N1 持久分区' : '需要先填写 Tunnel Token';
            metrics.value.textContent = s.metrics_local ? '仅本机' : '需检查';
            metrics.detail.textContent = s.metrics_local ?
                '127.0.0.1:20241' : '运行参数不满足预期或容器未创建';
            var running = s.container === 'running';
            runBadge.textContent = running ? '容器运行中' : state;
            runBadge.className = 'tvg-pill ' + (running ? 'is-good' :
                s.container === 'foreign' || s.container === 'dead' || s.container === 'unavailable' ?
                    'is-bad' : 'is-warn');
            summaryText.textContent = running ?
                'TVGuard Tunnel 容器正在运行。公网连通性以 Cloudflare 后台和手机实际访问为准。' :
                s.container === 'foreign' ?
                    '同名容器不属于 TVGuard，出于安全考虑拒绝接管。' :
                    '只有专用容器的启停受本页管理，不影响电视计时、ZeroTier 或其他 Tunnel。';
            detailsBadge.textContent = s.configured ? 'Token 已配置' : '需要 Token';
            detailsBadge.className = 'tvg-pill ' + (s.configured ? 'is-good' : 'is-warn');
            if (!s.configured) tokenPanel.open = true;
            applyButtons();
        }
        function refresh() {
            return exec(READ, ['status']).then(function(text) {
                renderState(JSON.parse(text));
                inform('状态已更新');
            }).catch(function(err) {
                renderState(null);
                inform('读取 Tunnel 状态失败：' + String(err.message || err), true);
            });
        }
        function refreshLogs() {
            if (busy) return;
            logPanel.open = true;
            logs.textContent = '正在读取…';
            logButton.disabled = true;
            return exec(READ, ['logs']).then(function(text) {
                logs.textContent = text || '容器暂无日志';
            }).catch(function(err) {
                logs.textContent = '日志读取失败：' + String(err.message || err);
            }).finally(function() { applyButtons(); });
        }
        function runAction(name, confirmText) {
            if (busy) return;
            if (confirmText && !window.confirm(confirmText)) return;
            busyUI(true);
            inform('操作进行中…');
            var completed = false;
            return exec(MANAGE, [name]).then(function(msg) {
                completed = true;
                inform(msg || '操作已完成');
                return exec(READ, ['status']).then(function(text) { renderState(JSON.parse(text)); });
            }).catch(function(err) {
                inform((completed ? '操作已执行，但状态刷新失败：' : '操作失败：') +
                    String(err.message || err), true);
            }).finally(function() { busyUI(false); });
        }
        function saveToken() {
            if (busy) return;
            var value = String(input.value || '').trim();
            if (!/^[A-Za-z0-9_./+=-]{64,8192}$/.test(value)) {
                inform('Token 格式不正确：请粘贴 Cloudflare Tunnel 提供的完整字符串，不能包含空格或换行。', true);
                return;
            }
            if (!window.confirm('确认保存或更换 Tunnel Token？运行中的专用容器会自动重启，外网可能短暂中断。'))
                return;
            busyUI(true);
            inform('正在安全保存 Token…');
            var saved = false;
            return exec(MANAGE, ['prepare']).catch(function(err) {
                throw new Error('准备临时目录失败：' + String(err.message || err));
            }).then(function() {
                return fs.write(PENDING, value).catch(function(err) {
                    throw new Error('写入临时 Token 失败（rpcd 文件 ACL）：' + String(err.message || err));
                });
            }).then(function() {
                return exec(MANAGE, ['save-token']).catch(function(err) {
                    throw new Error('保存到持久分区失败：' + String(err.message || err));
                });
            }).then(function(msg) {
                saved = true;
                inform(msg || 'Tunnel Token 已更新');
                return exec(READ, ['status']).then(function(text) { renderState(JSON.parse(text)); });
            }).catch(function(err) {
                inform((saved ? 'Token 已保存，但状态刷新失败：' : '保存失败：') +
                    String(err.message || err), true);
            }).finally(function() {
                input.value = '';
                value = '';
                busyUI(false);
            });
        }

        start = button('启动 Tunnel', function() { return runAction('start'); }, 'is-primary');
        restart = button('重启', function() {
            return runAction('restart', '重启 TVGuard Tunnel 会短暂中断外网访问，确定继续？');
        });
        stop = button('停止 Tunnel', function() {
            return runAction('stop', '停止 Tunnel 后家中 HTTP 不受影响，但外网家长遥控会中断。确定停止？');
        }, 'is-danger');
        refreshBtn = button('刷新状态', refresh);
        logButton = button('读取日志', refreshLogs, 'is-small');
        logActions.appendChild(logButton);
        save = button('保存 / 更换 Token', saveToken, 'is-primary');
        buttons = [start, restart, stop, refreshBtn, logButton, save];

        tokenPanel = E('details', { 'class': 'tvg-details' }, [
            E('summary', {}, '凭据管理（高级）'),
            E('div', { 'class': 'tvg-details-body' }, [
                E('p', { 'class': 'tvg-card-desc' },
                    'Token 已配置且 Tunnel 正常运行时无需操作。仅在更换 Cloudflare Tunnel 时填写，不会回显已保存的 Token。'),
                E('div', { 'class': 'tvg-secret-wrap' }, [input, save]),
                E('p', { 'class': 'tvg-caption' },
                    '凭据写入 N1 的 XFS 持久分区，不进入 UCI 或 Docker 命令行。本页仅操作 tvguard-cloudflared。')
            ])
        ]);

        var page = E('div', { 'class': 'tvg-console' }, [
            E('link', { 'rel': 'stylesheet', 'href': STYLE + '?v=0.1.16-r22' }),
            E('div', { 'class': 'tvg-header' }, [
                E('div', {}, [
                    E('div', { 'class': 'tvg-page-heading', 'role': 'heading', 'aria-level': '1' }, 'TV Guard · 远程访问'),
                    E('p', { 'class': 'tvg-intro' },
                        '通过独立的 Cloudflare Tunnel 访问家长遥控，不开放 LuCI 管理界面。')
                ]),
                refreshBtn
            ]),
            E('div', { 'class': 'tvg-status-grid' }, [
                connected.node, tokenInfo.node, metrics.node
            ]),
            E('div', { 'class': 'tvg-layout' }, [
                E('section', { 'class': 'tvg-card' }, [
                    E('div', { 'class': 'tvg-card-header' }, [
                        E('div', { 'class': 'tvg-card-title', 'role': 'heading', 'aria-level': '2' }, '外网家长遥控'),
                        badge('公网 HTTPS')
                    ]),
                    E('p', { 'class': 'tvg-card-desc' },
                        '你已配置的 TVGuard 专用域名。家长手机从外部网络打开后，仍需经过设备配对认证。'),
                    E('div', { 'class': 'tvg-address' }, [
                        address,
                        E('div', { 'class': 'tvg-address-actions' }, [
                            button('复制', function() { return copyText(PUBLIC_URL, inform); }, 'is-small'),
                            E('a', { 'class': 'btn cbi-button-positive tvg-btn is-primary is-small',
                                'href': PUBLIC_URL, 'target': '_blank',
                                'rel': 'noopener noreferrer' }, '打开')
                        ])
                    ]),
                    E('p', { 'class': 'tvg-caption' },
                        '容器运行状态不等于公网连通确认；可从手机蜂窝网络验证实际访问。'),
                    E('div', { 'class': 'tvg-safety' },
                        '当前方案未启用 Cloudflare Access。公网可以打开配对页面，控制操作仍需 TVGuard 自身授权。')
                ]),
                E('section', { 'class': 'tvg-card' }, [
                    E('div', { 'class': 'tvg-card-header' }, [
                        E('div', { 'class': 'tvg-card-title', 'role': 'heading', 'aria-level': '2' }, 'Tunnel 服务'),
                        runBadge
                    ]),
                    summaryText,
                    E('div', { 'class': 'tvg-controls' }, [start, restart, stop]),
                    E('details', { 'class': 'tvg-details' }, [
                        E('summary', {}, '运行环境与安全限制'),
                        E('div', { 'class': 'tvg-details-body' }, [
                            E('dl', { 'class': 'tvg-data' }, [
                                E('dt', {}, '容器名'), E('dd', {}, 'tvguard-cloudflared'),
                                E('dt', {}, '出站协议'), E('dd', {}, 'HTTP/2（TCP 7844）'),
                                E('dt', {}, 'Metrics'), E('dd', {}, '127.0.0.1:20241（仅本机）'),
                                E('dt', {}, '回源'), E('dd', {}, 'http://localhost:18765'),
                                E('dt', {}, '容器安全'), E('dd', {}, '专属标签、最小权限、独立日志轮转')
                            ]),
                            E('p', { 'class': 'tvg-caption' },
                                '仅操作 TVGuard 专用容器，不接管 Vaultwarden、ntfy 或其它 Tunnel。')
                        ])
                    ])
                ]),
                E('section', { 'class': 'tvg-card tvg-card-wide' }, [
                    E('div', { 'class': 'tvg-card-header' }, [
                        E('div', { 'class': 'tvg-card-title', 'role': 'heading', 'aria-level': '2' }, '维护与诊断'),
                        detailsBadge
                    ]),
                    E('p', { 'class': 'tvg-card-desc' },
                        '正常使用无需操作。遇到 Tunnel 连接问题时查看日志；仅在凭据变更时编辑 Token。'),
                    tokenPanel,
                    logPanel
                ])
            ]),
            inline,
            E('p', { 'class': 'tvg-footer' },
                '外网仅转发至家长遥控服务，不要发布 LuCI、SSH 或 RPCD。家中的 HTTP 访问可在「家长遥控」页面管理。')
        ]);
        renderState(initial);
        return page;
    }
});
