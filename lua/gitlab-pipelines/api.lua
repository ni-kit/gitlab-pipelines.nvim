local M = {}

local function encode_component(value)
  return tostring(value):gsub("([^%w%-%._~])", function(char)
    return ("%%%02X"):format(string.byte(char))
  end)
end

local function parse_project_url(url)
  local base_url, path = url:match("^(https?://[^/]+)/(.+)$")

  if not base_url or not path then
    return nil, "Only http(s) GitLab project URLs are supported"
  end

  path = path:gsub("[?#].*$", "")
  path = path:gsub("/%-/.*$", "")
  path = path:gsub("%.git$", "")
  path = path:gsub("/+$", "")

  if path == "" then
    return nil, "GitLab project URL does not contain a project path"
  end

  return {
    base_url = base_url,
    project_path = path,
    project_id = encode_component(path),
  }, nil
end

local function decode_json(body)
  local ok, decoded = pcall(vim.json.decode, body)
  if not ok then
    return nil, "GitLab returned invalid JSON"
  end
  return decoded, nil
end

local function build_query(params)
  local parts = {}
  for key, value in pairs(params or {}) do
    if value ~= nil then
      table.insert(parts, ("%s=%s"):format(encode_component(key), encode_component(value)))
    end
  end
  table.sort(parts)
  return table.concat(parts, "&")
end

local function curl_quote(value)
  return tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function chomp(value)
  local text = tostring(value):gsub("\n+$", "")
  return text
end

local function auth_header(project)
  if type(project.auth_header) == "function" then
    return project.auth_header(project)
  end

  if type(project.auth_header) == "string" and project.auth_header ~= "" then
    return project.auth_header
  end

  local auth_type = project.auth_type or "private-token"
  if auth_type == "bearer" then
    return "Authorization: Bearer " .. project.token
  end

  if auth_type == "job-token" then
    return "JOB-TOKEN: " .. project.token
  end

  return "PRIVATE-TOKEN: " .. project.token
end

local function request_error(result, project, project_info, url)
  local parts = {}
  if result.stderr and result.stderr ~= "" then
    table.insert(parts, chomp(result.stderr))
  end
  if result.stdout and result.stdout ~= "" then
    table.insert(parts, chomp(result.stdout))
  end

  local message = table.concat(parts, "\n")
  if message == "" then
    message = ("curl exited with code %d"):format(result.code)
  end

  if result.code == 22 and message:find("401", 1, true) then
    message = message
      .. ("\nUnauthorized while using auth_type=%s for %s/%s. Check the token, token scopes, and project membership."):format(
        project.auth_type or "private-token",
        project_info.base_url,
        project_info.project_path
      )
  elseif result.code == 22 and message:find("404", 1, true) then
    message = message
      .. ("\nProject not found or hidden from this token: %s/%s"):format(project_info.base_url, project_info.project_path)
  else
    message = message .. ("\nRequest URL: %s"):format(url)
  end

  return message
end

local Client = {}
Client.__index = Client

function Client:request(path, params, callback)
  local query = build_query(params)
  local url = ("%s/api/v4%s%s%s"):format(
    self.project_info.base_url,
    path,
    query ~= "" and "?" or "",
    query
  )

  local curl_config = ('header = "%s"\n'):format(curl_quote(auth_header(self.project)))

  vim.system({
    "curl",
    "--silent",
    "--show-error",
    "--fail-with-body",
    "--connect-timeout",
    tostring(self.project.connect_timeout or 10),
    "--max-time",
    tostring(self.project.request_timeout or 20),
    "--config",
    "-",
    url,
  }, { text = true, stdin = curl_config }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil, request_error(result, self.project, self.project_info, url))
        return
      end

      local decoded, err = decode_json(result.stdout)
      callback(decoded, err)
    end)
  end)
end

function Client:pipelines(callback)
  local project_id = self.project_info.project_id
  self:request(("/projects/%s/pipelines"):format(project_id), {
    per_page = self.options.pipelines_limit,
    order_by = "updated_at",
    sort = "desc",
  }, callback)
end

function Client:pipeline(pipeline_id, callback)
  local project_id = self.project_info.project_id
  self:request(("/projects/%s/pipelines/%s"):format(project_id, pipeline_id), nil, callback)
end

function Client:jobs(pipeline_id, callback)
  local project_id = self.project_info.project_id
  self:request(("/projects/%s/pipelines/%s/jobs"):format(project_id, pipeline_id), {
    per_page = self.options.jobs_limit,
    include_retried = "false",
  }, callback)
end

function Client:with_pipeline_data(pipelines, limit, fetch, apply, callback)
  local remaining = math.min(limit or #pipelines, #pipelines)
  if remaining == 0 then
    callback(pipelines, nil)
    return
  end

  local first_error
  for index = 1, remaining do
    fetch(pipelines[index], function(data, err)
      if err and not first_error then
        first_error = err
      elseif data then
        apply(pipelines, index, data)
      end

      remaining = remaining - 1
      if remaining == 0 then
        callback(pipelines, first_error)
      end
    end)
  end
end

function Client:add_pipeline_details(pipelines, callback)
  self:with_pipeline_data(pipelines, #pipelines, function(pipeline, done)
    self:pipeline(pipeline.id, done)
  end, function(target, index, details)
    target[index] = vim.tbl_deep_extend("force", target[index], details)
  end, callback)
end

function Client:add_pipeline_jobs(pipelines, callback)
  self:with_pipeline_data(pipelines, self.options.jobs_for_pipelines, function(pipeline, done)
    self:jobs(pipeline.id, done)
  end, function(target, index, jobs)
    target[index].jobs = jobs or {}
  end, callback)
end

function Client:pipelines_with_jobs(callback)
  self:pipelines(function(pipelines, err)
    if err then
      callback(nil, err)
      return
    end

    if #pipelines == 0 then
      callback(pipelines, nil)
      return
    end

    self:add_pipeline_details(pipelines, function(pipelines_with_details, details_err)
      if details_err then
        callback(nil, details_err)
        return
      end

      if not self.options.show_jobs then
        callback(pipelines_with_details, nil)
        return
      end

      self:add_pipeline_jobs(pipelines_with_details, callback)
    end)
  end)
end

function M.new(project, options)
  local project_info, err = parse_project_url(project.url)
  if err then
    return nil, err
  end

  return setmetatable({
    project = project,
    project_info = project_info,
    options = options,
  }, Client)
end

return M
