--- Run a command without a shell. Uses vim.system on Neovim 0.10+ and jobstart before that.

local M = {}

local function schedule(callback, result)
  vim.schedule(function()
    callback(result)
  end)
end

local function run_system(cmd, opts, callback)
  vim.system(cmd, {
    text = true,
    stdin = opts.stdin,
    env = opts.env,
    timeout = opts.timeout,
  }, function(obj)
    schedule(callback, {
      code = obj.code,
      stdout = obj.stdout or "",
      stderr = obj.stderr or "",
    })
  end)
end

local function run_jobstart(cmd, opts, callback)
  local state = { done = false, callback = callback }
  local stdout, stderr = {}, {}

  local function finish(result)
    if state.done then
      return
    end
    state.done = true
    if state.timer then
      pcall(vim.fn.timer_stop, state.timer)
    end
    schedule(callback, result)
  end

  local function drop_trailing_empty(data)
    if data[#data] == "" then
      table.remove(data)
    end
    return table.concat(data, "\n")
  end

  local job_opts = {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        stdout = data
      end
    end,
    on_stderr = function(_, data)
      if data then
        stderr = data
      end
    end,
    on_exit = function(_, code)
      finish({
        code = code,
        stdout = drop_trailing_empty(stdout),
        stderr = drop_trailing_empty(stderr),
      })
    end,
  }

  if opts.env then
    local env = vim.fn.environ()
    for key, value in pairs(opts.env) do
      env[key] = tostring(value)
    end
    job_opts.env = env
  end
  if opts.stdin ~= nil then
    job_opts.stdin = "pipe"
  end

  local job = vim.fn.jobstart(cmd, job_opts)
  if job <= 0 then
    finish({
      code = 1,
      stdout = "",
      stderr = "failed to start " .. tostring(cmd[1]),
    })
    return
  end

  state.timer = vim.fn.timer_start(opts.timeout or 15000, function()
    pcall(vim.fn.jobstop, job)
    finish({
      code = 1,
      stdout = "",
      stderr = "timed out: " .. table.concat(cmd, " "),
    })
  end)

  if opts.stdin ~= nil then
    vim.fn.chansend(job, opts.stdin)
    vim.fn.chanclose(job, "stdin")
  end
end

---@param cmd string[]
---@param opts {env?:table,stdin?:string,timeout?:integer}|nil
---@param callback fun(result:{code:integer,stdout:string,stderr:string})
function M.run(cmd, opts, callback)
  opts = opts or {}
  if vim.system then
    run_system(cmd, opts, callback)
  else
    run_jobstart(cmd, opts, callback)
  end
end

return M
