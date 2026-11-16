local M = {}

local function report()
  local health = vim.health
  if health.start then
    return health
  end
  return {
    start = health.report_start,
    ok = health.report_ok,
    warn = health.report_warn,
    error = health.report_error,
    info = health.report_info,
  }
end

function M.check()
  local health = report()
  health.start("manscope.nvim")

  if vim.fn.has("nvim-0.9") == 1 then
    health.ok("Neovim 0.9 or newer")
  else
    health.error("Neovim 0.9 or newer is required")
  end

  for _, bin in ipairs({ "man", "apropos" }) do
    if vim.fn.executable(bin) == 1 then
      health.ok(bin .. " is on PATH")
    else
      health.error(bin .. " was not found on PATH")
    end
  end

  if vim.fn.executable("col") == 1 then
    health.ok("col is on PATH (overstrike is stripped in the preview)")
  else
    health.warn("col was not found; previews may contain raw backspace characters")
  end

  local telescope_ok = pcall(require, "telescope")
  if telescope_ok then
    health.ok("telescope.nvim is installed")
  else
    health.error("telescope.nvim is required (nvim-telescope/telescope.nvim)")
  end

  local config = require("manscope.config").get()
  local mirror = config.layout.mirror == true and "preview on the left" or "search on the left, preview on the right"
  health.info("layout: " .. mirror)
end

return M
