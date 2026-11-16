local telescope = require("telescope")

local function call(name)
  return function(opts)
    local manscope = require("manscope")
    if name == "history" then
      manscope.history(opts)
    elseif name == "headings" then
      manscope.headings(opts)
    elseif name == "lines" then
      manscope.lines(opts)
    else
      manscope.search(opts)
    end
  end
end

return telescope.register_extension({
  setup = function(ext_config)
    require("manscope.config").setup(ext_config)
  end,
  exports = {
    manscope = call("search"),
    pages = call("search"),
    history = call("history"),
    headings = call("headings"),
    lines = call("lines"),
  },
})
