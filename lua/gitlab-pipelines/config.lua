local M = {}

M.defaults = {
	refresh_interval = 15000,
	pipelines_limit = 10,
	jobs_limit = 100,
	show_jobs = true,
	hide_headers = false,
	max_job_name_length = 13,
	split = "right",
	width = 84,
	open_key = "gx",
	auth_type = "private-token",
	projects = {},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

local function basename(path)
	local name = path:gsub("[/\\]+$", ""):match("([^/\\]+)$")
	return name or path
end

local function find_project(projects, name)
	for _, project in ipairs(projects) do
		if project.name == name then
			return project
		end
	end
	return nil
end

function M.project_names()
	local names = {}
	for _, project in ipairs(M.options.projects or {}) do
		if project.name then
			table.insert(names, project.name)
		end
	end
	return names
end

function M.resolve_all()
	local names = M.project_names()
	if #names == 0 then
		local project, err = M.resolve_project(nil)
		if err then
			return nil, err
		end
		return { project }, nil
	end

	local projects = {}
	for _, name in ipairs(names) do
		local project, err = M.resolve_project(name)
		if err then
			return nil, err
		end
		table.insert(projects, project)
	end
	return projects, nil
end

function M.resolve_project(name)
	local projects = M.options.projects or {}
	local project

	if name and name ~= "" then
		local entry = find_project(projects, name)
		if not entry then
			return nil, ("No GitLab pipeline project named '%s'"):format(name)
		end
		project = vim.tbl_deep_extend("force", { name = name }, entry)
	elseif M.options.project then
		project = vim.tbl_deep_extend("force", { name = "default" }, M.options.project)
	else
		local cwd_name = basename(vim.loop.cwd() or "")
		local entry = find_project(projects, cwd_name)
		if entry then
			project = vim.tbl_deep_extend("force", { name = cwd_name }, entry)
		elseif projects[1] then
			project = vim.tbl_deep_extend("force", { name = projects[1].name }, projects[1])
		end
	end

	if not project then
		return nil, "No GitLab pipeline project configured"
	end

	project.auth_type = project.auth_type or M.options.auth_type

	if type(project.token) == "function" then
		project.token = project.token(project)
	end

	if type(project.token) == "string" then
		project.token = project.token:gsub("^%s+", ""):gsub("%s+$", "")
	end

	if not project.url or project.url == "" then
		return nil, ("Project '%s' is missing url"):format(project.name)
	end

	if not project.token or project.token == "" then
		return nil, ("Project '%s' is missing token"):format(project.name)
	end

	return project, nil
end

return M
