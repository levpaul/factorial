local advisor = require("scripts.advisor")
local external = require("scripts.external")
local gui = require("scripts.gui")

local LOADING_TICK_INTERVAL = 20
local loading_dots_counters = {}

local function get_show_internal(player_index)
  advisor.ensure_player(player_index)
  return storage.player_data[player_index].show_internal == true
end

local function set_show_internal(player_index, value)
  advisor.ensure_player(player_index)
  storage.player_data[player_index].show_internal = value
end

local function get_dev_mode()
  return settings.global["factorial-dev-mode"].value
end

local function get_scope(player_index)
  advisor.ensure_player(player_index)
  return advisor.get_feedback_scope(player_index)
end

local function render_gui(player)
  local report = advisor.get_last_report(player.index)
  if not report then
    return
  end
  gui.render(
    player,
    report,
    advisor.get_external_report(player.index),
    get_show_internal(player.index),
    get_dev_mode(),
    advisor.get_detail_cache(player.index),
    advisor.get_expanded_details(player.index)
  )
end

local function refresh_player(player, scope)
  scope = scope or get_scope(player.index)
  local report, snapshot = advisor.build_report(player, scope)
  advisor.store_player_state(player.index, report, snapshot)
  render_gui(player)
  gui.set_internal_button_state(player, get_show_internal(player.index))
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
  gui.set_advisor_dropdown_index(player, gui.advisor_index_from_type(advisor.get_advisor_type(player.index)))
  gui.set_scope_dropdown_index(player, gui.index_from_scope(advisor.get_feedback_scope(player.index)))
  refresh_player(player)
end

local function export_for_player(player)
  local scope = get_scope(player.index)
  local report, snapshot = refresh_player(player, scope)
  local paths = external.export_snapshot(player, snapshot, report, scope)
  player.print(
    ("[Factorial Advisor] Wrote snapshot to script-output/%s and report to script-output/%s.")
      :format(paths.snapshot, paths.report)
  )
end

local function start_loading_animation(player_index)
  loading_dots_counters[player_index] = 1
  advisor.set_loading_state(player_index, true)
end

local function stop_loading_animation(player_index)
  loading_dots_counters[player_index] = nil
  advisor.set_loading_state(player_index, false)
end

local function send_external_request(player, scope)
  scope = scope or get_scope(player.index)
  start_loading_animation(player.index)
  gui.show_loading(player, loading_dots_counters[player.index] or 1)
  local report, snapshot = refresh_player(player, scope)
  local ok, message = external.send_snapshot(player, snapshot, report, scope)
  if ok then
    player.print("[Factorial Advisor] Snapshot sent to the localhost UDP bridge (Anthropic).")
  else
    stop_loading_animation(player.index)
    player.print("[Factorial Advisor] " .. message)
  end
end

local function send_local_llm_request(player, scope)
  scope = scope or get_scope(player.index)
  start_loading_animation(player.index)
  gui.show_loading(player, loading_dots_counters[player.index] or 1)
  local report, snapshot = refresh_player(player, scope)
  local ok, message = external.send_snapshot_local_llm(player, snapshot, report, scope)
  if ok then
    player.print("[Factorial Advisor] Snapshot sent to the localhost UDP bridge (Local LLM).")
  else
    stop_loading_animation(player.index)
    player.print("[Factorial Advisor] " .. message)
  end
end

--- Handle a click on a detail ("get more info") button.
--- Button names follow the pattern: factorial_advisor_detail_<section>_<item>
local function handle_detail_click(player, element_name)
  local si_str, ii_str = element_name:match("^" .. gui.names.detail_prefix .. "(%d+)_(%d+)$")
  if not si_str or not ii_str then
    return false
  end

  local detail_key = si_str .. "_" .. ii_str
  local si = tonumber(si_str)
  local ii = tonumber(ii_str)

  -- Toggle the expanded state
  local now_expanded = advisor.toggle_expanded(player.index, detail_key)

  -- If expanding and no cached detail, send a request
  if now_expanded and not advisor.get_detail(player.index, detail_key) then
    local ext_report = advisor.get_external_report(player.index)
    if ext_report and ext_report.sections and ext_report.sections[si] then
      local section = ext_report.sections[si]
      local items = section.items or {}
      local item_text = items[ii]
      if item_text then
        local ok, message = external.send_detail_request(
          player,
          item_text,
          section.title or "External Notes",
          detail_key,
          ext_report.source or "claude"
        )
        if ok then
          player.print("[Factorial Advisor] Requesting details...")
        else
          player.print("[Factorial Advisor] " .. message)
        end
      end
    end
  end

  -- Re-render the GUI to show/hide the detail
  render_gui(player)
  gui.set_internal_button_state(player, get_show_internal(player.index))
  return true
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

