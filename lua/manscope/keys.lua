local config = require("manscope.config")

local M = {}

local applied = false

local commands = {
  search = function()
    require("manscope").search()
  end,
  cword = function()
    local word = vim.fn.expand("<cword>")
    if word == "" then
      vim.notify("manscope: no word under the cursor", vim.log.levels.WARN)
      return
    end
    require("manscope").search({ query = word })
  end,
  history = function()
    require("manscope").history()
  end,
  headings = function()
    require("manscope").headings()
  end,
  lines = function()
    require("manscope").lines()
  end,
}

local function bind(spec)
  local lhs = spec[1]
  local action = spec[2]
  if type(lhs) ~= "string" or lhs == "" or type(action) ~= "string" then
    return
  end
  local fn = commands[action]
  if not fn then
    vim.notify("manscope: unknown key action '" .. action .. "'", vim.log.levels.WARN)
    return
  end
  vim.keymap.set(spec.mode or "n", lhs, fn, {
    desc = spec.desc,
    silent = true,
  })
end

--- which-key reads `desc` on keymaps by itself. The group name is separate:
--- without it the leader popup shows "+m" instead of "man".
local function register_group(groups)
  if not package.loaded["which-key"] then
    return false
  end
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk) ~= "table" then
    return false
  end
  if type(wk.add) == "function" then
    return pcall(wk.add, groups)
  end
  if type(wk.register) == "function" then
    local legacy = {}
    for _, item in ipairs(groups) do
      if item[1] and item.group then
        legacy[item[1]] = { name = item.group }
      end
    end
    return pcall(wk.register, legacy)
  end
  return false
end

local function schedule_group(groups)
  if register_group(groups) then
    return
  end
  local group = vim.api.nvim_create_augroup("manscope_which_key", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "VeryLazy", "LazyLoad" },
    callback = function(ev)
      if ev.match == "LazyLoad" and ev.data ~= "which-key.nvim" then
        return
      end
      if register_group(groups) then
        return true
      end
    end,
  })
end

function M.apply()
  if applied then
    return
  end
  applied = true

  local opts = config.get()
  if type(opts.keys) == "table" then
    for _, spec in ipairs(opts.keys) do
      bind(spec)
    end
  end
  if type(opts.which_key) == "table" then
    schedule_group(opts.which_key)
  end
end

function M.reset()
  applied = false
end

return M
