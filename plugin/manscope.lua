if vim.g.loaded_manscope then
  return
end
vim.g.loaded_manscope = true

vim.api.nvim_create_user_command("Manscope", function(opts)
  require("manscope").command(opts)
end, {
  nargs = "*",
  complete = function(arglead, cmdline)
    return require("manscope").complete(arglead, cmdline)
  end,
  desc = "Search man pages",
})
