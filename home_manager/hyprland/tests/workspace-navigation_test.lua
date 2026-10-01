-- Generated Home Manager Lua, with all compositor effects confined to this model.
local bindings, rules, hooks, timers, actions = {}, {}, {}, {}, {}
local monitors, workspaces, windows = {}, {}, {}
local focused, focused_window, rule_writes = nil, nil, 0
local function dispatcher(path)
  return setmetatable({}, {
    __index = function(_, key) return dispatcher(path .. "." .. key) end,
    __call = function(_, ...) return {path = path, args = {...}} end,
  })
end
local function workspace(id, monitor)
  if not workspaces[id] then workspaces[id] = {id = id, monitor = monitor} end
  return workspaces[id]
end
local function monitor(name, active)
  local value = {name = name, is_mirror = false}
  function value:set_workspace(options)
    self.active_workspace = assert(workspaces[options.workspace], "destination must exist before selection")
  end
  value.active_workspace = workspace(active, value)
  monitors[name] = value
  return value
end
local function values(map)
  local result = {}
  for _, value in pairs(map) do result[#result + 1] = value end
  return result
end
local external, internal = monitor("DP-2", 1), monitor("eDP-1", 6)
focused = external

hl = setmetatable({
  dsp = dispatcher("hl.dsp"), plugin = {load = function() end},
  bind = function(key, action) bindings[key] = action end,
  on = function(event, callback)
    hooks[event] = hooks[event] or {}; table.insert(hooks[event], callback)
  end,
  timer = function(callback, options)
    local timer = {enabled = true, callback = callback, timeout = options.timeout}
    function timer:set_enabled(enabled) self.enabled = enabled end
    function timer:set_timeout(timeout) self.timeout = timeout; self.enabled = true end
    timers[#timers + 1] = timer
    return timer
  end,
  workspace_rule = function(rule)
    local id = tonumber(rule.workspace)
    if id then rules[id] = rule; rule_writes = rule_writes + 1 end
  end,
  exec_scheduled_prop_refresh_immediately = function()
    for id, rule in pairs(rules) do
      if rule.persistent then workspace(id, assert(monitors[rule.monitor])) end
    end
  end,
  get_monitors = function() return values(monitors) end,
  get_workspaces = function() return values(workspaces) end,
  get_windows = function() return windows end,
  get_active_workspace = function() return focused and focused.active_workspace end,
  get_active_monitor = function() return focused end,
  get_active_window = function() return focused_window end,
  exec_cmd = function() error("workspace policy must not launch a subprocess") end,
  dispatch = function(action)
    if action.path == "hl.dsp.event" then return end
    actions[#actions + 1] = action
    local args = action.args[1]
    if action.path == "hl.dsp.focus" then
      if args.window then
        focused_window = args.window
        focused = args.window.workspace.monitor
        focused.active_workspace = args.window.workspace
      else
        local target = workspace(args.workspace, assert(monitors[rules[args.workspace].monitor]))
        focused = target.monitor; focused.active_workspace = target
      end
    elseif action.path == "hl.dsp.window.move" then
      local window = args.window or focused_window
      if window then
        window.workspace = workspace(args.workspace, assert(monitors[rules[args.workspace].monitor]))
        if args.follow ~= false then
          focused = window.workspace.monitor; focused.active_workspace = window.workspace
        end
      end
    elseif action.path == "hl.dsp.workspace.move" then
      local value = assert(workspaces[args.workspace])
      value.monitor = assert(monitors[args.monitor])
    else error("unexpected workspace action: " .. action.path) end
  end,
  define_submap = function(_, callback) callback() end,
}, {__index = function() return function() end end})

assert(loadfile(assert(arg[1], "provide the generated Hyprland config")))()
local function emit(event)
  for _, callback in ipairs(hooks[event] or {}) do callback() end
end
local function flush()
  for _ = 1, 10 do
    local pending = false
    for _, timer in ipairs(timers) do
      if timer.enabled then pending = true; timer.callback() end
    end
    if not pending then return end
  end
  error("workspace events must settle without a timer loop")
end
flush()
for id = 1, 10 do
  assert(rules[id].monitor == (id <= 5 and "DP-2" or "eDP-1"))
  assert(rules[id].persistent)
  local key = id == 10 and "0" or tostring(id)
  assert(type(bindings["SUPER + " .. key]) == "function")
  assert(type(bindings["SUPER + SHIFT + " .. key]) == "function")
end
assert(rules[1].default and rules[6].default)

local function press(key, id, target_monitor, path)
  local before = #actions
  assert(bindings[key], "missing binding " .. key)()
  assert(#actions == before + 1, "one key must dispatch exactly one action")
  local action = actions[#actions]
  assert(action.path == (path or "hl.dsp.focus"))
  assert(action.args[1].workspace == id, "wrong workspace for " .. key)
  if target_monitor then assert(focused.name == target_monitor) end
end

-- Every displayed slot has matching direct and shifted shortcuts when docked.
for id = 1, 10 do
  local key = id == 10 and "0" or tostring(id)
  press("SUPER + " .. key, id, id <= 5 and "DP-2" or "eDP-1")
  press("SUPER + SHIFT + " .. key, id, nil, "hl.dsp.window.move")
end
for _, output in ipairs({external, internal}) do
  local first = output == external and 1 or 6
  focused = output; output.active_workspace = workspaces[first]
  for _ = 1, 2 do
    for index = 1, 5 do press("SUPER + ALT + L", first + index % 5, output.name) end
    for index = 4, 0, -1 do press("SUPER + ALT + H", first + index, output.name) end
  end
end

-- Undocking merges windows 7→2, preserves existing windows on 2 and specials,
-- and keeps the focused application selected without ever closing it.
windows = {{name = "external-app", workspace = workspaces[2]},
  {name = "laptop-app", workspace = workspaces[7]},
  {name = "special-app", workspace = workspace(-98, external)}}
focused, focused_window = internal, windows[2]
internal.active_workspace = workspaces[7]
monitors["DP-2"] = nil
for _, value in pairs(workspaces) do value.monitor = internal end
emit("monitor.removed"); emit("monitor.layout_changed"); flush()
assert(#windows == 3 and windows[1].workspace.id == 2 and windows[2].workspace.id == 2)
assert(windows[3].workspace.id == -98)
assert(focused_window == windows[2] and internal.active_workspace.id == 2)
for id = 1, 10 do
  assert(rules[id].monitor == "eDP-1")
  assert(rules[id].persistent == (id <= 5))
  assert(rules[id].default == (id == 1))
end
for id = 1, 5 do press("SUPER + " .. id, id, "eDP-1") end
for _, key in ipairs({"6", "7", "8", "9", "0"}) do
  local before = #actions
  bindings["SUPER + " .. key](); bindings["SUPER + SHIFT + " .. key]()
  assert(#actions == before, "upper shortcuts must not create hidden slots while alone")
end
press("SUPER + ALT + L", 1, "eDP-1")
press("SUPER + ALT + H", 5, "eDP-1")

-- Unchanged layout events and reloads never move an already correct window.
local before, writes = #actions, rule_writes
emit("monitor.layout_changed"); flush()
assert(#actions == before and rule_writes == writes)
emit("config.reloaded"); flush()
assert(#actions == before and rule_writes == writes + 10)

-- Reconnect on a different connector: the five shared desktops become external.
external = monitor("HDMI-A-1", 1)
emit("monitor.added"); emit("monitor.layout_changed"); flush()
assert(rules[1].monitor == "HDMI-A-1" and rules[6].monitor == "eDP-1")
assert(windows[1].workspace.monitor.name == "HDMI-A-1")
assert(windows[2].workspace.id == 2 and windows[2].workspace.monitor.name == "HDMI-A-1")
assert(internal.active_workspace.id == 6)
press("SUPER + 0", 10, "eDP-1")
press("SUPER + ALT + L", 6, "eDP-1")
press("SUPER + 1", 1, "HDMI-A-1")

-- A lone external screen (closed laptop) also uses 1–5, and zero screens is safe.
monitors["eDP-1"] = nil
for _, value in pairs(workspaces) do value.monitor = external end
focused, focused_window = external, nil
emit("monitor.removed"); flush()
assert(rules[1].monitor == "HDMI-A-1" and not rules[6].persistent)
monitors, focused = {}, nil
before = #actions
emit("monitor.removed"); flush()
bindings["SUPER + 1"](); bindings["SUPER + ALT + H"](); bindings["SUPER + ALT + L"]()
assert(#actions == before)
print("PASS: dock/undock, direct/shifted/cycle shortcuts, window merging, focus, reload and connector changes")
