local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(root)
vim.o.columns = 120
vim.o.lines = 40

local failed = 0
local function check(condition, message)
  if not condition then
    failed = failed + 1
    io.stderr:write("FAIL " .. message .. "\n")
  end
end

local parse_failed = dofile(root .. "/tests/parse_spec.lua")()
check(parse_failed == 0, "parser spec failed (" .. tostring(parse_failed) .. ")")

vim.cmd("runtime plugin/manscope.lua")
check(vim.fn.exists(":Manscope") == 2, ":Manscope was not defined")

local manscope = require("manscope")
local subs = manscope.complete("h", "Manscope h", 10)
check(vim.tbl_contains(subs, "history"), "complete history")
check(vim.tbl_contains(subs, "headings"), "complete headings")
check(not vim.tbl_contains(subs, "cword"), "complete does not offer cword for h")
local sections = manscope.complete("3", "Manscope section 3", 18)
check(vim.tbl_contains(sections, "3"), "complete section 3")

local config = require("manscope.config")
config.setup({ sections = { "1", "2", "3" } })
config.setup({ sections = { "8" } })
check(vim.deep_equal(config.get().sections, { "8" }), "sections list is replaced, not merged by index")
config.setup({
  sections = nil,
  history = { enabled = true, limit = 5, path = vim.fn.tempname() },
})

local history = require("manscope.history")
history.clear()
history.add({ name = "java", section = "1", description = "launch" })
history.add({ name = "javac", section = "1", description = "compile" })
history.add({ name = "java", section = "1", description = "launch again" })
local items = history.list()
check(#items == 2, "history dedupes by name and section, got " .. #items)
check(items[1].name == "java" and items[1].description == "launch again", "latest open is first")
check(items[2].name == "javac", "older page remains")
history.clear()
check(#history.list() == 0, "history clears")

local index = require("manscope.index")
index.clear()
local pages, index_err
local index_done = false
index.pages(function(result, err)
  pages, index_err = result, err
  index_done = true
end)
vim.wait(20000, function()
  return index_done
end, 20)
check(index_done, "apropos index timed out")
check(index_err == nil, "apropos index error: " .. tostring(index_err))
check(type(pages) == "table" and #pages > 0, "apropos index was empty")

local java, long_description
if pages then
  for _, page in ipairs(pages) do
    if page.name == "java" and page.section == "1" then
      java = page
    end
    if #page.description > 80 then
      long_description = page.description
    end
  end
end
check(java ~= nil, "index contains java(1)")
if java then
  check(java.description:lower():find("java", 1, true) ~= nil, "java description mentions java")
  check(not java.description:find("%.%.%.$"), "java description was truncated: " .. java.description)
end
check(long_description ~= nil, "COLUMNS was ignored; every description is short")

local bin = vim.fn.tempname()
vim.fn.mkdir(bin, "p")
local real_man = "/usr/bin/man.REAL"
if vim.fn.executable(real_man) == 1 then
  vim.fn.system({ "ln", "-sf", real_man, bin .. "/man" })
  vim.env.PATH = bin .. ":" .. vim.env.PATH
end

local render = require("manscope.render")
render.clear()
local lines, render_err
local render_done = false
render.page("1", "java", 72, function(result, err)
  lines, render_err = result, err
  render_done = true
end)
vim.wait(20000, function()
  return render_done
end, 20)
check(render_done, "man render timed out")
check(render_err == nil, "man render error: " .. tostring(render_err))
check(type(lines) == "table" and #lines > 10, "man render returned too little text")

local saw_name = false
if lines then
  local headings = require("manscope.parse").headings(lines)
  for _, heading in ipairs(headings) do
    if heading.level == 1 and heading.title == "NAME" then
      saw_name = true
    end
  end
  local text = table.concat(lines, "\n")
  check(not text:find("\8", 1, true), "backspace overstrike survived col -bx")
  check(not text:find("\027", 1, true), "ANSI escapes survived the preview cleaner")
end
check(saw_name, "formatted java(1) has a NAME heading")

local cached_done = false
local cached_lines
render.page("1", "java", 72, function(result)
  cached_lines = result
  cached_done = true
end)
vim.wait(2000, function()
  return cached_done
end, 10)
check(cached_lines == lines, "render cache should return the same line table")

vim.cmd("checkhealth manscope")
local health_text = ""
for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[bufnr].filetype == "checkhealth" then
    health_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  end
end
check(health_text:find("Neovim 0.9 or newer", 1, true) ~= nil, "health check did not report Neovim")
check(health_text:find("apropos is on PATH", 1, true) ~= nil, "health check did not report apropos")
check(health_text:find("search on the left", 1, true) ~= nil, "health check did not report the layout")

if failed > 0 then
  io.stderr:write(failed .. " nvim_spec failure(s)\n")
  vim.cmd("cquit " .. math.min(failed, 99))
else
  print("nvim_spec: ok")
  vim.cmd("qa")
end
