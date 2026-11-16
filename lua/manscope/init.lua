local config = require("manscope.config")

local M = {}

function M.setup(opts)
  config.setup(opts)
end

function M.search(opts)
  require("manscope.picker").pages(opts)
end

function M.history(opts)
  require("manscope.picker").history(opts)
end

function M.headings(opts)
  require("manscope.picker").headings(opts)
end

function M.lines(opts)
  require("manscope.picker").lines(opts)
end

local subcommands = {
  cword = true,
  history = true,
  headings = true,
  lines = true,
  section = true,
}

local function rest(fargs, from)
  return table.concat(vim.list_slice(fargs, from), " ")
end

local function looks_like_section(text)
  return text:match("^%d") ~= nil or text:match("^[nlpox]$") ~= nil
end

local function page_opts(fargs)
  local first = fargs[2]
  if not first or first == "" then
    return {}
  end
  if first:find("(", 1, true) then
    return { ref = first }
  end
  if fargs[3] and looks_like_section(first) then
    return { section = first, name = rest(fargs, 3) }
  end
  return { name = rest(fargs, 2) }
end

function M.command(opts)
  local fargs = opts.fargs or {}
  local sub = fargs[1]
  if sub == "cword" then
    local word = vim.fn.expand("<cword>")
    if word == "" then
      vim.notify("manscope: no word under the cursor", vim.log.levels.WARN)
      return
    end
    M.search({ query = word })
  elseif sub == "history" then
    M.history()
  elseif sub == "headings" then
    M.headings(page_opts(fargs))
  elseif sub == "lines" then
    M.lines(page_opts(fargs))
  elseif sub == "section" then
    local section = fargs[2]
    if not section or section == "" then
      vim.notify("manscope: :Manscope section {number} [query]", vim.log.levels.WARN)
      return
    end
    M.search({
      sections = { section },
      query = rest(fargs, 3),
    })
  elseif sub and subcommands[sub] == nil and sub:find("^%-") then
    vim.notify("manscope: unknown command " .. sub, vim.log.levels.WARN)
  else
    M.search({ query = table.concat(fargs, " ") })
  end
end

function M.complete(arglead, cmdline)
  cmdline = cmdline:gsub("^%s*:", "")
  local parts = vim.split(cmdline, "%s+", { trimempty = true })
  for index, part in ipairs(parts) do
    if part == "Manscope" or part:match("Manscope$") then
      parts = vim.list_slice(parts, index)
      break
    end
  end
  local sub = parts[2]
  local names = { "cword", "history", "headings", "lines", "section" }
  local function matching(items)
    return vim.tbl_filter(function(item)
      return vim.startswith(item, arglead)
    end, items)
  end

  if sub == nil or sub == "" or sub == arglead then
    return matching(names)
  end
  if sub == "section" and (parts[3] == nil or parts[3] == arglead) then
    local sections = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "n" }
    local configured = config.get().sections
    if type(configured) == "table" and #configured > 0 then
      sections = vim.tbl_map(tostring, configured)
    end
    return matching(sections)
  end
  if (sub == "headings" or sub == "lines") and (parts[3] == nil or parts[3] == arglead) then
    local labels = {}
    local ok, history = pcall(require, "manscope.history")
    if ok then
      for _, page in ipairs(history.list()) do
        labels[#labels + 1] = string.format("%s(%s)", page.name, page.section)
      end
    end
    return matching(labels)
  end
  return {}
end

return M
