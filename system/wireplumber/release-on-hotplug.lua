-- Keep manual selection until the available devices/routes change, then let
-- WirePlumber's normal priority policy select the default again.
local cutils = require("common-utils")
local previous = {}

local function signature(nodes, devices, direction)
  local parts = {}
  for _, node in ipairs(nodes) do
    local class = node["media.class"] or ""
    local relevant = direction == "audio.sink" and class == "Audio/Sink"
      or direction == "audio.source" and (class == "Audio/Source"
        or class == "Audio/Source/Virtual")
      or class == "Audio/Duplex"
    if relevant then
      parts[#parts + 1] = string.format("node:%q:%q", node["node.name"] or "",
        tostring(node["object.serial"] or ""))
      local device = node["device.id"] and devices:lookup {
        Constraint { "bound-id", "=", node["device.id"], type = "gobject" },
      }
      if device then
        -- EnumRoute describes physical availability. Route also contains volume
        -- and mute changes, which must never cancel a manual selection.
        for param in device:iterate_params("EnumRoute") do
          local route = cutils.parseParam(param, "EnumRoute")
          local route_direction = direction == "audio.sink" and "Output" or "Input"
          if route and route.direction == route_direction then
            parts[#parts + 1] = string.format("route:%q:%q:%q",
              tostring(node["device.id"]), tostring(route.index),
              tostring(route.available or "unknown"))
          end
        end
      end
    end
  end
  table.sort(parts)
  return table.concat(parts, "\n")
end

SimpleEventHook {
  name = "default-nodes/release-on-hotplug",
  before = { "default-nodes/find-selected-default-node",
    "default-nodes/find-stored-default-node", "default-nodes/find-best-default-node" },
  interests = {
    EventInterest { Constraint { "event.type", "=", "select-default-node" } },
  },
  execute = function(event)
    local direction = event:get_properties()["default-node.type"]
    if direction ~= "audio.sink" and direction ~= "audio.source" then
      return
    end
    local available = event:get_data("available-nodes")
    if not available then
      return
    end
    local source = event:get_source()
    local devices = source:call("get-object-manager", "device")
    local current = signature(available:parse(), devices, direction)
    local changed = previous[direction] ~= nil and previous[direction] ~= current
    previous[direction] = current
    if not changed then
      return
    end
    local metadata = source:call("get-object-manager", "metadata"):lookup {
      Constraint { "metadata.name", "=", "default" },
    }
    local key = "default.configured." .. direction
    if metadata and metadata:find(0, key) then
      metadata:set(0, key, nil, nil)
    end
  end,
}:register()
