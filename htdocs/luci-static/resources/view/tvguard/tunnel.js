'use strict';
'require view';
'require fs';
'require ui';

// 敏感 Token 只在本地 LuCI 管理会话中提交，绝不写入 UCI 或调用参数。
var READ = '/usr/libexec/tvguard-tunnel-read';
var MANAGE = '/usr/libexec/tvguard-tunnel-manage';
var PENDING = '/tmp/tvguard-tunnel/token.pending';

function exec(script, args) {
    return fs.exec(script, args).then(function(r) {
        if (r.code)
            throw new Error(String(r.stderr || r.stdout || '执行失败').trim());
        return String(r.stdout || '').trim();
    });
}
function notice(message, level) {
    ui.addNotification(null, E('p', {}, message), level || 'info');
}
function actionButton(label, kind, onClick) {
    return E('button', {
        'type': 'button',
        'class': 'btn ' + (kind === 'danger' ? 'cbi-button-negative' : 'cbi-button-action'),
        'style': 'min-height:38px;min-width:115px;',
        'click': onClick
    }, label);
}

return view.extend({
    load: function() {
        return exec(READ, ['status']).then(function(text) {
            return JSON.parse(text);
        }).catch(function() {
            return null;
        });
    },

    render: function(initial) {
        var input = E('input', {
            'type': 'password',
            'class': 'cbi-input-text',
            'autocomplete': 'new-password',
            'spellcheck': 'false',
            'placeholder': '粘贴新建 Tunnel 的 Token',
            'style': 'width:100%;max-width:620px;'
        });
        var summary = E('strong', {}, '正在读取状态…');
        var details = E('div', { 'class': 'description', 'style': 'margin-top:6px;line-height:1.7;' }, '');
        var logs = E('pre', {
            'style': 'white-space:pre-wrap;overflow-wrap:anywhere;overflow:auto;max-height:360px;' +
                'padding:12px;border-radius:8px;background:rgba(127,127,127,.10);' +
                'font-size:12px;line-height:1.55;'
        }, '尚未加载日志');
        var busy = false;
        var buttons = [];

        function lockUI(value) {
            busy = value;
            buttons.forEach(function(b) { b.disabled = value; });
        }
        function applyState(s) {
            if (!s) {
                summary.textContent = '状态读取失败';
                details.textContent = '请检查 N1、rpcd 服务及当前账号的 LuCI 授权。';
                return;
            }
            var names = {
                running: '容器运行中（尚不代表 Tunnel 已连通）',
                exited: '容器已停止', created: '容器已创建',
                restarting: '正在重新连接', paused: '容器已暂停',
                dead: '容器异常', missing: '尚未创建容器',
                foreign: '发现同名非 TVGuard 容器，拒绝接管',
                unavailable: 'Docker 服务不可用',
                unknown: '状态未知'
            };
            summary.textContent = names[s.container] || '状态未知';
            details.textContent =
                'Token：' + (s.configured ? '已保存（不回显）' : '尚未配置') +
                '　·　持久分区：' + (s.storage_ready ? '正常' : '未挂载 / 只读') +
                '　·　Docker：' + (s.docker_ready ? '正常' : '不可用') +
                '　·　镜像：' + (s.image_present ? '已安装' : '未安装') +
                '　·　Metrics：' + (s.metrics_local ? '仅本机监听' : '需安全重建');
        }
        function refresh() {
            return exec(READ, ['status']).then(function(text) {
                applyState(JSON.parse(text));
            }).catch(function(err) {
                applyState(null);
                notice('读取 Tunnel 状态失败：' + String(err.message || err), 'error');
            });
        }
        function refreshLogs() {
            logs.textContent = '正在读取日志…';
            return exec(READ, ['logs']).then(function(text) {
                logs.textContent = text || '容器暂无日志';
            }).catch(function(err) {
                logs.textContent = '日志暂不可用：' + String(err.message || err);
            });
        }
        function runAction(name, confirmText) {
            if (busy)
                return;
            if (confirmText && !window.confirm(confirmText))
                return;
            lockUI(true);
            return exec(MANAGE, [name]).then(function(msg) {
                notice(msg);
                return refresh();
            }).then(refreshLogs).catch(function(err) {
                notice(String(err.message || err), 'error');
                return refresh();
            }).finally(function() {
                lockUI(false);
            });
        }
        function saveToken() {
            if (busy)
                return;
            var value = String(input.value || '').trim();
            if (!/^[A-Za-z0-9_./+=-]{64,8192}$/.test(value)) {
                notice('Token 应为 Cloudflare 提供的长字符串，不允许换行或其他特殊字符。', 'error');
                return;
            }
            if (!window.confirm('保存或更换 Token？若容器正在运行，将自动重启该容器。'))
                return;
            lockUI(true);
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
                input.value = '';
                value = '';
                notice(msg);
                return refresh();
            }).then(refreshLogs).catch(function(err) {
                notice('保存失败：' + String(err.message || err), 'error');
                return refresh();
            }).finally(function() {
                input.value = '';
                value = '';
                lockUI(false);
            });
        }

        var save = actionButton('保存 / 更换 Token', 'normal', saveToken);
        var start = actionButton('创建并启动 / 启动', 'normal', function() {
            return runAction('start');
        });
        var restart = actionButton('重启', 'normal', function() {
            return runAction('restart');
        });
        var rebuild = actionButton('安全重建（限制 Metrics）', 'normal', function() {
            return runAction('rebuild', '重建 TVGuard Tunnel 会短暂断开连接，失败时尝试恢复旧容器。确认继续？');
        });
        var stop = actionButton('停止', 'danger', function() {
            return runAction('stop', '停止 TVGuard Tunnel 后，外网访问将中断。继续吗？');
        });
        var update = actionButton('刷新状态', 'normal', refresh);
        var logButton = actionButton('刷新日志', 'normal', refreshLogs);
        buttons = [save, start, restart, rebuild, stop, update, logButton];

        var root = E('div', {'style':'max-width:930px;margin:0 auto;padding-bottom:18px'}, [
            E('h2', {}, 'TV Guard · 远程访问'),
            E('p', {'class':'description'},
                '单独管理 TVGuard 的 cloudflared Docker 容器；不会操作 Vaultwarden、ntfy 或 TVGuard 的电视计时与防火墙规则。'),
            E('section', {'class':'cbi-section'}, [
                E('h3', {}, 'Cloudflare Tunnel · 配置'),
                E('p', {'class':'description'}, [
                    '先在 ', E('a', {
                        'href':'https://one.dash.cloudflare.com/',
                        'target':'_blank', 'rel':'noopener noreferrer'
                    }, 'Cloudflare Zero Trust'), ' 创建 remotely-managed Tunnel，复制其中的 Token。'
                ]),
                E('div', {'style':'margin:12px 0'}, input),
                save,
                E('p', {'class':'description', 'style':'margin-top:10px;line-height:1.6'},
                    'Token 保存到 N1 持久 XFS 分区的 root 限权文件，不进入 UCI、容器环境变量或 Docker 命令参数；需要已存在的 cloudflare/cloudflared:latest 镜像（版本至少 2025.4.0）。')
            ]),
            E('section', {'class':'cbi-section'}, [
                E('h3', {}, '容器状态与操作'),
                E('div', {'style':'margin-bottom:10px'}, [summary, details]),
                E('div', {'style':'display:flex;gap:9px;flex-wrap:wrap;align-items:center'}, [
                    start, restart, rebuild, stop, update
                ]),
                E('p', {'class':'description','style':'margin-top:10px;line-height:1.6'},
                    '使用固定容器名 tvguard-cloudflared；只有本模块创建并带有专属标签的容器可被操作。容器运行中不代表 Cloudflare 已连通，请查看日志及 Cloudflare 后台确认。')
            ]),
            E('section', {'class':'cbi-section'}, [
                E('div', {'style':'display:flex;align-items:center;gap:12px;flex-wrap:wrap'}, [
                    E('h3', {'style':'margin:0'}, '最近运行日志'),
                    logButton
                ]),
                logs,
                E('p', {'class':'description'}, '仅查询专用容器最近 60 行，最多显示 16 KiB。Docker 自动轮转日志，每个文件 2 MB、保留 3 个。')
            ]),
            E('p', {'class':'description'},
                '安全提醒：在 TVGuard 家长控制面板与独立鉴权 API 完成前，不要在 Tunnel 中发布 LuCI 或 RPCD 的外网路由。')
        ]);
        applyState(initial);
        if (initial && initial.container !== 'missing' && initial.container !== 'unavailable')
            refreshLogs();
        return root;
    }
});
