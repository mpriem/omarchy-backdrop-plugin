const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
function library(name) {
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(path.join(root, name), 'utf8').replace('.pragma library', ''), context);
  return context;
}
const C = library('Config.js'), S = library('Selection.js');
const plain = value => JSON.parse(JSON.stringify(value));
function qmlFunction(file, name, context) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const start = source.indexOf('  function ' + name + '(');
  assert.ok(start >= 0, name);
  let end = source.indexOf('\n  }', start) + 4;
  vm.runInContext(source.slice(start, end), context);
}

test('normalization repairs malformed roots and nested maps, retaining unknown fields', () => {
  for (const input of [[], 'bad', null, 4, {rotate: 'bad', transition: [], pins: 'bad', workspaces: []}]) {
    const cfg = C.normalizeConfig(input);
    assert.equal(C.withMode(cfg, 'pinned').mode, 'pinned');
    assert.equal(C.rotate(cfg).every, '30m');
    assert.equal(C.transition(cfg).ms, 220);
  }
  const cfg = C.normalizeConfig({future: {a: 1}, pins: {t: {DP: 3, HDMI: '/a'}}, workspaces: {t: {'0': '/a', '11': 'random', '2': {}, '3': '/c'}}});
  assert.deepEqual(plain(cfg.pins), {t: {HDMI: '/a'}});
  assert.deepEqual(plain(cfg.workspaces), {t: {'11': 'random', '3': '/c'}});
  assert.deepEqual(plain(cfg.future), {a: 1});
});

test('interval syntax, seconds, minimum and QML overflow boundary', () => {
  for (const [input, expected] of [['45s', 45000], ['30m', 1800000], ['1h30m', 5400000], ['2', 120000], ['1s', 5000], ['1H 30M', 5400000], ['2147483s', 2147483000]]) {
    assert.equal(C.intervalMs(input), expected, input);
  }
  for (const input of ['junk1h??', '-1h', '0', '1h!', '2147484s', '9'.repeat(400), Infinity, {}, '', null]) assert.equal(C.intervalMs(input), null, String(input));
  assert.equal(C.intervalLabel('45s'), '45 s');
  assert.equal(C.intervalLabel('25h30m45s'), '25 h 30 min 45 s');
});

test('operations validate values and preserve unrelated edits from multiple callers', () => {
  let cfg = C.applyOperation({}, {type: 'pin', theme: 't', target: 'DP', value: '/one'});
  cfg = C.applyOperation(cfg, {type: 'transition', key: 'ms', value: 500});
  cfg = C.applyOperation(cfg, {type: 'assign', theme: 't', target: 11, value: 'random'});
  assert.equal(cfg.pins.t.DP, '/one');
  assert.equal(cfg.transition.ms, 500);
  assert.equal(cfg.workspaces.t['11'], 'random');
  for (const target of [0, -1, 1.5, 'junk', 2147483648]) assert.throws(() => C.applyOperation(cfg, {type: 'assign', theme: 't', target, value: '/a'}));
  for (const operation of [{type: 'rotate', key: 'order', value: 'typo'}, {type: 'rotate', key: 'every', value: '-1h'}, {type: 'transition', key: 'style', value: 'typo'}, {type: 'transition', key: 'ms', value: 'bad'}, {type: 'pin', theme: 't', target: 'DP', value: 7}]) assert.throws(() => C.applyOperation(cfg, operation));
});

test('explicit workspace choices work in both assignment policies', () => {
  for (const policy of ['fixed', 'modulo']) {
    assert.equal(S.workspaceImage(['/a', '/b', '/c'], {'1': '/c'}, {}, policy, 1), '/c');
    assert.equal(S.workspaceImage(['/a', '/b'], {'11': 'random'}, {'11': '/b'}, policy, 11), '/b');
    assert.equal(S.workspaceImage(['/a'], {}, {}, policy, 0), '/a');
  }
});

test('rotation preserves identity across reorder/shrink and retires disconnected screens', () => {
  const old = {base: '/b', own: {DP: '/c', HDMI: '/a'}};
  const state = S.reconcile(['/b', '/a'], old, ['DP']);
  assert.equal(state.base, '/b');
  assert.deepEqual(plain(state.own), {});
  for (const scope of ['same', 'different']) assert.equal(S.rotationImage(['/b', '/a'], state, scope, ['DP'], 'DP'), '/b');
  assert.equal(S.rotationImage([], state, 'same', ['DP'], 'DP'), '');
});

test('per-monitor picks take effect for either order and expire on tick', () => {
  for (const order of ['ordered', 'random']) {
    const state = {base: '/a', own: {DP: '/c'}};
    assert.equal(S.rotationImage(['/a', '/b', '/c'], state, 'different', ['DP', 'HDMI'], 'DP'), '/c');
    const next = S.plan(['/a', '/b', '/c'], state, {order, scope: 'different'}, ['DP', 'HDMI'], () => 0);
    assert.notEqual(S.rotationImage(['/a', '/b', '/c'], next, 'different', ['DP', 'HDMI'], 'DP'), '/c');
  }
});

test('renderer rejects a preloaded plan from an earlier generation', () => {
  const context = vm.createContext({images: ['/b'], rotationGeneration: 2, plannedRotate: {generation: 1, state: {base: '/removed', own: {}}}, rotation: {}, instantTargets: {}, planRotate: () => ({generation: 2, state: {base: '/b', own: {}}})});
  qmlFunction('Background.qml', 'rotateStep', context);
  context.rotateStep();
  assert.equal(context.rotation.base, '/b');
  assert.equal(context.plannedRotate, null);
});

test('picker target cursor uses actual values and stale activation is harmless', () => {
  const context = vm.createContext({Config: C, mode: 'workspace', workspaceAssign: 'fixed', rotate: {order: 'ordered', scope: 'same'}, transition: {style: 'fade'}, screenOptions: [], workspaceOptions: [{value: '1'}, {value: '11'}], editWorkspace: '11', editScreen: '', pickerRows: [], targetValue: '', cursorActive: true, selectedIndex: 10, focusSection: 'target', section: () => ({n: 2})});
  qmlFunction('Panel.qml', 'homeIndex', context);
  qmlFunction('Panel.qml', 'activateCursor', context);
  assert.equal(context.homeIndex('target'), 1);
  assert.doesNotThrow(() => context.activateCursor());
});

test('ordered per-monitor selections retain identity when the pool is reordered', () => {
  const screens = ['DP', 'HDMI'];
  const before = {base: '/a', own: {}};
  const state = S.reconcile(['/c', '/a', '/b'], before, screens, ['/a', '/b', '/c'], screens, 'different');
  assert.equal(S.rotationImage(['/c', '/a', '/b'], state, 'different', screens, 'DP'), '/a');
  assert.equal(S.rotationImage(['/c', '/a', '/b'], state, 'different', screens, 'HDMI'), '/b');
});
