local advisor = require("scripts.advisor")
local external = require("scripts.external")
local gui = require("scripts.gui")

local function refresh_player(player)
  local report, snapshot = advisor.build_report(player)
  advisor.store_player_state(player.index, report, snapshot)
  gui.render(player, report, advisor.get_external_report(player.index))
  return report, snapshot
end

local function open_or_refresh(player)
  if gui.open(player) then
    refresh_player(player)
  elseif gui.is_open(player) then
    refresh_player(player)
  end
end

local function toggle_for_player(player)
  if gui.is_open(player) then
    gui.close(player)
    return
  end

  gui.open(player)
  refresh_player(player)
end

local function export_for_player(player)
  local report, snapshot = refresh_player(player)
  local paths = external.export_snapshot(player, snapshot, report)
  player.print(
    ("[Factorial Advisor] Wrote snapshot to script-output/%s and report to script-output/%s.")
      :format(paths.snapshot, paths.report)
  )
end

local function send_external_request(player)
  local report, snapshot = refresh_player(player)
  local ok, message = external.send_snapshot(player, snapshot, report)
  if ok then
    player.print("[Factorial Advisor] Snapshot sent to the localhost UDP bridge.")
  else
    player.print("[Factorial Advisor] " .. message)
  end
end

local function on_init()
  advisor.initialize_storage()
  for _, player in pairs(game.players) do
    advisor.ensure_player(player.index)
  end
end

local function on_configuration_changed()
  advisor.initialize_storage()
  for _, player in pairs(game.players) do
    advisor.ensure_player(player.index)
    if gui.is_open(player) then
      refresh_player(player)
    end
  end
end

local function on_player_created(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  advisor.ensure_player(player.index)
  player.print("[Factorial Advisor] Press Control+Shift+A or use /advisor to open the advisor.")
end

commands.add_command("advisor", "Toggle the Factorial AI Advisor window.", function(command)
  if not command.player_index then
    return
  end

  local player = game.get_player(command.player_index)
  if player then
    advisor.ensure_player(player.index)
    toggle_for_player(player)
  end
end)

commands.add_command("advisor-refresh", "Refresh the Factorial AI Advisor analysis.", function(command)
  if not command.player_index then
    return
  end

  local player = game.get_player(command.player_index)
  if player then
    advisor.ensure_player(player.index)
    open_or_refresh(player)
    player.print("[Factorial Advisor] Analysis refreshed.")
  end
end)

commands.add_command("advisor-export", "Export the latest advisor snapshot to script-output.", function(command)
  if not command.player_index then
    return
  end

  local player = game.get_player(command.player_index)
  if player then
    advisor.ensure_player(player.index)
    export_for_player(player)
  end
end)

commands.add_command("advisor-send", "Send the latest advisor snapshot to the localhost UDP bridge.", function(command)
  if not command.player_index then
    return
  end

  local player = game.get_player(command.player_index)
  if player then
    advisor.ensure_player(player.index)
    send_external_request(player)
  end
end)

script.on_init(on_init)
script.on_configuration_changed(on_configuration_changed)
script.on_event(defines.events.on_player_created, on_player_created)

script.on_event("factorial-toggle-advisor", function(event)
  local player = game.get_player(event.player_index)
  if player then
    advisor.ensure_player(player.index)
    toggle_for_player(player)
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not element or not element.valid then
    return
  end

  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if element.name == gui.names.close_button then
    gui.close(player)
    return
  end

  if element.name == gui.names.refresh_button then
    refresh_player(player)
    player.print("[Factorial Advisor] Analysis refreshed.")
    return
  end

  if element.name == gui.names.export_button then
    export_for_player(player)
    return
  end

  if element.name == gui.names.external_button then
    send_external_request(player)
  end
end)

script.on_nth_tick(30, function()
  external.poll_udp()
end)

script.on_event(defines.events.on_udp_packet_received, function(event)
  external.receive_response(event)

  local player = game.get_player(event.player_index)
  if player and gui.is_open(player) then
    local report = advisor.get_last_report(player.index)
    if report then
      gui.render(player, report, advisor.get_external_report(player.index))
    end
  end
end)

remote.add_interface("factorial_ai_advisor", {
  get_latest_report = function(player_index)
    return advisor.get_last_report(player_index)
  end,
  get_latest_snapshot = function(player_index)
    return advisor.get_last_snapshot(player_index)
  end
})
