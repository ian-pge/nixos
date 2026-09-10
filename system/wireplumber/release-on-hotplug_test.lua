-- Run with Lua 5.4 from the repository root. No connection to the user's audio.
local hook
function Constraint(value) return value end
function EventInterest(value) return value end
function SimpleEventHook(value)
  function value:register() hook = self end
  return value
end
package.preload["common-utils"] = function()
  return { parseParam = function(param) return param end }
end

local configured, removed, routes = {}, {}, {}
local metadata = {}
function metadata:find(_, key) return configured[key] end
function metadata:set(_, key, _, value)
  assert(value == nil, "the hook must only clear preferences")
  configured[key] = nil
  removed[#removed + 1] = key
end
local devices = {}
function devices:lookup(constraints)
  local id = constraints[1][3]
  if not routes[id] then return nil end
  return { iterate_params = function(_, param)
    assert(param == "EnumRoute", "volume/mute parameters must not affect policy")
    local index = 0
    return function()
      index = index + 1
      return routes[id][index]
    end
  end }
end
local source = {}
function source:call(_, name)
  if name == "device" then return devices end
  assert(name == "metadata")
  return { lookup = function() return metadata end }
end
local function event(direction, nodes)
  hook.execute {
    get_properties = function() return { ["default-node.type"] = direction } end,
    get_data = function() return nodes and { parse = function() return nodes end } end,
    get_source = function() return source end,
  }
end
local function choose(direction)
  configured["default.configured." .. direction] = "manual"
end
local function kept(direction)
  assert(configured["default.configured." .. direction] == "manual")
end
local function released(direction)
  assert(configured["default.configured." .. direction] == nil)
end

dofile("system/wireplumber/release-on-hotplug.lua")
assert(hook.name == "default-nodes/release-on-hotplug")
assert(hook.before[1] == "default-nodes/find-selected-default-node")

local speaker = { ["media.class"] = "Audio/Sink", ["node.name"] = "speakers",
  ["object.serial"] = "1", ["device.id"] = "10" }
local headset = { ["media.class"] = "Audio/Sink", ["node.name"] = "headset",
  ["object.serial"] = "2" }
local mic = { ["media.class"] = "Audio/Source", ["node.name"] = "mic",
  ["object.serial"] = "3", ["device.id"] = "10" }
routes["10"] = {
  { index = 0, direction = "Output", available = "unknown" },
  { index = 1, direction = "Output", available = "no" },
  { index = 2, direction = "Input", available = "yes" },
}

-- First discovery and repeated rescans must preserve an existing choice.
choose("audio.sink")
choose("audio.source")
event("audio.sink", { speaker })
event("audio.source", { mic, speaker }) -- sources also include sink monitors upstream
event("audio.sink", { speaker })
kept("audio.sink")
kept("audio.source")

-- Adding/removing a playback endpoint affects only the output preference.
event("audio.sink", { speaker, headset })
released("audio.sink")
event("audio.source", { mic, speaker, headset })
kept("audio.source")
choose("audio.sink")
event("audio.sink", { headset, speaker }) -- enumeration order is irrelevant
kept("audio.sink")
event("audio.sink", { speaker })
released("audio.sink")

-- A jack can change route availability without creating a new node.
choose("audio.sink")
routes["10"][2].available = "yes"
event("audio.sink", { speaker })
released("audio.sink")
event("audio.source", { mic, speaker })
kept("audio.source")
choose("audio.sink")
routes["10"][3].available = "no"
event("audio.sink", { speaker })
kept("audio.sink")
event("audio.source", { mic, speaker })
released("audio.source")

-- Neither audio parameters nor application streams release a selection.
speaker.volume, speaker.mute = 0.7, true
routes["10"][1].props = { volume = 0.7, mute = true }
event("audio.sink", { speaker,
  { ["media.class"] = "Stream/Output/Audio", ["node.name"] = "music" } })
kept("audio.sink")
event("audio.sink", { speaker })
kept("audio.sink")

-- Metadata changes and unrelated video rescans do not reset the baseline.
event("audio.sink", nil)
event("video.source", {})
event("audio.sink", { speaker })
kept("audio.sink")
speaker["object.serial"] = "4" -- replacement with the same name
event("audio.sink", { speaker })
released("audio.sink")
choose("audio.sink")
event("audio.sink", {})
released("audio.sink")
local count = #removed
event("audio.sink", { speaker }) -- no preference: no redundant metadata writes
assert(#removed == count)
print("Audio hotplug policy: all scenarios passed")
