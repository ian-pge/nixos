// Exercise the production opacity calculations without creating Bar's services.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../bar/CentralCapsule.qml', import.meta.url), 'utf8');
const state = vm.createContext({
  targetMode: 'workspaces', visualSourceMode: 'workspaces', visualTargetMode: 'workspaces',
  transitionProgress: 1, startOpacities: {workspaces: 1},
  messengerHost: {originContentOpacity: 0}
});
state.root = state;
for (const name of ['clamp01', 'smoothSegment', 'contentOpacity']) {
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
console.log('PASS: volume/brightness/notification entry, interruption and expiry never flash hidden workspaces; chat handoff still restores them');
