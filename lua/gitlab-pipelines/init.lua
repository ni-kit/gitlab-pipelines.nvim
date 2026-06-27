local api = require("gitlab-pipelines.api")
local config = require("gitlab-pipelines.config")
local render = require("gitlab-pipelines.render")
local ui = require("gitlab-pipelines.ui")

local M = {}

local uv = vim.uv or vim.loop

local state = {
  buf = nil,
  win = nil,
  timer = nil,
  entries = {},
  refresh_interval = config.defaults.refresh_interval,
  hide_headers = config.defaults.hide_headers,
  max_job_name_length = config.defaults.max_job_name_length,
  refreshing = false,
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "gitlab-pipelines.nvim" })
end

function M.setup(opts)
  config.setup(opts)
end

function M.project_names()
  return config.project_names()
end

function M.refresh()
  if not state.entries or #state.entries == 0 then
    notify("No GitLab pipeline preview is open", vim.log.levels.WARN)
    return
  end

  if state.refreshing then
    return
  end

  state.refreshing = true

  local remaining = #state.entries

  local function done()
    remaining = remaining - 1
    if remaining > 0 then
      return
    end

    state.refreshing = false

    local sections = {}
    for _, entry in ipairs(state.entries) do
      table.insert(sections, entry.section)
    end
    ui.render(state, render.combine(sections))
  end

  for _, entry in ipairs(state.entries) do
    entry.client:pipelines_with_jobs(function(pipelines, err)
      if err then
        entry.section = render.error(entry.project, err, state)
      else
        entry.section = render.render(entry.project, pipelines, state)
      end
      done()
    end)
  end
end

function M.stop()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
end

function M.open(project_name)
  local projects, resolve_err
  if project_name and project_name ~= "" then
    local project, err = config.resolve_project(project_name)
    if not err then
      projects = { project }
    end
    resolve_err = err
  else
    projects, resolve_err = config.resolve_all()
  end

  if resolve_err then
    notify(resolve_err, vim.log.levels.ERROR)
    return
  end

  local entries = {}
  for _, project in ipairs(projects) do
    local client, client_err = api.new(project, config.options)
    if client_err then
      notify(client_err, vim.log.levels.ERROR)
      return
    end
    table.insert(entries, { project = project, client = client })
  end

  state.entries = entries
  state.refresh_interval = config.options.refresh_interval
  state.hide_headers = config.options.hide_headers
  state.max_job_name_length = config.options.max_job_name_length

  ui.open(state, config.options)
  M.stop()
  state.timer = uv.new_timer()
  state.timer:start(0, state.refresh_interval, vim.schedule_wrap(M.refresh))
end

function M.close()
  M.stop()
  ui.close(state)
end

return M
