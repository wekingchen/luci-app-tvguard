'use strict';
'require view';
'require fs';
'require ui';

// 家长遥控后台只调用已有的限权 RPCD 包装，不暴露 uhttpd、UCI 或 tvguardctl。
var READ = '/usr/libexec/tvguard-remote-read';
var MANAGE = '/usr/libexec/tvguard-remote-manage';
var STYLE = (typeof L !== 'undefined' && L.resource)
    ? L.resource('view/tvguard/panel.css') : '/luci-static/resources/view/tvguard/panel.css';

function exec(path, args) {
    return fs.exec(path, args).then(function(r) {
        if (r.code) throw new Error(String(r.stderr || r.stdout || '操作失败').trim());
        return String(r.stdout || '').trim();
    });
}
function button(label, callback, type) {
    return E('button', { 'type': 'button',
        'class': 'tvg-btn' + (type ? ' ' + type : ''), 'click': callback }, label);
}
function block(title, right, description) {
    return E('div', { 'class': 'tvg-card-header' }, [
        E('h3', { 'class': 'tvg-card-title' }, title),
        right || E('span'),
        description || E('span')
    ]);
}
function pill(label, kind) {
    return E('span', { 'class': 'tvg-pill' + (kind ? ' ' + kind : '') }, label);
}
function stat(label) {
    var value = E('div', { 'class': 'tvg-stat-value' }, '—');
    var note = E('div', { 'class': 'tvg-stat-detail' }, '正在读取');
    return { value: value, note: note, node: E('div', { 'class': 'tvg-stat' }, [
        E('div', { 'class': 'tvg-stat-label' }, label), value, note
    ]) };
}
function info(label, text) { return [E('dt', {}, label), E('dd', {}, text)]; }
function validLocalUrl(s) {
    var url = String(s || '');
    return /^http:\/\/(10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+):18765\/$/.test(url) ? url : '';
}
function dateText(epoch) {
    var n = Number(epoch);
    return n > 0 && isFinite(n) ? new Date(n * 1000).toLocaleString('zh-CN') : '历史配对，时间未记录';
}
return view.extend({
    load: function() {
        return exec(READ, ['status']).then(function(text) { return JSON.parse(text); })
            .catch(function() { return null; });
    },
    render: function(initial) {
        var busy = false, current = null, buttons = [], deviceButtons = [];
        var home = stat('家中 Wi-Fi'), service = stat('遥控服务'), devices = stat('授权设备');
        var serviceBadge = pill('状态未知'), lanBadge = pill('状态未知');
        var lanUrl = E('a', { 'class': 'tvg-url', 'target': '_blank',
            'rel': 'noopener noreferrer' }, '当前未开放局域网');
        var lanAddress = E('div', { 'class': 'tvg-address', 'style': 'display:none' }, [
            lanUrl, E('div', { 'class': 'tvg-address-actions' }, [
                button('复制地址', function() {
                    if (current && validLocalUrl(current.lan_url))
                        return copyText(current.lan_url);
                }, 'is-small')
            ])
        ]);
        var serviceMessage = E('p', { 'class': 'tvg-caption' },
            '独立遥控服务默认只允许本机访问。');
        var lanMessage = E('p', { 'class': 'tvg-caption' },
            '通过家中可信 Wi-Fi 直连，无需配置证书。');
        var deviceList = E('div', { 'class': 'tvg-devices', 'aria-live': 'polite' }, '正在读取设备…');
        var pairCode = E('code', { 'class': 'tvg-code', 'aria-live': 'polite' }, '未生成配对码');
        var pairTimer = E('span', { 'class': 'tvg-caption', 'aria-live': 'polite' },
            '一次性配对码仅供当前可信设备使用');
        var errorText = E('div', { 'class': 'tvg-message', 'role': 'status', 'aria-live': 'polite' }, '');
        var issueDeadline = 0, latestCode = '', timer = null, root;
        var enable, disable, enableLan, disableLan, pair, revoke, update, copyCode;

        function report(msg, level) {
            errorText.textContent = msg || '';
            errorText.className = 'tvg-message' + (level === 'error' ? ' is-error' : '');
            if (level === 'error') ui.addNotification(null, E('p', {}, msg), 'error');
        }
        function copyText(text) {
            if (!text) return Promise.resolve();
            if (typeof navigator !== 'undefined' && navigator.clipboard && navigator.clipboard.writeText) {
                return navigator.clipboard.writeText(text).then(function() {
                    report('已复制到剪贴板');
                }).catch(function() { report('复制未成功，请长按内容手动复制', 'error'); });
            }
            // HTTP 管理页面可能不是安全上下文；保留手工复制方案而非要求额外权限。
            report('当前浏览器不支持自动复制，请选中地址或配对码手动复制');
            return Promise.resolve();
        }
        function tick() {
            if (!issueDeadline) return;
            var left = Math.max(0, Math.ceil((issueDeadline - Date.now()) / 1000));
            if (!left) {
                pairCode.textContent = '配对码已过期';
                copyCode.disabled = true;
                pairCode.className = 'tvg-code is-expired';
                pairTimer.textContent = '请重新生成一次性配对码';
                latestCode = '';
                issueDeadline = 0;
                return;
            }
            var min = Math.floor(left / 60);
            pairTimer.textContent = '剩余 ' + min + ' 分 ' + String(left % 60).padStart(2, '0') + ' 秒 · 使用一次即失效';
        }
        function lock(value) {
            busy = value;
            applyButtons();
        }
        function applyButtons() {
            buttons.forEach(function(b) { b.disabled = !!busy; });
            if (!current || busy) {
                if (!current) buttons.forEach(function(b) { b.disabled = b !== update; });
                if (copyCode) copyCode.disabled = !latestCode || !!busy;
                deviceButtons.forEach(function(b) { b.disabled = true; });
                return;
            }
            enable.disabled = current.enabled && current.listener;
            disable.disabled = !current.enabled;
            enableLan.disabled = !current.enabled || current.lan_enabled;
            disableLan.disabled = !current.lan_enabled;
            pair.disabled = !current.listener;
            revoke.disabled = !(Number(current.paired) > 0);
            deviceButtons.forEach(function(b) { b.disabled = false; });
            if (copyCode) copyCode.disabled = !latestCode;
        }
        function renderDevices(list) {
            deviceButtons = [];
            deviceList.replaceChildren();
            if (!Array.isArray(list) || !list.length) {
                deviceList.appendChild(E('div', { 'class': 'tvg-empty' },
                    '还没有已授权的家长设备。生成一次性配对码后，可在手机上完成配对。'));
                return;
            }
            list.forEach(function(d) {
                var id = String(d.id || '');
                if (!/^[0-9a-f]{16}$/.test(id)) return;
                var title = String(d.name || '浏览器');
                var meta = '配对时间：' + dateText(d.paired_at) + ' · 设备标识：' + id;
                var expiry = Number(d.expires) === 0 ? '长期有效 · 可随时撤销' :
                    '到期：' + dateText(d.expires);
                var cancel = button('撤销此设备', function() {
                    return run('revoke-device', '确认撤销「' + title + '」的遥控授权？此设备需要重新配对才能使用。', [id]);
                }, 'is-danger is-small');
                deviceButtons.push(cancel);
                deviceList.appendChild(E('div', { 'class': 'tvg-device' }, [
                    E('div', {}, [
                        E('div', { 'class': 'tvg-device-name' }, title),
                        E('div', { 'class': 'tvg-device-meta' }, meta),
                        E('div', { 'class': 'tvg-device-meta' }, expiry)
                    ]),
                    cancel
                ]));
            });
            if (!deviceButtons.length) {
                deviceList.appendChild(E('div', { 'class': 'tvg-empty' }, '没有可显示的设备记录。'));
            }
        }
        function renderState(s) {
            if (!s) {
                current = null;
                service.value.textContent = '读取失败';
                service.note.textContent = '请检查 LuCI 管理权限';
                serviceBadge.textContent = '无法确认';
                home.value.textContent = '未知';
                home.note.textContent = '无法读取网络状态';
                devices.value.textContent = '—';
                devices.note.textContent = '暂不能读取设备';
                lanAddress.style.display = 'none';
                renderDevices([]);
                applyButtons();
                report('读取失败。请确认 N1 已联网并具有 TVGuard 管理权限。', 'error');
                return;
            }
            current = s;
            var ready = !!s.enabled && !!s.listener;
            service.value.textContent = ready ? '运行正常' : (s.enabled ? '服务异常' : '服务已关闭');
            service.note.textContent = ready ? '独立 HTTP 已就绪' : '不会影响原有电视计时与断网';
            serviceBadge.textContent = ready ? '可用' : '未就绪';
            serviceBadge.className = 'tvg-pill ' + (ready ? 'is-good' : (s.enabled ? 'is-warn' : ''));
            home.value.textContent = s.lan_enabled ? '已开放' : '未开放';
            home.note.textContent = s.lan_enabled ? '仅家中可信网络 · HTTP' : '外网 Tunnel 不受此开关影响';
            lanBadge.textContent = s.lan_enabled ? '内网可用' : '未开启';
            lanBadge.className = 'tvg-pill ' + (s.lan_enabled ? 'is-good' : '');
            devices.value.textContent = String(Number(s.paired) || 0) + ' / 4 台';
            devices.note.textContent = '授权长期有效，支持单台撤销';
            serviceMessage.textContent = ready ? '本机 API 127.0.0.1:18765 已就绪。' :
                '这是独立遥控服务，启停不会修改儿童模式或正式控制开关。';
            lanMessage.textContent = s.lan_enabled ?
                '家中 HTTP 直连已启用；浏览器与手机仍需完成设备配对。' :
                '家中 HTTP 尚未开放。打开后可从同一局域网的手机访问。';
            var url = s.lan_enabled ? validLocalUrl(s.lan_url) : '';
            if (url) {
                lanUrl.href = url;
                lanUrl.textContent = url;
                lanAddress.style.display = '';
            } else {
                lanUrl.removeAttribute('href');
                lanUrl.textContent = '';
                lanAddress.style.display = 'none';
            }
            renderDevices(s.devices);
            applyButtons();
        }
        function refresh() {
            return exec(READ, ['status']).then(function(s) {
                renderState(JSON.parse(s));
                report('状态已更新');
            }).catch(function(err) {
                renderState(null);
                report('读取失败：' + String(err.message || err), 'error');
            });
        }
        function run(name, confirmation, args) {
            if (busy) return;
            if (confirmation && !window.confirm(confirmation)) return;
            lock(true);
            report('操作进行中…');
            var actionCompleted = false;
            return exec(MANAGE, [name].concat(args || [])).then(function(result) {
                actionCompleted = true;
                if (name === 'pair') {
                    latestCode = result.replace(/^.*：/, '').trim();
                    if (!/^[0-9a-f]{32}$/.test(latestCode)) throw new Error('配对码格式异常');
                    issueDeadline = Date.now() + 5 * 60 * 1000;
                    pairCode.textContent = latestCode;
                    pairCode.className = 'tvg-code';
                    tick();
                    copyCode.disabled = false;
                    report('一次性配对码已生成，请在手机上输入');
                } else {
                    report(result || '操作已完成');
                    if (name === 'revoke-all') {
                        latestCode = ''; issueDeadline = 0;
                        pairCode.textContent = '已有授权已撤销';
                        copyCode.disabled = true;
                    }
                }
                return exec(READ, ['status']).then(function(text) { renderState(JSON.parse(text)); });
            }).catch(function(err) {
                report((actionCompleted ? '操作已执行，但状态刷新失败：' : '操作失败：') +
                    String(err.message || err), 'error');
            }).finally(function() { lock(false); });
        }

        enable = button('启用遥控服务', function() { return run('enable'); }, 'is-primary');
        disable = button('停止服务', function() {
            return run('disable', '停止遥控服务后，手机暂时无法控制电视；当前儿童模式和正式断网规则不变。确定停止？');
        }, 'is-danger');
        enableLan = button('开启家中直连', function() {
            return run('enable-lan', '家中 HTTP 不加密，仅适合可信家庭 Wi-Fi。确认开放局域网入口吗？');
        }, 'is-primary');
        disableLan = button('关闭局域网入口', function() {
            return run('disable-lan', '关闭后手机将无法通过内网 IP 访问，但 Cloudflare Tunnel 的本机回源仍保留。确定关闭？');
        }, 'is-danger');
        pair = button('生成 5 分钟配对码', function() { return run('pair'); }, 'is-primary');
        revoke = button('撤销全部设备', function() {
            return run('revoke-all', '确认撤销所有家长设备？所有设备均需重新配对。');
        }, 'is-danger');
        update = button('刷新状态', refresh);
        copyCode = button('复制配对码', function() {
            return copyText(latestCode);
        }, 'is-small');
        buttons = [enable, disable, enableLan, disableLan, pair, revoke, update];

        root = E('div', { 'class': 'tvg-console' }, [
            E('link', { 'rel': 'stylesheet', 'href': STYLE + '?v=0.1.16-r15' }),
            E('header', { 'class': 'tvg-header' }, [
                E('div', {}, [
                    E('div', { 'class': 'tvg-eyebrow' }, 'TVGUARD / PARENT ACCESS'),
                    E('h2', { 'class': 'tvg-title' }, '家长遥控'),
                    E('p', { 'class': 'tvg-intro' }, '管理家长遥控服务、家中访问与配对设备，不影响现有的观看计时与断网策略。')
                ]),
                update
            ]),
            E('div', { 'class': 'tvg-status-grid' }, [service.node, home.node, devices.node]),
            E('div', { 'class': 'tvg-layout' }, [
                E('section', { 'class': 'tvg-card' }, [
                    block('遥控服务', serviceBadge),
                    E('p', { 'class': 'tvg-card-desc' }, '手机控制电视模式与时间奖励所需的独立服务。'),
                    E('div', { 'class': 'tvg-controls' }, [enable, disable]),
                    serviceMessage,
                    E('details', { 'class': 'tvg-details' }, [
                        E('summary', {}, '技术信息'),
                        E('div', { 'class': 'tvg-details-body' },
                            '本机监听 127.0.0.1:18765；与 LuCI 管理端口分离。')
                    ])
                ]),
                E('section', { 'class': 'tvg-card' }, [
                    block('家中 Wi-Fi 直连', lanBadge),
                    E('p', { 'class': 'tvg-card-desc' }, '在家通过局域网访问，不需要额外配置 HTTPS 证书。'),
                    lanAddress,
                    E('div', { 'class': 'tvg-controls' }, [enableLan, disableLan]),
                    lanMessage,
                    E('details', { 'class': 'tvg-details' }, [
                        E('summary', {}, '关于局域网 HTTP'),
                        E('div', { 'class': 'tvg-details-body' },
                            '仅绑定 br-lan 的私有 IPv4:18765，不对公网开放端口。HTTP 数据未经加密，配对码和 Cookie 可能被同网段攻击者截获，仅限可信家庭网络使用。')
                    ])
                ]),
                E('section', { 'class': 'tvg-card tvg-card-wide' }, [
                    block('家长设备配对', pill('一次性 · 5 分钟')),
                    E('p', { 'class': 'tvg-card-desc' },
                        '在手机家长遥控器中输入配对码。最多授权 4 台设备，授权长期有效，直到主动撤销。'),
                    E('div', { 'class': 'tvg-controls' }, [pair]),
                    E('div', { 'class': 'tvg-code-row' }, [pairCode, copyCode]),
                    pairTimer,
                    E('div', { 'class': 'tvg-help' },
                        '配对码仅显示本次生成的值，使用一次后即失效。使用无痕模式或清理浏览器 Cookie 后，手机可能需要重新配对。')
                ]),
                E('section', { 'class': 'tvg-card tvg-card-wide' }, [
                    block('已授权的家长设备', pill('最多 4 台')),
                    deviceList,
                    E('div', { 'class': 'tvg-controls' }, [revoke])
                ])
            ]),
            errorText,
            E('div', { 'class': 'tvg-safety' },
                '外网入口 tv.rqqr.de 仅指向独立家长遥控服务。当前未启用 Cloudflare Access，公网访问需要 TVGuard 设备配对；切勿发布 LuCI 或 SSH。'),
            E('p', { 'class': 'tvg-footer' },
                '本页面只管理家长设备授权。观看时长、奖励和儿童模式仍按已验收的 TVGuard 控制规则执行。')
        ]);
        renderState(initial);
        // 只更新配对码的视觉倒计时，不向 N1 轮询或增加存储写入。
        if (typeof window !== 'undefined' && window.setInterval) {
            timer = window.setInterval(function() {
                if (typeof document !== 'undefined' && document.body &&
                    !document.body.contains(root)) {
                    window.clearInterval(timer);
                    return;
                }
                tick();
            }, 1000);
        }
        return root;
    }
});
