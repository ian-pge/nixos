-- Pass the Home Manager generated hyprland.lua as the first argument.
local bindings = {}
local function dispatcher(path)
  return setmetatable({}, {
    __index = function(_, key) return dispatcher(path .. "." .. key) end,
    __call = function(_, ...) return { path = path, args = { ... } } end,
  })
end
hl = setmetatable({
  dsp = dispatcher("hl.dsp"),
  bind = function(key, action, options)
    bindings[#bindings + 1] = { key = key, action = action, options = options or {} }
  end,
  define_submap = function(_, callback) callback() end,
}, { __index = function() return function() end end })

assert(loadfile(assert(arg[1], "provide the generated Hyprland config")))()
local show, chromeTabs, releases = 0, 0, {}
for _, binding in ipairs(bindings) do
  local action, options = binding.action, binding.options
  if type(action) == "table" then
    assert(not (action.path == "hl.dsp.exec_cmd"
      and action.args[1]:find("dev.me.pi", 1, true)), "Pi shortcut must be removed")
    if action.path == "hl.dsp.exec_cmd" and action.args[1]:find("topbar toggleChromeTabs", 1, true) then
      chromeTabs = chromeTabs + 1
      assert(binding.key == "SUPER + P", "Chrome tabs must move to Cmd+P")
      assert(not options.release and not options.repeating)
    end
    if action.path == "hl.dsp.event" then
      if action.args[1] == "keyboard-cheatsheet:show" then
        show = show + 1
      assert(binding.key == "SUPER + apostrophe")
        assert(not options.release and not options.repeating and not options.non_consuming,
          "Cmd+apostrophe must show once on press and consume the shortcut")
      elseif action.args[1] == "keyboard-cheatsheet:hide" then
        assert(not releases[binding.key], "duplicate release binding")
        releases[binding.key] = true
        assert(options.release and options.ignore_mods,
          "release must work even when Cmd is released before semicolon")
        assert(options.transparent and options.submap_universal,
          "release must survive other bindings and submaps")
        assert(options.non_consuming, "ordinary key releases must reach applications")
      end
    end
  end
end
assert(show == 1, "exactly one Cmd+apostrophe press binding is required")
assert(chromeTabs == 1, "exactly one Chrome tabs binding is required")
assert(not releases.P, "releasing P must no longer hide the sheet")
assert(not releases.ISO_Level5_Latch, "the Lafayette latch must not control the sheet")
for _, key in ipairs({ "apostrophe", "SUPER + SUPER_L", "SUPER + SUPER_R" }) do
  assert(releases[key], "missing release: " .. key)
end
print("HHKB bindings passed: Cmd+apostrophe hold/release, Cmd+P Chrome tabs, both Cmd keys, modifier/submap changes")
