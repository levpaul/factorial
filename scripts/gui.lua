local gui = {}

gui.names = {
  frame = "factorial_advisor_frame",
  titlebar = "factorial_advisor_titlebar",
  title_label = "factorial_advisor_title_label",
  content = "factorial_advisor_content",
  status_flow = "factorial_advisor_status_flow",
  body = "factorial_advisor_body",
  button_bar = "factorial_advisor_button_bar",
  refresh_button = "factorial_advisor_refresh_button",
  export_button = "factorial_advisor_export_button",
  external_button = "factorial_advisor_external_button",
  internal_button = "factorial_advisor_internal_button",
  clear_button = "factorial_advisor_clear_button",
  close_button = "factorial_advisor_close_button"
}

local SECTION_ICONS = {
  ["1. What To Focus On Next"] = "item/lab",
  ["2. Biggest Resource Bottleneck"] = "item/iron-plate",
  ["3. New Patterns To Apply"] = "item/blueprint",
  ["4. Upcoming Issues To Address"] = "item/radar",
  ["5. Serious Anti-Patterns"] = "item/deconstruction-planner"
}

local CONTENT_WIDTH = 540

local function frame_for(player)
  return player.gui.screen[gui.names.frame]
end

local function destroy_children(element)
  for _, child in pairs(element.children) do
    child.destroy()
  end
end

local function parse_severity(text)
  local severity, rest = text:match("^%[(%a+)%] (.+)$")
  if severity then
    return severity, rest
  end
  return nil, text
end

local function severity_richtext(severity, text)
  if severity == "High" then
    return "[color=1,0.3,0.3][High][/color] " .. text
  elseif severity == "Medium" then
    return "[color=1,0.8,0.2][Medium][/color] " .. text
  end
  return text
end

local function build_text_content(report, external_report, show_internal)
  local lines = {}

  if show_internal then
    table.insert(lines, "Summary: " .. report.summary)
    table.insert(lines, "")

    for _, section in ipairs(report.sections) do
      table.insert(lines, section.title)
      for _, item in ipairs(section.items) do
        local severity, body = parse_severity(item)
        if severity then
          table.insert(lines, "  [" .. severity .. "] " .. body)
        else
          table.insert(lines, "  " .. item)
        end
      end
      table.insert(lines, "")
    end
  end

  if external_report and external_report.sections then
    table.insert(lines, "External Advisor")
    table.insert(lines, external_report.summary or "External response received.")
    table.insert(lines, "")

    for _, section in ipairs(external_report.sections) do
      table.insert(lines, section.title or "External Notes")
      local items = section.items or { section.text or "No details provided." }
      for _, item in ipairs(items) do
        local severity, body = parse_severity(item)
        if severity then
          table.insert(lines, "  [" .. severity .. "] " .. body)
        else
          table.insert(lines, "  " .. item)
        end
      end
      table.insert(lines, "")
    end
  end

  return table.concat(lines, "\n")
end

local function add_section(parent, title, items)
  -- Section header flow with icon
  local header_flow = parent.add({
    type = "flow",
    direction = "horizontal"
  })
  header_flow.style.vertical_align = "center"
  header_flow.style.top_margin = 4

  local icon = SECTION_ICONS[title]
  if icon then
    header_flow.add({
      type = "sprite",
      sprite = icon,
      resize_to_sprite = false
    }).style.size = {24, 24}
  end

  local title_label = header_flow.add({
    type = "label",
    caption = title,
    style = "caption_label"
  })
  title_label.style.left_margin = icon and 4 or 0

  -- Items
  for _, item in ipairs(items) do
    local severity, body = parse_severity(item)
    local caption = severity_richtext(severity, body)
    local label = parent.add({
      type = "label",
      caption = "  - " .. caption
    })
    label.style.single_line = false
    label.style.maximal_width = CONTENT_WIDTH
  end
end

function gui.is_open(player)
  local frame = frame_for(player)
  return frame ~= nil and frame.valid
end

