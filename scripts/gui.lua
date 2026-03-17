local gui = {}

gui.names = {
  frame = "factorial_advisor_frame",
  header_flow = "factorial_advisor_header_flow",
  body = "factorial_advisor_body",
  refresh_button = "factorial_advisor_refresh_button",
  export_button = "factorial_advisor_export_button",
  external_button = "factorial_advisor_external_button",
  close_button = "factorial_advisor_close_button"
}

local function frame_for(player)
  return player.gui.screen[gui.names.frame]
end

local function destroy_children(element)
  for _, child in pairs(element.children) do
    child.destroy()
  end
end

local function add_section(parent, title, items)
  parent.add({
    type = "label",
    caption = "[font=default-bold]" .. title .. "[/font]"
  })

  for _, item in ipairs(items) do
    local label = parent.add({
      type = "label",
      caption = "- " .. item
    })
    label.style.single_line = false
  end
end

function gui.is_open(player)
  local frame = frame_for(player)
  return frame ~= nil and frame.valid
end

function gui.open(player)
  if gui.is_open(player) then
    return false
  end

  local frame = player.gui.screen.add({
    type = "frame",
    name = gui.names.frame,
    direction = "vertical",
    caption = "Factorial AI Advisor"
  })
  frame.auto_center = true
  frame.style.minimal_width = 620
  frame.style.maximal_height = 720

  local header = frame.add({
    type = "flow",
    name = gui.names.header_flow,
    direction = "horizontal"
  })
  header.add({
    type = "button",
    name = gui.names.refresh_button,
    caption = "Refresh"
  })
  header.add({
    type = "button",
    name = gui.names.export_button,
    caption = "Export"
  })
  header.add({
    type = "button",
    name = gui.names.external_button,
    caption = "Ask External"
  })
  header.add({
    type = "button",
    name = gui.names.close_button,
    caption = "Close"
  })

  local body = frame.add({
    type = "scroll-pane",
    name = gui.names.body,
    direction = "vertical"
  })
  body.style.maximal_height = 640
  body.style.vertically_stretchable = true

  player.opened = frame
  return true
end

function gui.close(player)
  local frame = frame_for(player)
  if frame and frame.valid then
    frame.destroy()
  end
end

function gui.render(player, report, external_report)
  local frame = frame_for(player)
  if not frame or not frame.valid then
    return
  end

  local body = frame[gui.names.body]
  if not body then
    return
  end

  destroy_children(body)

  local summary = body.add({
    type = "label",
    caption = ("[font=default-bold]Stage:[/font] %s\n[font=default-bold]Summary:[/font] %s")
      :format(report.stage.label, report.summary)
  })
  summary.style.single_line = false

  for _, section in ipairs(report.sections) do
    add_section(body, section.title, section.items)
  end

  if external_report and external_report.sections then
    body.add({
      type = "line",
      direction = "horizontal"
    })

    local external_summary = external_report.summary or "External response received."
    local label = body.add({
      type = "label",
      caption = "[font=default-bold]External Advisor[/font]\n" .. external_summary
    })
    label.style.single_line = false

    for _, section in ipairs(external_report.sections) do
      local items = section.items or { section.text or "No details provided." }
      add_section(body, section.title or "External Notes", items)
    end
  end
end

return gui