commands.add_command("advisor-send", "Send the latest advisor snapshot to the localhost UDP bridge (Anthropic).", function(command)
  if not command.player_index then
    return
  end

  local player = game.get_player(command.player_index)
  if player then
    advisor.ensure_player(player.index)
    send_external_request(player, get_scope(player.index))
  end
end)

commands.add_command("advisor-send-local", "Send the latest advisor snapshot to the localhost UDP bridge (Local LLM).", function(command)
  if not command.player_index then
    return
  end

  local player = game.get_player(command.player_index)
  if player then
    advisor.ensure_player(player.index)
    send_local_llm_request(player, get_scope(player.index))
  end
end)

script.on_init(on_init)
script.on_configuration_changed(on_configuration_changed)
script.on_event(defines.events.on_player_created, on_player_created)

script.on_nth_tick(20, function()
  external.poll_udp()

  for player_index, _ in pairs(loading_dots_counters) do
    local player = game.get_player(player_index)
    if player and gui.is_open(player) and advisor.get_loading_state(player_index) then
      loading_dots_counters[player_index] = (loading_dots_counters[player_index] % #gui.LOADING_STATES) + 1
      gui.show_loading(player, loading_dots_counters[player_index])
    end
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if event.element and event.element.valid and event.element.name == gui.names.frame then
    gui.close(player)
  end
end)

script.on_event("factorial-toggle-advisor", function(event)
  local player = game.get_player(event.player_index)
  if player then
    advisor.ensure_player(player.index)
    toggle_for_player(player)
  end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local element = event.element
  if not element or not element.valid then
    return
  end

  local player = game.get_player(event.player_index)
  if not player then
    return
  end

  if element.name == gui.names.advisor_dropdown then
    local advisor_type = gui.advisor_type_from_index(element.selected_index)
    advisor.set_advisor_type(player.index, advisor_type)

    if advisor_type == "internal" then
      local scope = get_scope(player.index)
      refresh_player(player, scope)
    end
  end

  if element.name == gui.names.scope_dropdown then
    local scope = gui.scope_from_index(element.selected_index)
    advisor.set_feedback_scope(player.index, scope)
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
    local scope = get_scope(player.index)
    refresh_player(player, scope)
    player.print("[Factorial Advisor] Analysis refreshed.")
    return
  end

  if element.name == gui.names.export_button then
    export_for_player(player)
    return
  end

  if element.name == gui.names.ask_button then
    local scope = get_scope(player.index)
    local advisor_type = advisor.get_advisor_type(player.index)

    if advisor_type == "internal" then
      refresh_player(player, scope)
      player.print("[Factorial Advisor] Internal analysis refreshed.")
    elseif advisor_type == "external" then
      send_external_request(player, scope)
    elseif advisor_type == "local-llm" then
      send_local_llm_request(player, scope)
    end
    return
  end

  if element.name:sub(1, #gui.names.detail_prefix) == gui.names.detail_prefix then
    handle_detail_click(player, element.name)
    return
  end

  if element.name == gui.names.internal_button then
    local current = get_show_internal(player.index)
    set_show_internal(player.index, not current)
    render_gui(player)
    gui.set_internal_button_state(player, not current)
    return
  end

  if element.name == gui.names.clear_button then
    advisor.store_player_state(player.index, nil, nil)
    advisor.set_external_report(player.index, nil)
    advisor.clear_detail_cache(player.index)
    gui.clear(player)
    player.print("[Factorial Advisor] Cleared.")
    return
  end
end)

script.on_event(defines.events.on_udp_packet_received, function(event)
  local response_type = external.receive_response(event)
  local player = game.get_player(event.player_index)
  if player then
    stop_loading_animation(player.index)
    if gui.is_open(player) then
      render_gui(player)
      gui.set_internal_button_state(player, get_show_internal(player.index))
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
