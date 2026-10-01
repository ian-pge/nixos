-- Five workspaces alone; external 1–5 and internal 6–10 when docked.
-- Everything runs in Hyprland's event loop, with no polling subprocess.
local function internal_output(name)
  return name and (name:match("^eDP%-") or name:match("^LVDS%-") or name:match("^DSI%-"))
end

local function workspace_outputs()
  local monitors = {}
  for _, monitor in ipairs(hl.get_monitors()) do
    if not monitor.is_mirror then table.insert(monitors, monitor) end
  end
  table.sort(monitors, function(a, b) return a.name < b.name end)
  local internal, external
  for _, monitor in ipairs(monitors) do
    if internal_output(monitor.name) then
      internal = internal or monitor
    elseif not external or monitor.name == "DP-2" then
      external = monitor
    end
  end
  local primary = external or internal
  return primary, internal and external and internal or nil
end

function quickshell_workspace_first(monitor)
  local _, secondary = workspace_outputs()
  return secondary and monitor and monitor.name == secondary.name and 6 or 1
end

function quickshell_workspace_target(id)
  local primary, secondary = workspace_outputs()
  if not primary or (id > 5 and not secondary) then return nil end
  return id
end

local last_topology = nil
local function reconcile_workspaces()
  local primary, secondary = workspace_outputs()
  if not primary then last_topology = nil; return end
  local topology = primary.name .. ":" .. (secondary and secondary.name or "")
  if topology == last_topology then return end
  -- A rule refresh can itself emit monitor events; commit before changing rules.
  last_topology = topology
  local active = hl.get_active_workspace()
  local active_id = active and active.id or nil
  local focused_window = hl.get_active_window()
  local changed = false

  for id = 1, 10 do
    local target = id <= 5 and primary or (secondary or primary)
    hl.workspace_rule({
      workspace = tostring(id), monitor = target.name,
      persistent = id <= 5 or secondary ~= nil,
      default = id == 1 or (id == 6 and secondary ~= nil),
    })
  end
  -- Materialize persistent destinations before moving windows or selecting one.
  hl.exec_scheduled_prop_refresh_immediately()

  if not secondary then
    -- Merge corresponding slots without closing applications or touching specials.
    for _, window in ipairs(hl.get_windows()) do
      local workspace = window.workspace
      if workspace and workspace.id >= 6 and workspace.id <= 10 then
        hl.dispatch(hl.dsp.window.move({window = window, workspace = workspace.id - 5, follow = false}))
        changed = true
      end
    end
  end

  for _, workspace in ipairs(hl.get_workspaces()) do
    if workspace.id >= 1 and workspace.id <= 10 then
      local target = workspace.id <= 5 and primary or (secondary or primary)
      if not workspace.monitor or workspace.monitor.name ~= target.name then
        hl.dispatch(hl.dsp.workspace.move({workspace = workspace.id, monitor = target.name}))
        changed = true
      end
    end
  end

  local function select_valid_workspace(monitor, first)
    local workspace = monitor.active_workspace
    if not workspace or workspace.id < first or workspace.id >= first + 5 then
      local target = first
      if not secondary and active_id and active_id >= 6 and active_id <= 10 then
        target = active_id - 5
      end
      monitor:set_workspace({workspace = target})
      changed = true
    end
  end
  select_valid_workspace(primary, 1)
  if secondary then select_valid_workspace(secondary, 6) end
  if changed and focused_window then
    hl.dispatch(hl.dsp.focus({window = focused_window}))
  end
end

-- Reusable one-shot scheduling: a repeating timer is disabled in its callback,
-- retaining its Lua handle for the next hotplug event.
local workspace_timer
workspace_timer = hl.timer(function()
  workspace_timer:set_enabled(false)
  reconcile_workspaces()
end, {timeout = 100, type = "repeat"})

local function schedule_workspace_update()
  workspace_timer:set_timeout(100)
end
hl.on("monitor.added", schedule_workspace_update)
hl.on("monitor.removed", schedule_workspace_update)
hl.on("monitor.layout_changed", schedule_workspace_update)
hl.on("hyprland.start", schedule_workspace_update)
hl.on("config.reloaded", function()
  last_topology = nil
  schedule_workspace_update()
end)
