local config = require("manscope.config")
local history = require("manscope.history")
local index = require("manscope.index")
local parse = require("manscope.parse")
local render = require("manscope.render")

local M = {}

local preview_ns = vim.api.nvim_create_namespace("manscope_preview")

local ours_keys = {
  query = true,
  sections = true,
  section = true,
  name = true,
  ref = true,
  telescope = true,
  open = true,
  page = true,
  description = true,
  jump = true,
}

local function telescope()
  local ok, loaded = pcall(function()
    return {
      actions = require("telescope.actions"),
      action_state = require("telescope.actions.state"),
      action_set = require("telescope.actions.set"),
      finders = require("telescope.finders"),
      pickers = require("telescope.pickers"),
      previewers = require("telescope.previewers"),
      conf = require("telescope.config").values,
      entry_display = require("telescope.pickers.entry_display"),
    }
  end)
  if not ok then
    vim.notify(
      "manscope.nvim requires telescope.nvim (nvim-telescope/telescope.nvim) and plenary.nvim.",
      vim.log.levels.ERROR
    )
    return nil
  end
  return loaded
end

local function split_opts(opts)
  opts = opts or {}
  local ours = {}
  local foreign = {}
  if type(opts.telescope) == "table" then
    foreign = vim.tbl_deep_extend("force", foreign, opts.telescope)
  end
  for key, value in pairs(opts) do
    if ours_keys[key] then
      ours[key] = value
    elseif key ~= "telescope" then
      foreign[key] = value
    end
  end
  if ours.section and not ours.sections then
    ours.sections = { ours.section }
  end
  if type(ours.query) ~= "string" or ours.query == "" then
    ours.query = foreign.default_text
  end
  return ours, foreign
end

local function picker_options(foreign, titles, query)
  local layout = config.get().layout
  local prompt_position = layout.prompt_position or "top"
  local base = {
    prompt_title = titles.prompt,
    results_title = titles.results,
    -- Horizontal is the Telescope layout with the prompt and results on the
    -- left and the preview on the right. mirror would swap those sides.
    layout_strategy = "horizontal",
    sorting_strategy = prompt_position == "bottom" and "descending" or "ascending",
    layout_config = {
      width = layout.width,
      height = layout.height,
      prompt_position = prompt_position,
      preview_cutoff = 40,
      horizontal = {
        width = layout.width,
        height = layout.height,
        prompt_position = prompt_position,
        preview_width = layout.preview_width,
        mirror = layout.mirror == true,
        preview_cutoff = 40,
      },
    },
  }
  local merged = vim.tbl_deep_extend("force", base, foreign or {})
  if query and query ~= "" then
    merged.default_text = query
  end
  merged.prompt_title = titles.prompt
  merged.results_title = titles.results
  if not (foreign and foreign.layout_strategy) then
    merged.layout_strategy = "horizontal"
  end
  return merged
end

local function how_for(cmd)
  if cmd == "horizontal" or cmd == "vertical" or cmd == "tab" then
    return cmd
  end
  local open = config.get().open
  if open == "horizontal" or open == "vertical" or open == "tab" then
    return open
  end
  return "current"
end

local function ensure_man()
  if vim.fn.exists(":Man") ~= 2 then
    pcall(vim.cmd, "runtime plugin/man.lua")
    pcall(vim.cmd, "runtime plugin/man.vim")
  end
end

