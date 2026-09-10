-- Run with the generated Home Manager hyprland.lua path as the first argument.
local bindings, commands, dispatches = {}, {}, {}
local submap = "reset"
local function dispatcher(path)
  return setmetatable({}, {
    __index = function(_, key) return dispatcher(path .. "." .. key) end,
    __call = function(_, ...) return { path = path, args = { ... } } end,
  })
end
hl = setmetatable({
  dsp = dispatcher("hl.dsp"),
  bind = function(key, callback, options)
    if key == "ESCAPE" then
      bindings[submap] = { callback = callback, options = options }
    end
  end,
  define_submap = function(name, callback, options)
    assert(options == nil, "notification Escape must not auto-reset the dictation submap")
    submap = name
    callback()
    submap = "reset"
  end,
  exec_cmd = function(command) table.insert(commands, command) end,
  dispatch = function(action) table.insert(dispatches, action) end,
}, { __index = function() return function() end end })

assert(loadfile(assert(arg[1], "provide the generated Hyprland config")))()
assert(bindings.reset.options.auto_consuming)
assert(bindings.voxtype.options.ignore_mods)

quickshell_notification_deadline = nil
local result = bindings.reset.callback()
assert(result.ok == false and result.pass_event == true)
assert(#commands == 0, "ordinary Escape must not invoke Quickshell")

quickshell_notification_deadline = os.time() + 5
result = bindings.reset.callback()
assert(result.ok == true and not result.pass_event)
assert(#commands == 1 and commands[1]:find("topbar dismissNotification", 1, true))
assert(quickshell_notification_deadline == 0)

commands = {}
quickshell_notification_deadline = os.time() + 5
bindings.voxtype.callback()
assert(#commands == 1 and commands[1]:find("topbar dismissNotification", 1, true))
assert(#dispatches == 0, "closing a notification must keep the dictation submap")

commands = {}
quickshell_notification_deadline = os.time() - 1
bindings.voxtype.callback()
assert(#commands == 1 and commands[1]:find("voxtype record cancel", 1, true))
assert(#dispatches == 1 and dispatches[1].path == "hl.dsp.submap")
assert(dispatches[1].args[1] == "reset")
print("Notification Escape tests passed")
