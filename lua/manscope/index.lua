local async = require("manscope.async")
local config = require("manscope.config")
local parse = require("manscope.parse")

local M = {}

local cache
local waiting

local function sysname()
  local uv = vim.uv or vim.loop
  local ok, uname = pcall(uv.os_uname)
  if ok and uname and uname.sysname then
    return string.lower(uname.sysname)
  end
  return ""
end

function M.command()
  local override = config.get().man_cmd
  if type(override) == "table" and override[1] then
    return override
  end
  local name = sysname()
  -- BSD apropos treats an empty query as "match nothing". "." is the usual
  -- "everything" regex there. man-db on Linux accepts an empty query.
  if name == "darwin" or name == "freebsd" or name == "openbsd" or name == "netbsd" then
    return { "apropos", "." }
  end
  return { "apropos", "" }
end

local function deliver(pages, err)
  local callbacks = waiting or {}
  waiting = nil
  if pages then
    cache = pages
  end
  for _, callback in ipairs(callbacks) do
    callback(pages, err)
  end
end

local function parse_catalog(stdout)
  local pages = {}
  local seen = {}
  for line in stdout:gmatch("[^\n]+") do
    local page = parse.apropos_line(line)
    if page then
      local id = page.name .. "\0" .. page.section
      local previous = seen[id]
      if not previous then
        seen[id] = page
        pages[#pages + 1] = page
      elseif #page.description > #previous.description then
        previous.description = page.description
        previous.ordinal = page.ordinal
        previous.names = page.names
      end
    end
  end
  table.sort(pages, function(a, b)
    local left, right = a.name:lower(), b.name:lower()
    if left == right then
      return a.section < b.section
    end
    return left < right
  end)
  return pages
end

--- Load the apropos catalog. Later calls reuse the in-memory cache.
---@param callback fun(pages:table[]|nil, err:string|nil)
function M.pages(callback)
  if cache then
    vim.schedule(function()
      callback(cache, nil)
    end)
    return
  end
  if waiting then
    waiting[#waiting + 1] = callback
    return
  end
  waiting = { callback }

  if vim.fn.executable("apropos") ~= 1 then
    deliver(nil, "apropos was not found on PATH")
    return
  end

  async.run(M.command(), {
    -- apropos truncates descriptions to $COLUMNS even when stdout is a pipe.
    env = { COLUMNS = "4096" },
    timeout = 20000,
  }, function(result)
    if result.stdout == "" then
      local err = result.stderr
      if err == "" then
        err = "apropos returned no man pages"
      end
      deliver(nil, err)
      return
    end
    deliver(parse_catalog(result.stdout), nil)
  end)
end

function M.clear()
  cache = nil
end

return M
