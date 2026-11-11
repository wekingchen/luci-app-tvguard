'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');

const menu = JSON.parse(fs.readFileSync(
    'root/usr/share/luci/menu.d/luci-app-tvguard.json', 'utf8'
));

const root = menu['admin/services/tvguard'];
const overview = menu['admin/services/tvguard/overview'];
const settings = menu['admin/services/tvguard/settings'];

assert.ok(root, 'missing TV Guard root menu');
assert.equal(root.action.type, 'firstchild');
assert.deepEqual(root.depends.acl, ['luci-app-tvguard']);

assert.ok(overview, 'missing overview tab');
assert.equal(overview.title, '概览');
assert.equal(overview.action.type, 'view');
assert.equal(overview.action.path, 'tvguard/overview');

assert.ok(settings, 'missing settings tab');
assert.equal(settings.title, '设置');
assert.equal(settings.action.type, 'view');
assert.equal(settings.action.path, 'tvguard/settings');

assert.ok(overview.order < settings.order, 'overview must be the default first tab');

const directRootView = root.action.type === 'view' && root.action.path === 'tvguard/overview';
assert.equal(directRootView, false, 'root must redirect to first child to avoid a lone settings tab');

console.log('PASS: LuCI menu exposes explicit overview/settings tabs with overview as default');
