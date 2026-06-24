local M = {}

local ns = vim.api.nvim_create_namespace("gitlab-pipelines")

local function set_highlights()
  vim.api.nvim_set_hl(0, "GitLabPipelinesSuccess", { fg = "#7ee787", bold = true })
  vim.api.nvim_set_hl(0, "GitLabPipelinesFailed", { fg = "#ff7b72", bold = true })
  vim.api.nvim_set_hl(0, "GitLabPipelinesCanceled", { fg = "#8b949e", bold = true })
  vim.api.nvim_set_hl(0, "GitLabPipelinesSkipped", { fg = "#8b949e" })
  vim.api.nvim_set_hl(0, "GitLabPipelinesRunning", { fg = "#79c0ff", bold = true })
  vim.api.nvim_set_hl(0, "GitLabPipelinesPending", { fg = "#d29922", bold = true })
  vim.api.nvim_set_hl(0, "GitLabPipelinesCreated", { fg = "#a5d6ff" })
  vim.api.nvim_set_hl(0, "GitLabPipelinesManual", { fg = "#d2a8ff", bold = true })
  vim.api.nvim_set_hl(0, "GitLabPipelinesScheduled", { fg = "#ffa657", bold = true })
  vim.api.nvim_set_hl(0, "GitLabPipelinesStatus", { fg = "#c9d1d9", bold = true })
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

function M.open(state, options)
  set_highlights()

  if valid_win(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  if not valid_buf(state.buf) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = "nofile"
    vim.bo[state.buf].bufhidden = "hide"
    vim.bo[state.buf].buflisted = false
    vim.bo[state.buf].filetype = "gitlab-pipelines"
    vim.bo[state.buf].modifiable = false
    vim.api.nvim_buf_set_name(state.buf, "GitLab Pipelines")
  end

  if options.split == "left" then
    vim.cmd("topleft vertical new")
  elseif options.split == "bottom" then
    vim.cmd("botright new")
  elseif options.split == "top" then
    vim.cmd("topleft new")
  else
    vim.cmd("botright vertical new")
  end

  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, state.buf)

  if options.split == "left" or options.split == "right" then
    vim.api.nvim_win_set_width(state.win, options.width)
  end

  vim.wo[state.win].wrap = false
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
end

function M.render(state, rendered)
  if not valid_buf(state.buf) then
    return
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, rendered.lines)
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

  for line_number, highlights in pairs(rendered.highlights or {}) do
    for _, highlight in ipairs(highlights) do
      vim.api.nvim_buf_set_extmark(state.buf, ns, line_number - 1, highlight.start_col, {
        end_col = highlight.end_col,
        hl_group = highlight.group,
      })
    end
  end

  vim.bo[state.buf].modifiable = false
end

function M.close(state)
  if valid_win(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

return M
