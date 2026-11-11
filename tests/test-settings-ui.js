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
const factory = new Function('view', 'form', 'uci', source);
const page = factory(view, form, uci);

(async () => {
    await page.load();
    assert.equal(loaded, true);

    const map = page.render();
    assert.equal(map.title, 'TV Guard · 时间规则');
    assert.match(map.description, /高风险功能/);
    assert.deepEqual(
        map.sections.map(section => section.title),
        ['每日额度', '可使用时段', '计时判断', '每日观看日报 · Bark', '设备绑定（只读）']
    );

    const options = map.sections.flatMap(section => section.options);
    const byName = Object.fromEntries(options.map(option => [option.name, option]));

    for (const name of ['weekday_minutes', 'weekend_minutes', 'max_bonus_minutes', 'allow_start',
                        'allow_end', 'silence_seconds', 'child_name', 'bark_enabled', 'bark_server', 'bark_key', 'bark_daily_time', 'ip', 'interface']) {
        assert.ok(byName[name], 'missing settings field: ' + name);
        assert.ok(byName[name].description.length > 0, 'missing description: ' + name);
    }

    for (const forbidden of ['enforce', 'allow_enforcement', 'observe_reply']) {
        assert.equal(byName[forbidden], undefined,
            'high-risk switch must not appear in ordinary settings: ' + forbidden);
    }

    assert.equal(byName.bark_enabled.type, 'Flag');
    assert.equal(byName.bark_enabled.default, '0');
    assert.equal(byName.bark_key.password, true);
    assert.equal(byName.child_name.validate('main', '小明'), true);
    assert.notEqual(byName.child_name.validate('main', 'A\nB'), true);
    assert.equal(byName.bark_server.validate('main', 'https://api.day.app'), true);
    assert.notEqual(byName.bark_server.validate('main', 'https://example.com/key'), true);
    assert.equal(byName.bark_key.validate('main', 'abcdef1234'), true);
    assert.notEqual(byName.bark_key.validate('main', 'bad/key'), true);
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
