-- Exercise the generated config without sending events to the real desktop.
local bindings, hooks, events, commands = {}, {}, {}, {}
local current_submap = ""
local function dispatcher(path)
  return setmetatable({}, {
    __index = function(_, key) return dispatcher(path .. "." .. key) end,
    __call = function(_, ...) return { path = path, args = { ... } } end,
  })
end
hl = setmetatable({
  dsp = dispatcher("hl.dsp"),
  bind = function(key, action, options)
    assert(action ~= nil, "binding registered before its callback exists: " .. key)
    bindings[#bindings + 1] = { key = key, action = action, options = options or {} }
  end,
  on = function(event, callback) hooks[event] = callback end,
  exec_cmd = function(command) commands[#commands + 1] = command end,
  get_current_submap = function() return current_submap end,
  dispatch = function(action)
    if action.path == "hl.dsp.event" then
      events[#events + 1] = action.args[1]
    elseif action.path == "hl.dsp.submap" then
      current_submap = action.args[1] == "reset" and "" or action.args[1]
      if hooks["keybinds.submap"] then hooks["keybinds.submap"](current_submap) end
    end
  end,
  define_submap = function(_, callback) callback() end,
}, { __index = function() return function() end end })

assert(loadfile(assert(arg[1], "provide the generated Hyprland config")))()
local show, next_page, previous_page, stop_voice
local chromeTabs, releases = 0, {}
for _, binding in ipairs(bindings) do
  local action, options = binding.action, binding.options
  if binding.key == "SUPER + apostrophe" and not options.release then
    assert(not show, "duplicate show binding")
    show = action
    assert(not options.repeating and not options.non_consuming)
  elseif binding.key == "SUPER + TAB" and not options.release then
    next_page = action
    assert(not options.repeating and not options.non_consuming)
  elseif binding.key == "SUPER + SHIFT + TAB" then
    previous_page = action
    assert(options.auto_consuming and not options.repeating)
  elseif binding.key == "TAB" and options.release then
    stop_voice = action
  end
  if type(action) == "table" then
    assert(not (action.path == "hl.dsp.exec_cmd"
      and action.args[1]:find("dev.me.pi", 1, true)), "Pi shortcut must be removed")
    if action.path == "hl.dsp.exec_cmd" and action.args[1]:find("topbar toggleChromeTabs", 1, true) then
      chromeTabs = chromeTabs + 1
      assert(binding.key == "SUPER + P", "Chrome tabs must move to Cmd+P")
      assert(not options.release and not options.repeating)
    end
  elseif options.release and options.submap_universal then
    assert(not releases[binding.key], "duplicate sheet release binding")
    releases[binding.key] = action
    assert(options.ignore_mods and options.transparent and options.non_consuming,
      "sheet release must survive modifier/submap changes without consuming other releases")
  end
end
assert(show and next_page and previous_page and stop_voice)
assert(chromeTabs == 1, "exactly one Chrome tabs binding is required")
assert(not releases.P, "releasing P must no longer hide the sheet")
assert(not releases.ISO_Level5_Latch, "the Lafayette latch must not control the sheet")

-- Cmd+Tab stays push-to-talk; Shift+Tab passes through while the sheet is hidden.
local result = previous_page()
assert(result.pass_event and not result.ok)
next_page()
assert(commands[#commands]:find("record start", 1, true))
assert(current_submap == "voxtype")
stop_voice()
assert(commands[#commands]:find("record stop", 1, true))
assert(current_submap == "")

for _, key in ipairs({ "apostrophe", "SUPER + SUPER_L", "SUPER + SUPER_R" }) do
  assert(releases[key], "missing release: " .. key)
  show()
  assert(events[#events] == "keyboard-cheatsheet:show")
  local before = #commands
  for _ = 1, 3 do
    next_page()
    assert(events[#events] == "keyboard-cheatsheet:next")
    stop_voice() -- Releasing Tab must not hide the sheet or stop a nonexistent recording.
    assert(events[#events] == "keyboard-cheatsheet:next")
  end
  result = previous_page()
  assert(result.ok and not result.pass_event)
  assert(events[#events] == "keyboard-cheatsheet:previous")
  assert(#commands == before and current_submap == "", "sheet cycling must not start dictation")
  releases[key]()
  assert(events[#events] == "keyboard-cheatsheet:hide")
  assert(previous_page().pass_event, "release must clear the sheet state")
end

for _, event in ipairs({ "keybinds.submap", "config.reloaded" }) do
  show()
  assert(hooks[event], "missing cleanup hook: " .. event)
  hooks[event]("")
  assert(events[#events] == "keyboard-cheatsheet:hide")
  assert(previous_page().pass_event, "compositor event must clear the sheet state")
end
print("PASS: sheet show/release, Tab/Shift+Tab, hidden-key pass-through, dictation and reload/submap cleanup")
