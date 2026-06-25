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
  client = nil,
  project = nil,
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
  if not state.client or not state.project then
    notify("No GitLab pipeline preview is open", vim.log.levels.WARN)
    return
  end

  if state.refreshing then
    return
  end

  state.refreshing = true
  state.client:pipelines_with_jobs(function(pipelines, err)
    state.refreshing = false
    if err then
      ui.render(state, render.error(state.project, err, state))
      return
    end

    ui.render(state, render.render(state.project, pipelines, state))
  end)
end

function M.stop()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
end

function M.open(project_name)
  local project, project_err = config.resolve_project(project_name)
  if project_err then
    notify(project_err, vim.log.levels.ERROR)
    return
  end

  local client, client_err = api.new(project, config.options)
  if client_err then
    notify(client_err, vim.log.levels.ERROR)
    return
  end

  state.project = project
  state.client = client
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
