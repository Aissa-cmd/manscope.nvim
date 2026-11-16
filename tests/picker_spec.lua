-- Open the catalog in a headless Neovim and check that the list is left of the page.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local telescope_root = vim.env.MANSCOPE_TELESCOPE or "/tmp/telescope.nvim"
local plenary_root = vim.env.MANSCOPE_PLENARY or "/tmp/plenary.nvim"

if vim.fn.isdirectory(telescope_root .. "/lua") ~= 1 or vim.fn.isdirectory(plenary_root .. "/lua") ~= 1 then
  print("picker_spec: skipped (set MANSCOPE_TELESCOPE and MANSCOPE_PLENARY)")
  vim.cmd("qa!")
  return
end

if not vim.uv then
  vim.uv = vim.loop
end

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(plenary_root)
vim.opt.runtimepath:prepend(telescope_root)
vim.o.columns = 140
vim.o.lines = 40

local failed = 0
local function check(condition, message)
  if not condition then
    failed = failed + 1
    io.stderr:write("FAIL " .. message .. "\n")
  end
end

local bin = vim.fn.tempname()
vim.fn.mkdir(bin, "p")
if vim.fn.executable("/usr/bin/man.REAL") == 1 then
  vim.fn.system({ "ln", "-sf", "/usr/bin/man.REAL", bin .. "/man" })
  vim.env.PATH = bin .. ":" .. vim.env.PATH
end

require("telescope").setup({})
vim.cmd("runtime plugin/manscope.lua")

local opened = false
local ok, err = pcall(function()
  require("manscope").search({ query = "java" })
end)
check(ok, "search() raised before the picker opened: " .. tostring(err))

vim.wait(8000, function()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "TelescopePrompt" then
      opened = true
      return true
    end
  end
  return false
end, 30)
check(opened, "Telescope prompt did not open")

local prompt, results, preview
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local config = vim.api.nvim_win_get_config(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  local info = {
    win = win,
    buf = buf,
    ft = ft,
    col = config.col,
    row = config.row,
    width = config.width,
  }
  if type(info.col) == "table" then
    info.col = info.col[vim.val_idx or false] or info.col[false] or info.col[1]
  end
  if ft == "TelescopePrompt" then
    prompt = info
  elseif ft == "TelescopeResults" then
    results = info
  end
  -- The preview buffer starts empty and is not a telescope filetype.
  if config.relative ~= "" and ft ~= "TelescopePrompt" and ft ~= "TelescopeResults" and (info.width or 0) > 20 then
    if not preview or info.col > preview.col then
      preview = info
    end
  end
end

check(prompt ~= nil, "missing prompt window")
check(results ~= nil, "missing results window")
check(preview ~= nil, "missing preview window")

if prompt and results and preview then
  check(prompt.col < preview.col, string.format(
    "prompt should be left of the preview (prompt col %s, preview col %s)",
    tostring(prompt.col),
    tostring(preview.col)
  ))
  check(results.col < preview.col, string.format(
    "results should be left of the preview (results col %s, preview col %s)",
    tostring(results.col),
    tostring(preview.col)
  ))
  check(math.abs(prompt.col - results.col) <= 2, "prompt and results should share the left column")
end

local saw_java = false
if results then
  vim.wait(3000, function()
    local lines = vim.api.nvim_buf_get_lines(results.buf, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:lower():find("java", 1, true) then
        saw_java = true
        return true
      end
    end
    return false
  end, 30)
end
check(saw_java, "results did not list java")

local preview_text = ""
if preview then
  vim.wait(8000, function()
    preview_text = table.concat(vim.api.nvim_buf_get_lines(preview.buf, 0, 40, false), "\n")
    return preview_text:find("NAME") ~= nil or preview_text:find("java") ~= nil
  end, 40)
  check(
    preview_text:find("NAME") ~= nil or preview_text:lower():find("java", 1, true) ~= nil,
    "preview did not show the man page:\n" .. preview_text
  )
end

if failed > 0 then
  io.stderr:write(failed .. " picker_spec failure(s)\n")
  vim.cmd("cquit " .. math.min(failed, 99))
else
  print("picker_spec: ok")
  print(string.format(
    "layout cols prompt=%s results=%s preview=%s",
    prompt and prompt.col or "?",
    results and results.col or "?",
    preview and preview.col or "?"
  ))
  vim.cmd("qa!")
end
