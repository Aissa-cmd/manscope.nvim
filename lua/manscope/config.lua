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
}

local values

local function assign_lists(opts)
  if opts.sections ~= nil then
    values.sections = vim.deepcopy(opts.sections)
  end
  if opts.man_cmd ~= nil then
    values.man_cmd = vim.deepcopy(opts.man_cmd)
  end
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
