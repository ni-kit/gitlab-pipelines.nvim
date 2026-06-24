if vim.g.loaded_gitlab_pipelines == 1 then
	return
end

vim.g.loaded_gitlab_pipelines = 1

local gitlab_pipelines = require("gitlab-pipelines")

vim.api.nvim_create_user_command("GitLabPipelinesOpen", function(opts)
	gitlab_pipelines.open(opts.args ~= "" and opts.args or nil)
end, {
	nargs = "?",
	complete = function()
		return gitlab_pipelines.project_names()
	end,
})

vim.api.nvim_create_user_command("GitLabPipelinesRefresh", function()
	gitlab_pipelines.refresh()
end, {})

vim.api.nvim_create_user_command("GitLabPipelinesStop", function()
	gitlab_pipelines.stop()
end, {})

vim.api.nvim_create_user_command("GitLabPipelinesClose", function()
	gitlab_pipelines.close()
end, {})
