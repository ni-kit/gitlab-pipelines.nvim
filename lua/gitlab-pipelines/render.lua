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
	{ key = "id", label = "Pipeline" },
	{ key = "commit", label = "Commit" },
	{ key = "started_at", label = "Started" },
	{ key = "elapsed", label = "Elapsed" },
}

local function pad_right(text, width)
	local pad = width - display_width(text)
	if pad > 0 then
		text = text .. string.rep(" ", pad)
	end
	return text
end

local function column_width(column, id_width)
	if column.key == "id" then
		return math.max(id_width or 0, display_width(column.label))
	end
	return display_width(column.label)
end

local function join_pipeline_columns(values, id_width)
	local parts = {}
	for _, column in ipairs(pipeline_columns) do
		local text = values[column.key] or column.label
		if column.key == "id" then
			text = pad_right(text, column_width(column, id_width))
		end
		table.insert(parts, text)
	end
	return table.concat(parts, " ")
end

local function pipeline_header(stage_width, id_width)
	local line = "  " .. join_pipeline_columns({}, id_width)
	if stage_width > 0 then
		line = line .. " Stages Jobs"
	end
	return line
end

local function pipeline_rule(stage_width, id_width)
	local parts = {}
	for _, column in ipairs(pipeline_columns) do
		table.insert(parts, string.rep("-", column_width(column, id_width)))
	end
	local line = "  " .. table.concat(parts, " ")
	if stage_width > 0 then
		line = line .. " ------ ----"
	end
	return line
end

local function compact_stage_width(stage_count)
	if stage_count <= 0 then
		return 0
	end
	return stage_count * 2 - 1
end

local function merge_request_iid(pipeline)
	local ref = pipeline.ref
	if type(ref) ~= "string" then
		return nil
	end
	return ref:match("^refs/merge%-requests/(%d+)/")
end

local function merge_request_url(pipeline, mr_iid)
	if not mr_iid then
		return nil
	end
	local web_url = pipeline.web_url
	if type(web_url) ~= "string" then
		return nil
	end
	local root = web_url:match("^(.-)/%-/pipelines/")
	if not root then
		return nil
	end
	return ("%s/-/merge_requests/%s"):format(root, mr_iid)
end

local function pipeline_id_segment(pipeline)
	local id = pipeline.id or pipeline.iid or "-"
	local id_text = tostring(id)
	local links = {}

	if type(pipeline.web_url) == "string" then
		table.insert(links, { start_col = 0, end_col = #id_text, url = pipeline.web_url })
	end

	local mr_iid = merge_request_iid(pipeline)
	if mr_iid then
		local mr_start = #id_text -- include the "@" in the pale span
		id_text = id_text .. "@" .. mr_iid
		local mr_url = merge_request_url(pipeline, mr_iid)
		table.insert(links, {
			start_col = mr_start,
			end_col = #id_text,
			url = mr_url,
			group = "GitLabPipelinesMergeRequest",
		})
	end

	return id_text, links
end

local function pipeline_line(pipeline, id_text, id_width)
	local sha = pipeline.sha and pipeline.sha:sub(1, 8) or "-"
	id_text = id_text or pipeline_id_segment(pipeline)

	return join_pipeline_columns({
		id = id_text,
		commit = sha,
		started_at = time.format_started_at(pipeline.started_at),
		elapsed = time.format_duration(time.elapsed(pipeline)),
	}, id_width)
end

local function compact_pipeline_line(item, stage_width, state, id_width)
	local highlights = {}
	local links = {}
	local line = append_segment("", highlights, status_box, status_group(item.pipeline.status or "unknown"))

	-- id segment starts right after the status box and its trailing space
	local id_text, id_links = pipeline_id_segment(item.pipeline)
	local id_base = #line + 1
	for _, link in ipairs(id_links) do
		local start_col = id_base + link.start_col
		local end_col = id_base + link.end_col
		if link.url then
			table.insert(links, { start_col = start_col, end_col = end_col, url = link.url })
		end
		table.insert(highlights, { group = link.group or "Underlined", start_col = start_col, end_col = end_col })
	end

	line = append_segment(line, highlights, " " .. pipeline_line(item.pipeline, id_text, id_width), nil)

	if stage_width > 0 then
		line = append_segment(line, highlights, " ", nil)
		local stage_start_width = display_width(line)

		for index, group in ipairs(item.groups) do
			if index > 1 then
				line = append_segment(line, highlights, " ", nil)
			end
			line = append_segment(line, highlights, status_box, status_group(model.stage_status(group)))
		end

		line = append_segment(
			line,
			highlights,
			string.rep(" ", stage_width - (display_width(line) - stage_start_width)),
			nil
		)
	end

	if #item.notable_jobs > 0 then
		local names = {}
		for _, name in ipairs(item.notable_jobs) do
			table.insert(names, truncate_text(name, state.max_job_name_length))
		end
		line = append_segment(line, highlights, table.concat(names, ", "), nil)
	end

	return line, highlights, links, item.pipeline.web_url
end

function M.render(project, pipelines, state)
	local result = {
		lines = {},
		highlights = {},
		links = {},
	}

	if not state.hide_headers then
		add_line(result, (" GitLab Pipelines - %s"):format(project.name or project.url))
		add_line(
			result,
			(" Updated %s | polling every %.1fs"):format(os.date("%Y-%m-%d %H:%M:%S"), state.refresh_interval / 1000)
		)
		add_line(result, "")
	end

	if not pipelines or #pipelines == 0 then
		if not state.hide_headers then
			add_line(result, pipeline_header(0))
			add_line(result, pipeline_rule(0))
		end
		add_line(result, " No pipelines found")
		return result
	end

	local items, max_stage_count = model.pipeline_items(pipelines, state)
	local stage_width = compact_stage_width(max_stage_count)

	local id_width = 0
	for _, item in ipairs(items) do
		id_width = math.max(id_width, display_width((pipeline_id_segment(item.pipeline))))
	end

	if not state.hide_headers then
		add_line(result, pipeline_header(stage_width, id_width))
		add_line(result, pipeline_rule(stage_width, id_width))
	end

	for _, item in ipairs(items) do
		local line, highlights, links, fallback_url = compact_pipeline_line(item, stage_width, state, id_width)
		add_line(result, line, highlights)
		result.links[#result.lines] = { regions = links, fallback = fallback_url }
	end

	return result
end

function M.url_at(rendered, line_number, col)
	local entry = rendered.links and rendered.links[line_number]
	if not entry then
		return nil
	end

	for _, region in ipairs(entry.regions or {}) do
		if col >= region.start_col and col < region.end_col then
			return region.url
		end
	end

	return entry.fallback
end

function M.error(project, message, state)
	local lines = {}

	if not state.hide_headers then
		table.insert(lines, (" GitLab Pipelines - %s"):format(project and project.name or "unknown"))
		table.insert(
			lines,
			(" Updated %s | polling every %.1fs"):format(os.date("%Y-%m-%d %H:%M:%S"), state.refresh_interval / 1000)
		)
		table.insert(lines, "")
	end

	local error_line = #lines + 1
	table.insert(lines, " Error")

	for _, line in ipairs(vim.split(tostring(message), "\n", { plain = true })) do
		table.insert(lines, " " .. line)
	end

	return {
		lines = lines,
		highlights = {
			[error_line] = {
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