function gui.set_internal_button_state(player, showing)
  local frame = frame_for(player)
  if not frame or not frame.valid then
    return
  end
  local button_bar = frame[gui.names.button_bar]
  if not button_bar then
    return
  end
  local button = button_bar[gui.names.internal_button]
  if button and button.valid then
    button.caption = showing and "Hide Internal" or "Show Internal"
  end
end

function gui.set_clear_button_visible(player, visible)
  local frame = frame_for(player)
  if not frame or not frame.valid then
    return
  end
  local button_bar = frame[gui.names.button_bar]
  if not button_bar then
    return
  end
  local button = button_bar[gui.names.clear_button]
  if button and button.valid then
    button.visible = visible
  end
end

function gui.has_content(report, external_report)
  -- Check if there's any meaningful content to display
  if report and report.sections and #report.sections > 0 then
    return true
  end
  if external_report and external_report.sections and #external_report.sections > 0 then
    return true
  end
  return false
end

function gui.open(player)
  if gui.is_open(player) then
    return false
  end

  -- Outer frame with no caption (custom titlebar instead)
  local frame = player.gui.screen.add({
    type = "frame",
    name = gui.names.frame,
    direction = "vertical"
  })
  frame.auto_center = true
  frame.style.minimal_width = 620
  frame.style.maximal_height = 720

  -- Draggable titlebar
  local titlebar = frame.add({
    type = "flow",
    name = gui.names.titlebar,
    direction = "horizontal"
  })
  titlebar.style.horizontal_spacing = 8
  titlebar.style.vertically_stretchable = false
  titlebar.drag_target = frame

  local title_label = titlebar.add({
    type = "label",
    name = gui.names.title_label,
    caption = "Factorial AI Advisor",
    style = "frame_title"
  })
  title_label.drag_target = frame

  -- Filler to push close button to the right
  local filler = titlebar.add({
    type = "empty-widget",
    ignored_by_interaction = true
  })
  filler.style.horizontally_stretchable = true

  titlebar.add({
    type = "sprite-button",
    name = gui.names.close_button,
    sprite = "utility/close",
    style = "frame_action_button",
    tooltip = "Close"
  })

  -- Content frame
  local content = frame.add({
    type = "frame",
    name = gui.names.content,
    direction = "vertical",
    style = "inside_shallow_frame_with_padding"
  })

  -- Status bar
  local status_flow = content.add({
    type = "flow",
    name = gui.names.status_flow,
    direction = "horizontal"
  })
  status_flow.style.vertical_align = "center"
  status_flow.style.bottom_margin = 4
  status_flow.style.horizontal_spacing = 12

  -- Separator between status and body
  content.add({
    type = "line",
    direction = "horizontal"
  })

  -- Scroll pane body
  local body = content.add({
    type = "scroll-pane",
    name = gui.names.body,
    direction = "vertical"
  })
  body.style.minimal_height = 400
  body.style.maximal_height = 580
  body.style.vertically_stretchable = true
  body.style.horizontally_stretchable = true

  -- Button bar at the bottom
  local button_bar = frame.add({
    type = "flow",
    name = gui.names.button_bar,
    direction = "horizontal"
  })
  button_bar.style.top_margin = 4
  button_bar.style.horizontal_spacing = 8

  button_bar.add({
    type = "button",
    name = gui.names.refresh_button,
    caption = "Refresh"
  })
  button_bar.add({
    type = "button",
    name = gui.names.export_button,
    caption = "Export"
  })
  button_bar.add({
    type = "button",
    name = gui.names.external_button,
    caption = "Ask External"
  })
  button_bar.add({
    type = "button",
    name = gui.names.internal_button,
    caption = "Show Internal"
  })
  local clear_button = button_bar.add({
    type = "button",
    name = gui.names.clear_button,
    caption = "Clear"
  })
  clear_button.visible = false  -- Hidden by default, shown when there's content

  player.opened = frame
  return true
end

function gui.close(player)
  local frame = frame_for(player)
  if frame and frame.valid then
    frame.destroy()
  end
