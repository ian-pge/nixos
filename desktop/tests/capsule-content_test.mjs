// Exercise the production opacity calculations without creating Bar's services.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../bar/CentralCapsule.qml', import.meta.url), 'utf8');
const motion = vm.createContext({});
vm.runInContext(readFileSync(new URL('../ui/Morph.js', import.meta.url), 'utf8')
  .replace(/^\.pragma library\s*/, ''), motion);

assert.equal(motion.duration, 220);
assert.equal(motion.minScale, 0.5);
assert.equal(motion.maxScale, 2);

// Each independent axis stays between half and twice the normal size.
for (const [surface, content, expected] of [[180, 300, 0.6], [300, 180, 5 / 3],
    [42, 42, 1], [98, 398, 0.5], [398, 98, 2], [0, 42, 0.5]])
  assert.equal(motion.axisScale(surface, content), expected);
assert.ok(Number.isFinite(motion.axisScale(42, 0)), 'Zero-sized content must not produce an infinite transform');
const contentSize = {width: 100, height: 100};
for (const [x, y, expectedX, expectedY] of [
  [1.08, 1, 1.08, 1], [0.95, 1, 0.95, 1],
  [3, 1, 2, 1], [1, 3, 1, 2],
  [0.5, 1, 0.5, 1], [1, 0.5, 1, 0.5],
  [3, 3, 2, 2], [0.2, 0.2, 0.5, 0.5], [1, 1, 1, 1], [0, 1, 0.5, 1],
  [0.1, 4, 0.5, 2], [4, 0.1, 2, 0.5]
]) {
  const scale = motion.contentScale({width: x * 100, height: y * 100}, contentSize);
  assert.ok(Math.abs(scale.x - expectedX) < 1e-12);
  assert.ok(Math.abs(scale.y - expectedY) < 1e-12);
}
// Both directions use the displayed geometry, with no history or threshold
// jump. Cover very different aspect ratios, including the capsule/chat handoff.
for (const source of [{width: 340, height: 42}, {width: 130, height: 42},
    {width: 340, height: 398}, {width: 1280, height: 900}]) {
  for (const destination of [{width: 180, height: 42}, {width: 340, height: 398}, {width: 1280, height: 900}]) {
    for (let frame = 0; frame <= 100; ++frame) {
      const t = frame / 100;
      const surface = {width: source.width + (destination.width - source.width) * t,
        height: source.height + (destination.height - source.height) * t};
      const scale = motion.contentScale(surface, destination);
      assert.ok(scale.x >= 0.5 && scale.x <= 2 && scale.y >= 0.5 && scale.y <= 2);
      assert.equal(scale.x, Math.max(0.5, Math.min(2, surface.width / destination.width)));
      assert.equal(scale.y, Math.max(0.5, Math.min(2, surface.height / destination.height)));
      const reversedSurface = {width: destination.width + (source.width - destination.width) * (1 - t),
        height: destination.height + (source.height - destination.height) * (1 - t)};
      const reversed = motion.contentScale(reversedSurface, destination);
      assert.ok(Math.abs(scale.x - reversed.x) < 1e-12 && Math.abs(scale.y - reversed.y) < 1e-12);
    }
  }
}
for (const threshold of [0.5, 2]) {
  const before = motion.contentScale({width: (threshold - 1e-8) * 100, height: 100}, contentSize);
  const after = motion.contentScale({width: (threshold + 1e-8) * 100, height: 100}, contentSize);
  assert.ok(Math.abs(before.x - after.x) < 3e-8 && Math.abs(before.y - after.y) < 3e-8);
}
const zeroSize = motion.contentScale({width: 42, height: 42}, {width: 0, height: 0});
assert.ok(Number.isFinite(zeroSize.x) && Number.isFinite(zeroSize.y));
console.log('PASS: 220ms motion, independent 50–200% axis limits, continuous and reversible zoom');
const state = vm.createContext({
  targetMode: 'workspaces', visualSourceMode: 'workspaces', visualTargetMode: 'workspaces',
  transitionProgress: 1, startOpacities: {workspaces: 1},
  messengerHost: {originContentOpacity: 0}, chatHandoff: false, Morph: motion
});
state.root = state;
for (const name of ['contentOpacity']) {
  const method = source.match(new RegExp(`^  function ${name}\\([^]*?^  }`, 'm'));
  assert.ok(method, `Missing Bar opacity method ${name}`);
  vm.runInContext(method[0], state);
}

// The new target is known before the coalesced transition callback. No cached
// workspace pixels may become visible as the OSD container starts to appear.
for (const mode of ['volume', 'brightness', 'notification']) {
  for (const chatOpacity of [0, 0.2, 1]) {
    state.messengerHost.originContentOpacity = chatOpacity;
    state.targetMode = mode;
    state.visualTargetMode = 'workspaces';
    state.visualSourceMode = 'workspaces';
    state.startOpacities = {workspaces: 1};
    state.transitionProgress = 1;
    assert.equal(state.contentOpacity('workspaces'), 0, `${mode}: before transition callback`);
    state.visualTargetMode = mode;
    for (const frame of [0, 0.1, 0.25, 0.48, 0.6, 0.8, 1]) {
      state.transitionProgress = frame;
      assert.equal(state.contentOpacity('workspaces'), 0, `${mode}: frame ${frame}`);
      const opacity = state.contentOpacity(mode);
      assert.ok(opacity >= 0 && opacity <= 1);
    }
    assert.equal(state.contentOpacity(mode), 1);
  }
  // OSD expiration must not reveal the workspace target through its fading
  // container while the chat continues occupying the central capsule.
  state.messengerHost.originContentOpacity = 0;
  state.targetMode = 'workspaces';
  state.visualSourceMode = mode;
  state.visualTargetMode = 'workspaces';
  state.startOpacities = {[mode]: 1, workspaces: 0};
  for (const frame of [0, 0.2, 0.5, 0.8, 1]) {
    state.transitionProgress = frame;
    assert.equal(state.contentOpacity('workspaces'), 0, `${mode}: expiration ${frame}`);
  }
}

// Switching from one OSD to the other (even with a stale workspace weight)
// must not make the third, unrelated mode participate in the crossfade.
state.targetMode = 'brightness'; state.visualTargetMode = 'brightness';
state.visualSourceMode = 'volume'; state.startOpacities = {volume: 0.7, workspaces: 0.3};
state.transitionProgress = 0.2;
assert.equal(state.contentOpacity('workspaces'), 0);

// The genuine capsule/chat handoff still returns the workspace content.
state.targetMode = state.visualTargetMode = 'workspaces';
state.startOpacities = {workspaces: 1}; state.transitionProgress = 1;
for (const originOpacity of [0.1, 0.5, 1]) {
  state.messengerHost.originContentOpacity = originOpacity;
  assert.equal(state.contentOpacity('workspaces'), 1);
}

// Preserve the actual outgoing widget while its surface becomes the chat.
state.chatHandoff = true;
state.messengerHost.active = true;
state.chatSourceOpacities = {calendar: 1};
state.messengerHost.originContentOpacity = 0.5;
assert.equal(state.contentOpacity('calendar'), 1);
assert.equal(state.contentOpacity('workspaces'), 0);
state.messengerHost.originContentOpacity = 0;
assert.equal(state.contentOpacity('calendar'), 0);
state.chatSourceOpacities = {workspaces: 1};
assert.equal(state.contentOpacity('workspaces'), 0);
console.log('PASS: volume/brightness/notification entry, interruption and expiry never flash hidden workspaces; chat handoff still restores them');
