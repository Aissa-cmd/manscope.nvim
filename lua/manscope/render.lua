local async = require("manscope.async")

local M = {}

local cache = {}
local waiting = {}

local function split_lines(text)
  text = text:gsub("\r", ""):gsub("\027%[[0-9;]*m", "")
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

local function deliver(key, lines, err)
  cache[key] = { lines = lines, err = err }
  local callbacks = waiting[key] or {}
  waiting[key] = nil
  for _, callback in ipairs(callbacks) do
    callback(lines, err)
  end
end

local function finish_plain(key, text, err)
  if err then
    deliver(key, nil, err)
    return
  end
  deliver(key, split_lines(text), nil)
end

---@param section string
---@param name string
---@param width integer
---@param callback fun(lines:string[]|nil, err:string|nil)
function M.page(section, name, width, callback)
  width = math.floor(width or 80)
  if width < 36 then
    width = 36
  elseif width > 200 then
    width = 200
  end
  local key = string.format("%s\0%s\0%d", section, name, width)
  local cached = cache[key]
  if cached then
    vim.schedule(function()
      callback(cached.lines, cached.err)
    end)
    return
  end
  if waiting[key] then
    table.insert(waiting[key], callback)
    return
  end
  waiting[key] = { callback }

  if vim.fn.executable("man") ~= 1 then
    deliver(key, nil, "man was not found on PATH")
    return
  end

  async.run({ "man", section, name }, {
    timeout = 15000,
    env = {
      MANPAGER = "cat",
      PAGER = "cat",
      MANWIDTH = tostring(width),
      -- groff 1.23 emits ANSI SGR by default. Force overstrike so `col -bx`
      -- can turn bold/underline into plain text the man syntax can read.
      GROFF_NO_SGR = "1",
      MAN_KEEP_FORMATTING = "1",
    },
  }, function(result)
    if result.stdout == "" then
      local err = result.stderr
      if err == "" then
        err = string.format("no manual entry for %s(%s)", name, section)
      end
      finish_plain(key, nil, vim.trim(err))
      return
    end
    if vim.fn.executable("col") ~= 1 then
      finish_plain(key, result.stdout, nil)
      return
    end
    async.run({ "col", "-bx" }, { stdin = result.stdout, timeout = 10000 }, function(stripped)
      local text = stripped.code == 0 and stripped.stdout ~= "" and stripped.stdout or result.stdout
      finish_plain(key, text, nil)
    end)
  end)
end

function M.clear()
  cache = {}
  waiting = {}
end

--- Width of the preview column from the current screen and the configured layout.
function M.document_width()
  local layout = require("manscope.config").get().layout
  local preview = layout.preview_width
  if type(preview) ~= "number" then
    preview = 0.58
  end
  local picker = layout.width
  if type(picker) ~= "number" then
    picker = 0.92
  end
  local width = math.floor(vim.o.columns * picker * preview) - 4
  if width < 36 then
    width = 36
  elseif width > 200 then
    width = 200
  end
  return width
end

return M