local function open_man(entry, how)
  history.add({
    name = entry.name,
    section = entry.section,
    description = entry.description,
  })
  ensure_man()
  local mods = {}
  if how == "vertical" then
    mods.vertical = true
  elseif how == "horizontal" then
    mods.horizontal = true
  elseif how == "tab" then
    mods.tab = 1
  end
  local ok, err = pcall(vim.api.nvim_cmd, {
    cmd = "Man",
    args = { entry.section, entry.name },
    mods = mods,
  }, {})
  if not ok then
    vim.notify("manscope: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  local jump = entry.jump
  if type(jump) ~= "string" or jump == "" then
    return
  end
  vim.schedule(function()
    if vim.bo.filetype ~= "man" then
      return
    end
    local pattern = "\\V" .. vim.fn.escape(jump, "\\")
    vim.cmd("keepjumps normal! gg")
    if vim.fn.search(pattern, "W") > 0 then
      vim.cmd("normal! zz")
    end
  end)
end

local function show_text(bufnr, lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines and #lines > 0 and lines or { "" })
  vim.bo[bufnr].filetype = "man"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
end

local function reveal(winid, bufnr, lnum)
  if not winid or not vim.api.nvim_win_is_valid(winid) or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  pcall(vim.api.nvim_buf_clear_namespace, bufnr, preview_ns, 0, -1)
  if not lnum or lnum < 1 then
    return
  end
  local last = vim.api.nvim_buf_line_count(bufnr)
  if last < 1 then
    return
  end
  if lnum > last then
    lnum = last
  end
  pcall(vim.api.nvim_buf_set_extmark, bufnr, preview_ns, lnum - 1, 0, {
    line_hl_group = "TelescopePreviewLine",
  })
  pcall(vim.api.nvim_win_set_cursor, winid, { lnum, 0 })
  pcall(vim.api.nvim_win_call, winid, function()
    vim.cmd("normal! zz")
  end)
end

local function prepare_window(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
  vim.wo[winid].breakindent = true
  vim.wo[winid].conceallevel = 2
end

local function man_previewer(ts, preview_opts)
  preview_opts = preview_opts or {}
  local fixed_lines = preview_opts.lines
  return ts.previewers.new_buffer_previewer({
    title = "Man page",
    dyn_title = function(_, entry)
      if entry and entry.name and entry.section then
        return string.format("%s(%s)", entry.name, entry.section)
      end
      return "Man page"
    end,
    get_buffer_by_name = function(_, entry)
      return string.format("%s(%s)", entry.name or "", entry.section or "")
    end,
    define_preview = function(self, entry)
      local winid = self.state.winid
      local bufnr = self.state.bufnr
      prepare_window(winid)
      self.state.filled = self.state.filled or {}

      local function paint(lines)
        if not vim.api.nvim_buf_is_valid(bufnr) or self.state.bufnr ~= bufnr then
          return
        end
        if not self.state.filled[bufnr] then
          show_text(bufnr, lines)
          self.state.filled[bufnr] = true
        end
        vim.schedule(function()
          if self.state.bufnr ~= bufnr then
            return
          end
          prepare_window(winid)
          reveal(winid, bufnr, entry.lnum)
        end)
      end

      if fixed_lines then
        paint(fixed_lines)
        return
      end
      if self.state.filled[bufnr] then
        vim.schedule(function()
          if self.state.bufnr == bufnr then
            reveal(winid, bufnr, entry.lnum)
          end
        end)
        return
      end

      self.state.token = (self.state.token or 0) + 1
      local token = self.state.token
      render.page(entry.section, entry.name, render.document_width(), function(lines, err)
        if self.state.token ~= token or self.state.bufnr ~= bufnr then
          return
        end
        if err then
          paint(vim.split(err, "\n", { plain = true }))
          return
        end
        paint(lines)
      end)
    end,
  })
end

local function column_width(text, cap, floor)
  local width = vim.fn.strdisplaywidth(text)
  if width < floor then
    width = floor
  end
  if width > cap then
    width = cap
  end
  return width
end

local function page_entry_maker(ts, pages)
  local name_w, section_w = 8, 5
  for _, page in ipairs(pages) do
    name_w = math.max(name_w, column_width(page.name, 32, 0))
    section_w = math.max(section_w, column_width("(" .. page.section .. ")", 12, 0))
  end
  local displayer = ts.entry_display.create({
    separator = " ",
    items = {
      { width = name_w },
      { width = section_w },
      { remaining = true },
    },
  })
  return function(page)
    return {
      value = page.name,
      ordinal = page.ordinal,
      name = page.name,
      section = page.section,
      description = page.description or "",
      display = function(entry)
        return displayer({
          { entry.name, "TelescopeResultsFunction" },
          { "(" .. entry.section .. ")", "TelescopeResultsNumber" },
          { entry.description, "TelescopeResultsComment" },
        })
      end,
    }
  end
end

local function normalize(page)
  page.description = page.description or ""
  page.names = page.names or { page.name }
  if not page.ordinal or page.ordinal == "" then
    page.ordinal = table.concat(page.names, " ") .. " " .. page.section .. " " .. page.description
  end
  return page
end

local function filter_pages(pages, sections)
  local mode = config.get().section_match
  local shown = {}
  for _, page in ipairs(pages) do
    if parse.section_matches(page.section, sections, mode) then
      shown[#shown + 1] = page
    end
  end
  return shown
end

local function cycle_list()
  local configured = config.get().sections
  local presets = configured or { "1", "2", "3", "4", "5", "6", "7", "8", "9" }
  local cycle = {
    {
      id = "all",
      label = configured and "Configured sections" or "All sections",
      sections = configured,
    },
  }
  for _, section in ipairs(presets) do
    cycle[#cycle + 1] = {
      id = tostring(section),
      label = "Section " .. tostring(section),
      sections = { tostring(section) },
    }
  end
  return cycle
end

local function initial_cycle(sections)
  local cycle = cycle_list()
  if not sections or #sections == 0 then
    return cycle, 1
  end
  if #sections == 1 then
    for index, item in ipairs(cycle) do
      if item.id == tostring(sections[1]) then
        return cycle, index
      end
    end
  end
  local label = "Section " .. table.concat(sections, ",")
  table.insert(cycle, 1, {
    id = "custom",
    label = label,
    sections = sections,
  })
  return cycle, 1
end

local function retitle(picker, prompt, results)
  picker.prompt_title = prompt
  picker.results_title = results
  local function apply(part, title)
    if not title then
      return
    end
    local win = picker.layout and picker.layout[part]
    local winid = win and win.winid
    if winid and vim.api.nvim_win_is_valid(winid) then
      pcall(vim.api.nvim_win_set_config, winid, { title = " " .. title .. " " })
    end
  end
  apply("prompt", prompt)
  apply("results", results)
end

local function map_key(map, key, fn, desc)
  if type(key) ~= "string" or key == "" then
    return
  end
  map({ "i", "n" }, key, fn, { desc = desc })
end

local function bind_select(ts, prompt_bufnr, on_select)
  ts.action_set.select:replace(function(_, cmd)
    local entry = ts.action_state.get_selected_entry()
    if not entry then
      vim.notify("manscope: nothing selected", vim.log.levels.WARN)
      return
    end
    ts.actions.close(prompt_bufnr)
    vim.schedule(function()
      on_select(entry, cmd)
    end)
  end)
end

local function selected_page(ts)
  local entry = ts.action_state.get_selected_entry()
  if not entry or not entry.name or not entry.section then
    return nil
  end
  return {
    name = entry.name,
    section = entry.section,
    description = entry.description,
  }
end

local function open_catalog(ts, pages, opts, catalog_opts)
  catalog_opts = catalog_opts or {}
  local ours, foreign = split_opts(opts)
  for _, page in ipairs(pages) do
    normalize(page)
  end

  local cycle, cycle_index
  if catalog_opts.cycle == false then
    cycle, cycle_index = { { id = "all", label = catalog_opts.results or "Pages", sections = nil } }, 1
  else
    cycle, cycle_index = initial_cycle(ours.sections)
  end
  local state = { index = cycle_index }

  local function current_filter()
    return cycle[state.index]
  end

  local function make_finder()
    local shown = filter_pages(pages, current_filter().sections)
    return ts.finders.new_table({
      results = shown,
      entry_maker = page_entry_maker(ts, shown),
    })
  end

  local prompt = catalog_opts.prompt or "Man pages"
  local function results_title()
    return current_filter().label
  end

  local popts = picker_options(foreign, { prompt = prompt, results = results_title() }, ours.query)
  popts.finder = make_finder()
  popts.sorter = ts.conf.generic_sorter({})
  popts.previewer = man_previewer(ts)
  popts.attach_mappings = function(prompt_bufnr, map)
    bind_select(ts, prompt_bufnr, function(entry, cmd)
      open_man(entry, how_for(cmd))
    end)

    local mappings = config.get().mappings or {}
    if catalog_opts.cycle ~= false then
      map_key(map, mappings.cycle_section, function()
        local picker = ts.action_state.get_current_picker(prompt_bufnr)
        state.index = state.index % #cycle + 1
        picker:refresh(make_finder(), { reset_prompt = false })
        retitle(picker, prompt, results_title())
      end, "Cycle man section")
    end

    map_key(map, mappings.headings, function()
      local page = selected_page(ts)
      if not page then
        return
      end
      ts.actions.close(prompt_bufnr)
      vim.schedule(function()
        M.headings(page)
      end)
    end, "Headings in this man page")

    map_key(map, mappings.lines, function()
      local page = selected_page(ts)
      if not page then
        return
      end
      ts.actions.close(prompt_bufnr)
      vim.schedule(function()
        M.lines(page)
      end)
    end, "Search inside this man page")

    if type(foreign.attach_mappings) == "function" then
      local result = foreign.attach_mappings(prompt_bufnr, map)
      if result == nil then
        return true
      end
      return result
    end
    return true
  end

  ts.pickers.new(popts):find()
end

local function outline_entry_maker(ts, kind)
  local displayer = ts.entry_display.create({
    separator = " ",
    items = {
      { width = 6 },
      { remaining = true },
    },
  })
  return function(item)
    local title = item.title
    local highlight
    if kind == "headings" then
      highlight = item.level == 2 and "TelescopeResultsComment" or "TelescopeResultsFunction"
      if item.level == 2 then
        title = "  " .. title
      end
    end
    return {
      value = item.title,
      ordinal = item.title,
      name = item.name,
      section = item.section,
      description = item.description or "",
      lnum = item.lnum,
      jump = item.jump,
      display = function(entry)
        local text = title
        if highlight then
          text = { title, highlight }
        end
        return displayer({
          { tostring(entry.lnum), "TelescopeResultsNumber" },
          text,
        })
      end,
    }
  end
end

local function open_outline(kind, page, lines, opts)
  local ts = telescope()
  if not ts then
    return
  end
  local ours, foreign = split_opts(opts)
  local items = {}
  if kind == "headings" then
    for _, heading in ipairs(parse.headings(lines)) do
      items[#items + 1] = {
        lnum = heading.lnum,
        level = heading.level,
        title = heading.title,
        jump = heading.text,
        name = page.name,
        section = page.section,
        description = page.description,
      }
    end
    if #items == 0 then
      vim.notify(
        string.format("manscope: no headings in %s(%s)", page.name, page.section),
        vim.log.levels.WARN
      )
      return
    end
  else
    for lnum, line in ipairs(lines) do
      if line:find("%S") then
        local title = vim.trim(line)
        items[#items + 1] = {
          lnum = lnum,
          title = title,
          jump = line,
          name = page.name,
          section = page.section,
          description = page.description,
        }
      end
    end
  end

  local prompt = kind == "headings" and "Headings" or "Search in page"
  local results = string.format("%s(%s)", page.name, page.section)
  local popts = picker_options(foreign, { prompt = prompt, results = results }, ours.query)
  popts.finder = ts.finders.new_table({
    results = items,
    entry_maker = outline_entry_maker(ts, kind),
  })
  popts.sorter = ts.conf.generic_sorter({})
  popts.previewer = man_previewer(ts, { lines = lines })
  popts.attach_mappings = function(prompt_bufnr, map)
    bind_select(ts, prompt_bufnr, function(entry, cmd)
      open_man(entry, how_for(cmd))
    end)
    if type(foreign.attach_mappings) == "function" then
      local result = foreign.attach_mappings(prompt_bufnr, map)
      if result == nil then
        return true
      end
      return result
    end
    return true
  end
  ts.pickers.new(popts):find()
end

local function current_man_page()
  if vim.bo.filetype ~= "man" then
    return nil
  end
  local bufname = vim.api.nvim_buf_get_name(0)
  local ref = bufname:match("^man://(.*)$")
  if not ref then
    return nil
  end
  local page = parse.ref(vim.fn.fnameunescape(ref))
  if page then
    page.description = ""
  end
  return page
end

local function lines_for(page, callback)
  local current = current_man_page()
  if current and current.name == page.name and current.section == page.section then
    callback(vim.api.nvim_buf_get_lines(0, 0, -1, false), nil)
    return
  end
  render.page(page.section, page.name, render.document_width(), callback)
end

local function resolve_page(opts, callback)
  opts = opts or {}
  if opts.ref then
    local page = parse.ref(opts.ref)
    if page then
      callback(page)
      return
    end
  end
  if opts.name and opts.section then
    callback(normalize({
      name = opts.name,
      section = opts.section,
      description = opts.description or "",
    }))
    return
  end
  if not opts.name then
    local current = current_man_page()
    if current then
      callback(current)
      return
    end
    vim.notify("manscope: open a man page, or pass name(section)", vim.log.levels.WARN)
    return
  end

  index.pages(function(pages, err)
    if not pages then
      vim.notify("manscope: " .. (err or "man page index failed"), vim.log.levels.ERROR)
      return
    end
    local matches = {}
    local wanted = opts.name:lower()
    for _, page in ipairs(pages) do
      if page.name == opts.name or page.name:lower() == wanted then
        matches[#matches + 1] = page
      end
    end
    if #matches == 1 then
      callback(matches[1])
    elseif #matches == 0 then
      vim.notify("manscope: no man page named " .. opts.name, vim.log.levels.WARN)
    else
      M.pages({ query = opts.name })
    end
  end)
end

local function open_resolved(kind, opts)
  resolve_page(opts, function(page)
    lines_for(page, function(lines, err)
      if not lines then
        vim.notify("manscope: " .. (err or "could not format the man page"), vim.log.levels.ERROR)
        return
      end
      open_outline(kind, page, lines, opts)
    end)
  end)
end

function M.pages(opts)
  local ts = telescope()
  if not ts then
    return
  end
  index.pages(function(pages, err)
    if not pages or #pages == 0 then
      vim.notify("manscope: " .. (err or "no man pages found"), vim.log.levels.ERROR)
      return
    end
    open_catalog(ts, pages, opts, { cycle = true, prompt = "Man pages" })
  end)
end

function M.history(opts)
  local ts = telescope()
  if not ts then
    return
  end
  local pages = history.list()
  if #pages == 0 then
    vim.notify("manscope: no man page history yet", vim.log.levels.INFO)
    return
  end
  open_catalog(ts, pages, opts, {
    cycle = false,
    prompt = "Recent man pages",
    results = "History",
  })
end

function M.headings(opts)
  open_resolved("headings", opts or {})
end

function M.lines(opts)
  open_resolved("lines", opts or {})
end

return M
