'use strict';
'require view';
'require form';
'require uci';

return view.extend({
    load: function() {
        return uci.load('tvguard');
    },
    render: function() {
        var m = new form.Map('tvguard', 'TV Guard 设置',
            '请先在观察模式验证计时，再启用正式网络控制。当前版本固定已验证的电视 IP/接口，避免旧规则残留；不要在页面中修改它们。');
        var s = m.section(form.NamedSection, 'main', 'tvguard', '基础配置');
        s.addremove = false;
        s.anonymous = true;
        var o;
        o = s.option(form.DummyValue, 'ip', '电视 IPv4 地址（只读）');
        o = s.option(form.DummyValue, 'interface', '电视流量进入 N1 的接口（只读）');
        o = s.option(form.Value, 'weekday_minutes', '工作日基础额度（分钟）');
        o.datatype = 'range(0,600)';
        o.rmempty = false;
        o = s.option(form.Value, 'weekend_minutes', '周末基础额度（分钟）');
        o.datatype = 'range(0,600)';
        o.rmempty = false;
        o = s.option(form.Value, 'max_bonus_minutes', '每天最大奖励（分钟）');
        o.datatype = 'range(0,600)';
        o.rmempty = false;
        o = s.option(form.Value, 'allow_start', '允许开始时间（HH:MM）');
        o.rmempty = false;
        o = s.option(form.Value, 'allow_end', '允许结束时间（HH:MM）');
        o.rmempty = false;
        o = s.option(form.Value, 'silence_seconds', '网络静默确认时间（秒）');
        o.datatype = 'range(10,600)';
        o.rmempty = false;
        return m.render();
    }
});
