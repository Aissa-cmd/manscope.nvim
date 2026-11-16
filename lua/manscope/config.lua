local M = {}

local defaults = {
  -- Sections offered by the section cycle, and the pages included when the
  -- cycle is on "all". nil means every section apropos returns.
  sections = nil,
  -- "prefix": filter "1" also matches "1ssl". "exact" matches the whole token.
  section_match = "prefix",
  -- Override the catalog command, e.g. { "apropos", "." }. nil picks a default.
  man_cmd = nil,
  -- How <CR> opens a page. <C-x>, <C-v>, and <C-t> still split or use a tab.
  open = "current",
  layout = {
    width = 0.92,
    height = 0.88,
    -- Share of the picker width given to the page. The list keeps the rest.
    preview_width = 0.58,
    prompt_position = "top",
    -- false keeps the list on the left and the page on the right.
    mirror = false,
  },
  history = {
    enabled = true,
    limit = 50,
    path = nil,
  },
  mappings = {
    cycle_section = "<M-s>",
    headings = "<M-h>",
    lines = "<M-l>",
  },
  -- Leader keys. `desc` is the label which-key shows. false disables them.
  -- <leader>sM is the "Man Pages" row already in LazyVim's Search menu.
  keys = {
    { "<leader>mm", "search", desc = "Search man pages" },
    { "<leader>mw", "cword", desc = "Word under cursor" },
    { "<leader>mh", "history", desc = "Recent man pages" },
    { "<leader>mH", "headings", desc = "Headings" },
    { "<leader>ml", "lines", desc = "Search in page" },
    { "<leader>sM", "search", desc = "Man Pages" },
  },
  -- Group title in the which-key popup. false skips the which-key call.
  which_key = {
    { "<leader>m", group = "man", icon = { icon = "", color = "cyan" } },
  },
}

local values

local function assign_list(opts, key)
  if opts[key] == nil then
    return
  end
  if opts[key] == false then
    values[key] = false
  else
    values[key] = vim.deepcopy(opts[key])
  end
end

local function assign_lists(opts)
  assign_list(opts, "sections")
  assign_list(opts, "man_cmd")
  assign_list(opts, "keys")
  assign_list(opts, "which_key")
end

function M.setup(opts)
  opts = opts or {}
  if not values then
    values = vim.deepcopy(defaults)
  end
  values = vim.tbl_deep_extend("force", values, opts)
  -- tbl_deep_extend merges arrays by index, so a shorter sections list would
  -- keep leftover entries from the previous config. Replace lists wholesale.
  assign_lists(opts)
end

function M.get()
  if not values then
    values = vim.deepcopy(defaults)
  end
  return values
end

function M.reset()
  values = nil
end

return M
