local advisor = require("scripts.advisor")

local external = {}

local function setting_value(name)
  local setting = settings.global[name]
  if not setting then
    return nil
  end

  return setting.value
end

local function is_bridge_enabled()
  return setting_value("factorial-enable-udp-bridge") == true
end

local function export_base_path(player)
  return ("factorial/player-%d"):format(player.index)
end

local function normalize_external_sections(payload)
  if type(payload.sections) == "table" then
    local normalized = {}

    for _, section in ipairs(payload.sections) do
      local items = {}
      if type(section.items) == "table" then
        for _, item in ipairs(section.items) do
          table.insert(items, tostring(item))
        end
      elseif section.text ~= nil then
        items = { tostring(section.text) }
      else
        items = { "No details provided." }
      end

      table.insert(normalized, {
        title = tostring(section.title or "External Notes"),
        items = items
      })
    end

    if #normalized > 0 then
      return normalized
    end
  end

  local text = payload.text or payload.summary or "External advisor response received."
  return {
    {
      title = tostring(payload.title or "External Advisor"),
      items = { tostring(text) }
    }
  }
end

function external.export_snapshot(player, snapshot, report)
  local payload = {
    kind = "factorial-advisor-request",
    snapshot = snapshot,
    local_report = report
  }

  local base_path = export_base_path(player)
  local snapshot_path = base_path .. "/latest_snapshot.json"
  local report_path = base_path .. "/latest_local_report.json"
  local request_path = base_path .. "/latest_request.json"

  helpers.write_file(snapshot_path, helpers.table_to_json(snapshot), false, player.index)
  helpers.write_file(report_path, helpers.table_to_json(report), false, player.index)
  helpers.write_file(request_path, helpers.table_to_json(payload), false, player.index)

  return {
    snapshot = snapshot_path,
    report = report_path,
    request = request_path
  }
end

function external.send_snapshot(player, snapshot, report)
  if not is_bridge_enabled() then
    return false, "Enable the runtime setting 'factorial-enable-udp-bridge' and start Factorio with --enable-lua-udp first."
  end

  local port = setting_value("factorial-udp-port")
  if not port then
    return false, "No UDP port is configured."
  end

  external.export_snapshot(player, snapshot, report)

  local payload = {
    kind = "factorial-advisor-request",
    source = "factorial",
    player_index = player.index,
    player_name = player.name,
    sent_at_tick = game.tick,
    snapshot = snapshot,
    local_report = report
  }

  helpers.send_udp(port, helpers.table_to_json(payload), player.index)
  return true
end

function external.poll_udp()
  if not is_bridge_enabled() then
    return
  end

  if setting_value("factorial-auto-poll-udp") ~= true then
    return
  end

  for _, player in pairs(game.connected_players) do
    helpers.recv_udp(player.index)
  end
end

function external.receive_response(event)
  local player_index = event.player_index
  if not player_index or player_index == 0 then
    return
  end

  local payload = helpers.json_to_table(event.payload)
  if type(payload) ~= "table" then
    advisor.set_external_report(player_index, {
      source = "udp",
      received_at_tick = game.tick,
      summary = "Received a non-JSON UDP response.",
      sections = {
        {
          title = "External Advisor",
          items = {
            tostring(event.payload)
          }
        }
      }
    })
    return
  end

  advisor.set_external_report(player_index, {
    source = tostring(payload.source or "udp"),
    title = tostring(payload.title or "External Advisor"),
    received_at_tick = game.tick,
    summary = tostring(payload.summary or "External response received."),
    sections = normalize_external_sections(payload)
  })
end

return external
