local model = require("gitlab-pipelines.model")
local time = require("gitlab-pipelines.time")

local M = {}

local status_groups = {
  success = "GitLabPipelinesSuccess",
  failed = "GitLabPipelinesFailed",
  canceled = "GitLabPipelinesCanceled",
  skipped = "GitLabPipelinesSkipped",
  running = "GitLabPipelinesRunning",
  pending = "GitLabPipelinesPending",
  created = "GitLabPipelinesCreated",
  manual = "GitLabPipelinesManual",
  scheduled = "GitLabPipelinesScheduled",
}

local status_box = "■"

local function add_line(result, line, highlights)
  table.insert(result.lines, line)
  if highlights then
    result.highlights[#result.lines] = highlights
  end
end

local function append_segment(line, highlights, text, group)
  local start_col = #line
  line = line .. text

  if group then
    table.insert(highlights, {
      group = group,
      start_col = start_col,
      end_col = start_col + #text,
    })
  end

  return line
end

local function display_width(text)
  return vim.fn.strdisplaywidth(text)
end

local function pad_right(text, width)
  local padding = width - display_width(text)
  if padding <= 0 then
    return text
  end
  return text .. string.rep(" ", padding)
end

local function truncate_text(text, max_width)
  text = tostring(text or "-")
  max_width = tonumber(max_width)

  if not max_width or max_width <= 0 or display_width(text) <= max_width then
    return text
  end

  if max_width == 1 then
    return "…"
  end

  return text:sub(1, max_width - 1) .. "…"
end

local function status_group(status)
  return status_groups[status] or "GitLabPipelinesStatus"
end

local pipeline_columns = {
  { key = "id", label = "Pipeline", width = 11 },
  { key = "commit", label = "Commit", width = 10 },
  { key = "started_at", label = "Started", width = 8 },
  { key = "elapsed", label = "Elapsed", width = 8 },
}

local function join_pipeline_columns(values)
  local parts = {}
  for _, column in ipairs(pipeline_columns) do
    table.insert(parts, pad_right(values[column.key] or column.label, column.width))
  end
  return table.concat(parts, " ")
end

local function pipeline_header(stage_width)
  local line = "  " .. join_pipeline_columns({})
  if stage_width > 0 then
    line = line .. " " .. pad_right("Stages", stage_width) .. " Jobs"
  end
  return line
end

local function pipeline_rule(stage_width)
  local parts = {}
  for _, column in ipairs(pipeline_columns) do
    table.insert(parts, string.rep("-", column.width))
  end
  local line = "  " .. table.concat(parts, " ")
  if stage_width > 0 then
    line = line .. " " .. string.rep("-", stage_width) .. " ----"
  end
  return line
end

local function compact_stage_width(stage_count)
  if stage_count <= 0 then
    return 0
  end
  return stage_count * 2 - 1
end

local function pipeline_line(pipeline)
  local sha = pipeline.sha and pipeline.sha:sub(1, 8) or "-"
  local id = pipeline.id or pipeline.iid or "-"

  return join_pipeline_columns({
    id = tostring(id),
    commit = sha,
    started_at = time.format_started_at(pipeline.started_at),
    elapsed = time.format_duration(time.elapsed(pipeline)),
  })
end

local function compact_pipeline_line(item, stage_width, state)
  local highlights = {}
  local line = append_segment("", highlights, status_box, status_group(item.pipeline.status or "unknown"))
  line = append_segment(line, highlights, " " .. pipeline_line(item.pipeline), nil)

  if stage_width > 0 then
    line = append_segment(line, highlights, " ", nil)
    local stage_start_width = display_width(line)

    for index, group in ipairs(item.groups) do
      if index > 1 then
        line = append_segment(line, highlights, " ", nil)
      end
      line = append_segment(line, highlights, status_box, status_group(model.stage_status(group)))
    end

    line = append_segment(line, highlights, string.rep(" ", stage_width - (display_width(line) - stage_start_width)), nil)
  end

  if #item.notable_jobs > 0 then
    local names = {}
    for _, name in ipairs(item.notable_jobs) do
      table.insert(names, truncate_text(name, state.max_job_name_length))
    end
    line = append_segment(line, highlights, " (" .. table.concat(names, ", ") .. ")", nil)
  end

  return line, highlights
end

function M.render(project, pipelines, state)
  local result = {
    lines = {},
    highlights = {},
  }

  add_line(result, (" GitLab Pipelines - %s"):format(project.name or project.url))
  add_line(result, (" Updated %s | polling every %.1fs"):format(
    os.date("%Y-%m-%d %H:%M:%S"),
    state.refresh_interval / 1000
  ))
  add_line(result, "")

  if not pipelines or #pipelines == 0 then
    add_line(result, pipeline_header(0))
    add_line(result, pipeline_rule(0))
    add_line(result, " No pipelines found")
    return result
  end

  local items, max_stage_count = model.pipeline_items(pipelines, state)
  local stage_width = compact_stage_width(max_stage_count)
  add_line(result, pipeline_header(stage_width))
  add_line(result, pipeline_rule(stage_width))

  for _, item in ipairs(items) do
    local line, highlights = compact_pipeline_line(item, stage_width, state)
    add_line(result, line, highlights)
  end

  return result
end

function M.error(project, message, state)
  local lines = {
    (" GitLab Pipelines - %s"):format(project and project.name or "unknown"),
    (" Updated %s | polling every %.1fs"):format(os.date("%Y-%m-%d %H:%M:%S"), state.refresh_interval / 1000),
    "",
    " Error",
  }

  for _, line in ipairs(vim.split(tostring(message), "\n", { plain = true })) do
    table.insert(lines, " " .. line)
  end

  return {
    lines = lines,
    highlights = {
      [4] = {
        {
          group = "GitLabPipelinesFailed",
          start_col = 1,
          end_col = 6,
        },
      },
    },
  }
end

return M
