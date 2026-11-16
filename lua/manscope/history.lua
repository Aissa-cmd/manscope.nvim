local config = require("manscope.config")

local M = {}

local items

local function path()
  local configured = config.get().history.path
  if type(configured) == "string" and configured ~= "" then
    return configured
  end
  local dir = vim.fn.stdpath("data") .. "/manscope"
  vim.fn.mkdir(dir, "p")
  return dir .. "/history.json"
end

local function read()
  if items then
    return items
  end
  items = {}
  local file = path()
  if vim.fn.filereadable(file) ~= 1 then
    return items
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(file), "\n"))
  if ok and type(decoded) == "table" then
    items = decoded
  end
  return items
end

local function write(next_items)
  items = next_items
  local encoded = vim.json.encode(next_items)
  local ok, err = pcall(vim.fn.writefile, { encoded }, path())
  if not ok then
    vim.notify("manscope: could not write history (" .. tostring(err) .. ")", vim.log.levels.WARN)
  end
end

function M.list()
  if not config.get().history.enabled then
    return {}
  end
  return vim.deepcopy(read())
end

---@param page {name:string,section:string,description?:string}
function M.add(page)
  local history = config.get().history
  if not history.enabled or not page or not page.name or not page.section then
    return
  end
  local next_items = {}
  local id = page.name .. "\0" .. page.section
  for _, item in ipairs(read()) do
    if item.name and item.section and (item.name .. "\0" .. item.section) ~= id then
      next_items[#next_items + 1] = item
    end
  end
  table.insert(next_items, 1, {
    name = page.name,
    section = page.section,
    description = page.description or "",
    at = os.time(),
  })
  local limit = history.limit or 50
  while #next_items > limit do
    table.remove(next_items)
  end
  write(next_items)
end

function M.clear()
  items = {}
  local file = path()
  if vim.fn.filereadable(file) == 1 then
    vim.fn.delete(file)
  end
end

return M
