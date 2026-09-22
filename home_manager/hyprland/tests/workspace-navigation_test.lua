-- Run with the generated Home Manager hyprland.lua path (or /dev/stdin).
-- All compositor calls are mocked: this never switches the real desktop.
local bindings, assignments, dispatches = {}, {}, {}
local monitors, focused, regularWorkspace, specialWorkspace
local function dispatcher(path)
  return setmetatable({}, {
    __index = function(_, key) return dispatcher(path .. "." .. key) end,
    __call = function(_, ...) return { path = path, args = { ... } } end,
  })
end

hl = setmetatable({
  dsp = dispatcher("hl.dsp"),
  bind = function(key, action, options)
    if key == "SUPER + ALT + H" or key == "SUPER + ALT + L" then
      assert(not bindings[key], "duplicate workspace shortcut: " .. key)
      assert(type(action) == "function", "workspace must be read on key press")
      assert(not options or not options.release, "switch on press, not release")
      bindings[key] = action
    end
  end,
  workspace_rule = function(rule)
    local id = tonumber(rule.workspace)
    if id then assignments[id] = rule.monitor end
  end,
  get_active_workspace = function() return regularWorkspace end,
  get_active_special_workspace = function() return specialWorkspace end,
  exec_cmd = function() error("workspace cycling must not launch a subprocess") end,
  dispatch = function(action)
    assert(action.path == "hl.dsp.focus", "must focus, not move a workspace/window")
    local id = action.args[1].workspace
    assert(type(id) == "number" and id >= 1 and id <= 8, "target outside bar slots")
    dispatches[#dispatches + 1] = id
    local destination = assignments[id]
    if not monitors[destination] then destination = focused end
    focused = destination
    monitors[destination].active = id
    regularWorkspace = { id = id }
  end,
  define_submap = function(_, callback) callback() end,
}, { __index = function() return function() end end })

assert(loadfile(assert(arg[1], "provide the generated Hyprland config")))()
assert(#dispatches == 0, "loading the config must not change workspace")
local previous = assert(bindings["SUPER + ALT + H"])
local nextWorkspace = assert(bindings["SUPER + ALT + L"])
for id = 1, 8 do
  assert(assignments[id] == (id <= 4 and "DP-2" or "eDP-1"))
end

local function press(action, id, monitor)
  local count = #dispatches
  action()
  assert(#dispatches == count + 1, "each press must dispatch exactly once")
  assert(dispatches[#dispatches] == id, "unexpected workspace: " .. dispatches[#dispatches])
  assert(focused == monitor, "wrong destination monitor")
end

-- Two screens: visit all eight workspaces, including empty ones, in both directions.
monitors = { ["DP-2"] = { active = 1 }, ["eDP-1"] = { active = 5 } }
focused, regularWorkspace = "DP-2", { id = 1 }
for _ = 1, 2 do
  for _, id in ipairs({ 2, 3, 4, 5, 6, 7, 8, 1 }) do
    press(nextWorkspace, id, id <= 4 and "DP-2" or "eDP-1")
  end
  for _, id in ipairs({ 8, 7, 6, 5, 4, 3, 2, 1 }) do
    press(previous, id, id <= 4 and "DP-2" or "eDP-1")
  end
end

-- Crossing screens still focuses the destination if it already shows that workspace.
focused, regularWorkspace = "DP-2", { id = 4 }
monitors["DP-2"].active, monitors["eDP-1"].active = 4, 5
press(nextWorkspace, 5, "eDP-1")
assert(monitors["DP-2"].active == 4, "must preserve the other screen's workspace")
press(previous, 4, "DP-2")
assert(monitors["eDP-1"].active == 5)

-- One screen: the same loop works when the external output is disconnected.
monitors, focused, regularWorkspace = { ["eDP-1"] = { active = 1 } }, "eDP-1", { id = 1 }
for _, id in ipairs({ 2, 3, 4, 5, 6, 7, 8, 1 }) do press(nextWorkspace, id, "eDP-1") end
for _, id in ipairs({ 8, 7, 6, 5, 4, 3, 2, 1 }) do press(previous, id, "eDP-1") end

-- A special workspace is not part of the loop; use the underlying normal workspace.
specialWorkspace, regularWorkspace = { id = -98 }, { id = 5 }
press(nextWorkspace, 6, "eDP-1")
regularWorkspace = { id = 5 }
press(previous, 4, "eDP-1")
specialWorkspace = nil

-- Recover from old out-of-range/named workspaces without opening another hidden slot.
for _, id in ipairs({ 9, 100, -1337 }) do
  regularWorkspace = { id = id }
  press(nextWorkspace, 1, "eDP-1")
  regularWorkspace = { id = id }
  press(previous, 8, "eDP-1")
end

regularWorkspace = nil
local count = #dispatches
nextWorkspace()
previous()
assert(#dispatches == count, "no active workspace must be a harmless no-op")
print("PASS: global workspace cycle, 1/8 wrap, two/one screens, special and out-of-range workspaces")
