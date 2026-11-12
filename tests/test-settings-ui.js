'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync(
    'htdocs/luci-static/resources/view/tvguard/settings.js', 'utf8'
);

class MockOption {
    constructor(type, name, title) {
        this.type = type;
        this.name = name;
        this.title = title;
        this.description = '';
        this.datatype = null;
        this.rmempty = true;
        this.placeholder = null;
        this.suffix = null;
        this.validate = null;
    }
}

class MockSection {
    constructor(type, sectionId, configType, title) {
        this.type = type;
        this.sectionId = sectionId;
        this.configType = configType;
        this.title = title;
        this.description = '';
        this.options = [];
        this.addremove = true;
        this.anonymous = false;
    }

    option(type, name, title) {
        const option = new MockOption(type, name, title);
        this.options.push(option);
        return option;
    }
}

class MockMap {
    constructor(config, title, description) {
        this.config = config;
        this.title = title;
        this.description = description;
        this.sections = [];
    }

    section(type, sectionId, configType, title) {
        const section = new MockSection(type, sectionId, configType, title);
        this.sections.push(section);
        return section;
    }

    render() {
        return this;
    }
}

const form = {
    Map: MockMap,
    NamedSection: 'NamedSection',
    Value: 'Value',
    Flag: 'Flag',
    Button: 'Button',
    DummyValue: 'DummyValue'
};

let loaded = false;
const uci = {
    load(name) {
        assert.equal(name, 'tvguard');
        loaded = true;
        return Promise.resolve();
    }
};

const view = { extend: value => value };
const notices = [];
const commands = [];
let pushFails = false;
const mockFs = {
    exec(path, args) {
        commands.push([path, args]);
        return Promise.resolve(pushFails ?
            {code: 3, stdout: '', stderr: '今天还没有儿童模式下的观看记录，未发送测试推送。'} :
            {code: 0, stdout: '测试推送已发送：儿童模式累计约20分钟。'});
    }
};
const mockUi = {addNotification(_id, node, type) {notices.push({node, type});}};
const E = (tag, attrs, children) => ({tag, children});
const factory = new Function('view', 'form', 'uci', 'fs', 'ui', 'E', source);
const page = factory(view, form, uci, mockFs, mockUi, E);

(async () => {
    await page.load();
    assert.equal(loaded, true);

    const map = page.render();
    assert.equal(map.title, 'TV Guard · 设置');
    assert.match(map.description, /高风险功能/);
    assert.deepEqual(
        map.sections.map(section => section.title),
        ['每日额度', '可使用时段', '计时判断', '每日观看日报 · Bark', '设备绑定（只读）']
    );

    const options = map.sections.flatMap(section => section.options);
    const byName = Object.fromEntries(options.map(option => [option.name, option]));

    for (const name of ['weekday_minutes', 'weekend_minutes', 'max_bonus_minutes', 'allow_start',
                        'allow_end', 'silence_seconds', 'child_name', 'bark_enabled', 'bark_server', 'bark_key', 'bark_key2', 'bark_daily_time', '_bark_test', 'ip', 'interface']) {
        assert.ok(byName[name], 'missing settings field: ' + name);
        assert.ok(byName[name].description.length > 0, 'missing description: ' + name);
    }

    for (const forbidden of ['enforce', 'allow_enforcement', 'observe_reply']) {
        assert.equal(byName[forbidden], undefined,
            'high-risk switch must not appear in ordinary settings: ' + forbidden);
    }

    assert.equal(byName._bark_test.type, 'Button');
    assert.match(byName._bark_test.description, /先保存并应用/);
    assert.match(byName._bark_test.description, /截至此刻|截止/);
    await byName._bark_test.onclick();
    assert.deepEqual(commands.at(-1), ['/usr/libexec/tvguardctl', ['bark-test']]);
    assert.equal(notices.at(-1).type, 'info');
    pushFails = true;
    await byName._bark_test.onclick();
    assert.equal(notices.at(-1).type, 'error');
    assert.match(notices.at(-1).node.children, /没有儿童模式下的观看记录/);
    assert.equal(byName.bark_enabled.type, 'Flag');
    assert.equal(byName.bark_enabled.default, '0');
    assert.equal(byName.child_name.default, '孩子');
    assert.equal(byName.bark_server.default, 'https://api.day.app');
    assert.equal(byName.bark_daily_time.default, '00:05');
    assert.equal(byName.bark_key.password, true);
    assert.equal(byName.bark_key2.password, true);
    assert.match(byName.bark_key.description, /最多支持两台设备|至少填写一个/);
    assert.match(byName.bark_key2.description, /爸爸和妈妈|第二台/);
    assert.equal(byName.child_name.validate('main', '小明'), true);
    assert.notEqual(byName.child_name.validate('main', 'A\nB'), true);
    assert.equal(byName.bark_server.validate('main', 'https://api.day.app'), true);
    assert.notEqual(byName.bark_server.validate('main', 'https://example.com/key'), true);
    assert.equal(byName.bark_key.validate('main', 'abcdef1234'), true);
    assert.notEqual(byName.bark_key.validate('main', 'bad/key'), true);
    assert.equal(byName.bark_key2.validate('main', 'secondDevice123'), true);
    assert.notEqual(byName.bark_key2.validate('main', 'bad/key2'), true);
    assert.equal(byName.bark_daily_time.validate('main', '00:05'), true);
    assert.notEqual(byName.bark_daily_time.validate('main', '24:00'), true);
    assert.equal(byName.ip.type, 'DummyValue');
    assert.equal(byName.interface.type, 'DummyValue');

    assert.equal(byName.allow_start.validate('main', '08:00'), true);
    assert.equal(byName.allow_end.validate('main', '23:59'), true);
    assert.match(String(byName.allow_start.validate('main', '8:00')), /24 小时制/);
    assert.match(String(byName.allow_end.validate('main', '24:00')), /24 小时制/);
    assert.match(byName.allow_end.description, /开始和结束相同表示不限制/);
    assert.match(byName.silence_seconds.description, /不是屏幕状态识别|网络短暂停顿/);

    console.log('PASS: settings hierarchy, validation, descriptions and high-risk switch isolation');
})().catch(err => {
    console.error(err);
    process.exitCode = 1;
});
