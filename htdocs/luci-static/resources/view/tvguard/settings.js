'use strict';
'require view';
'require form';
'require uci';

function validateTime(section_id, value) {
    var m = String(value || '').match(/^([01]\d|2[0-3]):([0-5]\d)$/);
    return m ? true : '请输入 24 小时制时间，例如 08:00 或 21:30';
}

return view.extend({
    load: function() {
        return uci.load('tvguard');
    },

    render: function() {
        var m = new form.Map(
            'tvguard',
            'TV Guard · 时间规则',
            '这里仅配置日常时间规则。正式网络控制和实验回程观测属于高风险功能，不在普通设置页提供开关。'
        );

        var quota = m.section(form.NamedSection, 'main', 'tvguard', '每日额度');
        quota.addremove = false;
        quota.anonymous = true;
        quota.description = '分别设置工作日和周末的儿童基础额度；家长临时奖励会在当天额度上追加。';

        var o = quota.option(form.Value, 'weekday_minutes', '工作日基础额度');
        o.datatype = 'range(0,600)';
        o.rmempty = false;
        o.description = '周一至周五每天可用的基础分钟数。设为 0 表示当天没有基础额度。';
        o.placeholder = '60';
        o.suffix = ' 分钟';

        o = quota.option(form.Value, 'weekend_minutes', '周末基础额度');
        o.datatype = 'range(0,600)';
        o.rmempty = false;
        o.description = '周六、周日每天可用的基础分钟数。';
        o.placeholder = '120';
        o.suffix = ' 分钟';

        o = quota.option(form.Value, 'max_bonus_minutes', '每天最大奖励');
        o.datatype = 'range(0,600)';
        o.rmempty = false;
        o.description = '限制当天通过“+15 / +30 / +60 分钟”累计追加的总量，防止误操作无限增加。';
        o.placeholder = '120';
        o.suffix = ' 分钟';

        var schedule = m.section(form.NamedSection, 'main', 'tvguard', '可使用时段');
        schedule.addremove = false;
        schedule.anonymous = true;
        schedule.description = '儿童模式下，只有处于允许时段并且额度未用完时才满足“可用”条件。观察模式只记录判断结果，不会断网。';

        o = schedule.option(form.Value, 'allow_start', '开始时间');
        o.rmempty = false;
        o.placeholder = '08:00';
        o.description = '24 小时制，例如 08:00。';
        o.validate = validateTime;

        o = schedule.option(form.Value, 'allow_end', '结束时间');
        o.rmempty = false;
        o.placeholder = '21:00';
        o.description = '24 小时制，例如 21:00。开始和结束相同表示不限制时间段。支持跨午夜，例如 20:00 → 07:00。';
        o.validate = validateTime;

        var detection = m.section(form.NamedSection, 'main', 'tvguard', '计时判断');
        detection.addremove = false;
        detection.anonymous = true;
        detection.description = '这里只调整“多久没有看到电视网络包后，才认为当前会话静默”。它不是屏幕状态识别。';

        o = detection.option(form.Value, 'silence_seconds', '网络静默确认时间');
        o.datatype = 'range(10,600)';
        o.rmempty = false;
        o.placeholder = '60';
        o.suffix = ' 秒';
        o.description = '默认 60 秒。数值越小，停止计时更快，但网络短暂停顿更容易被误判为静默；建议没有明确证据时保持默认。';

        var device = m.section(form.NamedSection, 'main', 'tvguard', '设备绑定（只读）');
        device.addremove = false;
        device.anonymous = true;
        device.description = '当前候选版本固定电视地址和进入接口，避免修改后残留旧防火墙 hook。需要迁移设备时应先完成专门的安全流程。';

        o = device.option(form.DummyValue, 'ip', '电视 IPv4 地址');
        o.description = '当前受管理电视的固定 IPv4。';

        o = device.option(form.DummyValue, 'interface', '进入 N1 的接口');
        o.description = 'TV Guard 只匹配该接口上来自这台电视的 IPv4 流量。';

        return m.render();
    }
});
