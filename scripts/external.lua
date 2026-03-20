local advisor = require("scripts.advisor")

local external = {}

-- Max safe UDP payload size (macOS limits localhost UDP to ~8KB)
local MAX_CHUNK_SIZE = 7000

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

function external.export_snapshot(player, snapshot, report, scope)
  scope = scope or "global"
  local payload = {
    kind = "factorial-advisor-request",
    scope = scope,
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

--- Send a JSON payload over UDP, chunking if it exceeds MAX_CHUNK_SIZE.
--- Each chunk is a JSON object with a header and a data fragment:
---   {"_chunked":true,"_msg_id":"<id>","_part":<n>,"_total":<n>,"_data":"<fragment>"}
--- Small payloads (<= MAX_CHUNK_SIZE) are sent as-is (no chunking header).
local function send_chunked_udp(port, json_payload, player_index)
  if #json_payload <= MAX_CHUNK_SIZE then
    -- Small enough to send in a single packet
    local ok, err = pcall(helpers.send_udp, port, json_payload, player_index)
    if not ok then
      return false, tostring(err)
    end
    return true
  end

  -- Generate a unique message ID from tick + player index
  local msg_id = tostring(game.tick) .. "_" .. tostring(player_index)

  -- Calculate how many chunks we need
  -- Reserve space for the chunk header JSON wrapper (~120 bytes)
  local header_overhead = 150
  local data_chunk_size = MAX_CHUNK_SIZE - header_overhead
  local total_parts = math.ceil(#json_payload / data_chunk_size)

  for part = 1, total_parts do
    local start_idx = (part - 1) * data_chunk_size + 1
    local end_idx = math.min(part * data_chunk_size, #json_payload)
    local fragment = json_payload:sub(start_idx, end_idx)

    -- Escape the fragment for embedding in JSON string value
    -- We need to escape backslashes and double quotes
    fragment = fragment:gsub("\\", "\\\\")
    fragment = fragment:gsub('"', '\\"')
    fragment = fragment:gsub("\n", "\\n")
    fragment = fragment:gsub("\r", "\\r")
    fragment = fragment:gsub("\t", "\\t")

    local chunk_json = ('{"_chunked":true,"_msg_id":"%s","_part":%d,"_total":%d,"_data":"%s"}'):format(
      msg_id, part, total_parts, fragment
    )

    local ok, err = pcall(helpers.send_udp, port, chunk_json, player_index)
    if not ok then
      return false, ("Chunk %d/%d failed: %s"):format(part, total_parts, tostring(err))
    end
  end

  return true
end

--- Map external report source to backend name for requests.
--- The external report stores "claude" or "lmstudio" as the source,
--- but the bridge expects "anthropic" or "lmstudio" as backend.
local function source_to_backend(source)
  if source == "lmstudio" then
    return "lmstudio"
  end
  -- "claude", "claude-bridge", "udp", or anything else -> anthropic
  return "anthropic"
end

--- Build the common payload for external requests, with an optional backend override.
local function build_payload(player, snapshot, report, backend, scope)
  scope = scope or "global"
  local payload = {
    kind = "factorial-advisor-request",
    source = "factorial",
    backend = backend or "anthropic",
    scope = scope,
    player_index = player.index,
    player_name = player.name,
    sent_at_tick = game.tick,
    snapshot = snapshot,
    local_report = report
  }

  -- Include LM Studio URL when using that backend
  if backend == "lmstudio" then
    payload.lmstudio_url = setting_value("factorial-lmstudio-url") or "http://192.168.1.53:1234"
  end

  return payload
end

--- Send a snapshot to the bridge with the specified backend.
--- Returns ok, message.
local function send_to_bridge(player, snapshot, report, backend, scope)
  if not is_bridge_enabled() then
    local receive_port = setting_value("factorial-udp-receive-port") or 34199
    local bridge_port = setting_value("factorial-udp-port") or 34198
    return false, ("Enable the runtime setting 'factorial-enable-udp-bridge' and start Factorio with --enable-lua-udp=%d. The bridge must listen on %d."):format(receive_port, bridge_port)
  end

  local port = setting_value("factorial-udp-port")
  if not port then
    return false, "No UDP port is configured."
  end

  external.export_snapshot(player, snapshot, report, scope)

  local payload = build_payload(player, snapshot, report, backend, scope)
  local json_payload = helpers.table_to_json(payload)
  local ok, err = send_chunked_udp(port, json_payload, player.index)
  if not ok then
    local receive_port = setting_value("factorial-udp-receive-port") or 34199
    return false, ("send_udp failed: %s. Make sure Factorio was started with --enable-lua-udp=%d."):format(tostring(err), receive_port)
  end

  return true
end

function external.send_snapshot(player, snapshot, report, scope)
  return send_to_bridge(player, snapshot, report, "anthropic", scope)
end

function external.send_snapshot_local_llm(player, snapshot, report, scope)
  return send_to_bridge(player, snapshot, report, "lmstudio", scope)
end

--- Send a detail request for a specific recommendation item.
--- @param player LuaPlayer
--- @param item_text string The recommendation text to get more detail on
--- @param section_title string The section the item belongs to
--- @param detail_key string Cache key e.g. "1_2"
--- @param backend_source string The source from the external report ("claude" or "lmstudio")
function external.send_detail_request(player, item_text, section_title, detail_key, backend_source)
  if not is_bridge_enabled() then
    local receive_port = setting_value("factorial-udp-receive-port") or 34199
    local bridge_port = setting_value("factorial-udp-port") or 34198
    return false, ("Enable the runtime setting 'factorial-enable-udp-bridge' and start Factorio with --enable-lua-udp=%d. The bridge must listen on %d."):format(receive_port, bridge_port)
  end

  local port = setting_value("factorial-udp-port")
  if not port then
    return false, "No UDP port is configured."
  end

  local snapshot = advisor.get_last_snapshot(player.index)
  local report = advisor.get_last_report(player.index)
  local backend = source_to_backend(backend_source)

  local payload = {
    kind = "factorial-advisor-detail-request",
    source = "factorial",
    backend = backend,
    detail_key = detail_key,
    item_text = item_text,
    section_title = section_title,
    player_index = player.index,
    player_name = player.name,
    sent_at_tick = game.tick,
    snapshot = snapshot or {},
    local_report = report or {}
  }

  if backend == "lmstudio" then
    payload.lmstudio_url = setting_value("factorial-lmstudio-url") or "http://192.168.1.53:1234"
  end

  local json_payload = helpers.table_to_json(payload)
  local ok, err = send_chunked_udp(port, json_payload, player.index)
  if not ok then
    local receive_port = setting_value("factorial-udp-receive-port") or 34199
    return false, ("send_udp failed: %s. Make sure Factorio was started with --enable-lua-udp=%d."):format(tostring(err), receive_port)
  end

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

--- Process an incoming UDP response.
--- Returns "detail" if this was a detail response, "report" for a full report, or nil on error.
function external.receive_response(event)
  local player_index = event.player_index
  if not player_index or player_index == 0 then
    return nil
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
    return "report"
  end

  -- Check if this is a detail response (for "get more info" requests)
  if payload.kind == "factorial-advisor-detail-response" then
    local detail_key = payload.detail_key
    local detail_text = payload.detail_text
    if detail_key and detail_text then
      advisor.set_detail(player_index, tostring(detail_key), tostring(detail_text))
    end
    return "detail"
  end

  -- Standard full report response
  advisor.set_external_report(player_index, {
    source = tostring(payload.source or "udp"),
    title = tostring(payload.title or "External Advisor"),
    received_at_tick = game.tick,
    summary = tostring(payload.summary or "External response received."),
    sections = normalize_external_sections(payload)
  })
  return "report"
end

return external