end

function gui.clear(player)
  local frame = frame_for(player)
  if not frame or not frame.valid then
    return
  end

  local content = frame[gui.names.content]
  if not content then
    return
  end

  local body = content[gui.names.body]
  if body then
    destroy_children(body)
  end

  local status_flow = content[gui.names.status_flow]
  if status_flow then
    destroy_children(status_flow)
  end

  -- Hide Clear button after clearing content
  gui.set_clear_button_visible(player, false)
end

function gui.render(player, report, external_report, show_internal, dev_mode)
  local frame = frame_for(player)
  if not frame or not frame.valid then
    return
  end

  local content = frame[gui.names.content]
  if not content then
    return
  end

  local body = content[gui.names.body]
  if not body then
    return
  end

  -- Show/hide Clear button based on whether there's content
  gui.set_clear_button_visible(player, gui.has_content(report, external_report))

  -- Populate status bar
  local status_flow = content[gui.names.status_flow]
  if status_flow then
    destroy_children(status_flow)

    local stage_label = status_flow.add({
      type = "label",
      caption = "[font=default-bold]Stage:[/font] " .. report.stage.label
    })
    stage_label.style.maximal_width = CONTENT_WIDTH

    if report.stats then
      local stats = report.stats
      local metrics_parts = {}
      if stats.iron_rate then
        table.insert(metrics_parts, ("Iron: %.0f/m"):format(stats.iron_rate))
      end
      if stats.copper_rate then
        table.insert(metrics_parts, ("Cu: %.0f/m"):format(stats.copper_rate))
      end
      if stats.steel_rate then
        table.insert(metrics_parts, ("Steel: %.0f/m"):format(stats.steel_rate))
      end
      if stats.top_science then
        table.insert(metrics_parts, ("Sci: %.1f/m"):format(stats.top_science))
      end
      if stats.evolution then
        table.insert(metrics_parts, ("Evo: %.0f%%"):format(stats.evolution * 100))
      end
      if stats.game_time then
        table.insert(metrics_parts, stats.game_time)
      end

      if #metrics_parts > 0 then
        local metrics_label = status_flow.add({
          type = "label",
          caption = table.concat(metrics_parts, "  |  ")
        })
        metrics_label.style.font_color = {0.7, 0.7, 0.7}
      end
    end
  end

  -- Populate body
  destroy_children(body)

  if dev_mode then
    local text = build_text_content(report, external_report, show_internal)
    if text and text ~= "" then
      local text_box = body.add({
        type = "text-box",
        text = text
      })
      text_box.style.vertically_stretchable = true
      text_box.style.horizontally_stretchable = true
      text_box.style.minimal_width = CONTENT_WIDTH
      text_box.style.maximal_width = CONTENT_WIDTH
      text_box.style.minimal_height = 400
      text_box.read_only = true
    end
  else
    if show_internal then
      local summary = body.add({
        type = "label",
        caption = "[font=default-bold]Summary:[/font] " .. report.summary
      })
      summary.style.single_line = false
      summary.style.maximal_width = CONTENT_WIDTH
      summary.style.bottom_margin = 6

      for i, section in ipairs(report.sections) do
        if i > 1 then
          body.add({
            type = "line",
            direction = "horizontal"
          }).style.top_margin = 4
        end
        add_section(body, section.title, section.items)
      end
    end

    -- External report
    if external_report and external_report.sections then
      body.add({
        type = "line",
        direction = "horizontal"
      }).style.top_margin = 6

      local external_summary = external_report.summary or "External response received."
      local label = body.add({
        type = "label",
        caption = "[font=default-bold]External Advisor[/font]\n" .. external_summary
      })
      label.style.single_line = false
      label.style.maximal_width = CONTENT_WIDTH

      for _, section in ipairs(external_report.sections) do
        local items = section.items or { section.text or "No details provided." }
        add_section(body, section.title or "External Notes", items)
      end
    end
  end
end

return gui
