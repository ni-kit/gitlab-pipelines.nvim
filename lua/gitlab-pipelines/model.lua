local time = require("gitlab-pipelines.time")

local M = {}

local unfinished_statuses = {
  created = true,
  pending = true,
  running = true,
  scheduled = true,
}

function M.group_jobs(jobs)
  local groups = {}
  local index_by_stage = {}

  for _, job in ipairs(jobs or {}) do
    if job.status ~= "manual" then
      local stage = job.stage or "-"
      local index = index_by_stage[stage]
      if not index then
        table.insert(groups, {
          stage = stage,
          jobs = {},
          order = #groups + 1,
          stage_idx = job.stage_idx,
        })
        index = #groups
        index_by_stage[stage] = index
      elseif groups[index].stage_idx == nil and job.stage_idx ~= nil then
        groups[index].stage_idx = job.stage_idx
      end

      table.insert(groups[index].jobs, job)
    end
  end

  -- GitLab returns jobs newest-first for this endpoint in practice, so fallback
  -- stage order intentionally reverses first-seen order when stage_idx is absent.
  table.sort(groups, function(left, right)
    if left.stage_idx ~= nil and right.stage_idx ~= nil and left.stage_idx ~= right.stage_idx then
      return left.stage_idx > right.stage_idx
    end
    if left.stage_idx ~= nil and right.stage_idx == nil then
      return true
    end
    if left.stage_idx == nil and right.stage_idx ~= nil then
      return false
    end
    return left.order > right.order
  end)

  for _, group in ipairs(groups) do
    table.sort(group.jobs, function(left, right)
      return (left.name or "") < (right.name or "")
    end)
  end

  return groups
end

function M.stage_status(group)
  local counts = {}
  for _, job in ipairs(group.jobs) do
    counts[job.status or "unknown"] = true
  end

  if counts.failed then
    return "failed"
  end
  if counts.running then
    return "running"
  end
  if counts.pending or counts.created or counts.scheduled then
    return "pending"
  end
  if counts.canceled then
    return "canceled"
  end
  if counts.success or counts.skipped then
    return "success"
  end
  return "unknown"
end

function M.pipeline_finished(pipeline)
  return not unfinished_statuses[pipeline.status or "unknown"]
end

local function job_names_with_status(groups, status)
  local names = {}
  for _, group in ipairs(groups) do
    for _, job in ipairs(group.jobs) do
      if job.status == status then
        table.insert(names, job.name or "-")
      end
    end
  end
  return names
end

function M.notable_job_names(pipeline, groups)
  if M.pipeline_finished(pipeline) then
    return job_names_with_status(groups, "failed")
  end
  return job_names_with_status(groups, "running")
end

function M.pipeline_items(pipelines)
  local items = {}
  local max_stage_count = 0

  for _, pipeline in ipairs(pipelines or {}) do
    local groups = M.group_jobs(pipeline.jobs)

    table.insert(items, {
      pipeline = pipeline,
      groups = groups,
      notable_jobs = M.notable_job_names(pipeline, groups),
    })
    max_stage_count = math.max(max_stage_count, #groups)
  end

  table.sort(items, function(left, right)
    local left_started = time.parse_gitlab_time(left.pipeline.started_at) or 0
    local right_started = time.parse_gitlab_time(right.pipeline.started_at) or 0
    if left_started == right_started then
      return (left.pipeline.id or left.pipeline.iid or 0) > (right.pipeline.id or right.pipeline.iid or 0)
    end
    return left_started > right_started
  end)

  return items, max_stage_count
end

return M
