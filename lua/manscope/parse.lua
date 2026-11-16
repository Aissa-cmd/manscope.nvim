--- Pure parsers for apropos lines and formatted man pages.
--- This module does not touch the Neovim API so it can be tested on its own.

local M = {}

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Split an apropos/whatis line into a page record.
--- Accepts `name (section) - description` and `name(section) - description`,
--- including comma-separated aliases and a `--` separator.
---@param line string
---@return table|nil
function M.apropos_line(line)
  if type(line) ~= "string" then
    return nil
  end
  line = trim(line):gsub("\r$", "")
  if line == "" then
    return nil
  end

  -- ASCII hyphen first. `%-+` also covers the `--` variant some databases emit.
  local name_part, section, description = line:match("^(.-)%s*%(([^)]+)%)%s+%-+%s*(.*)$")
  if not name_part then
    -- en dash U+2013, then em dash U+2014. Lua patterns are byte based, so
    -- these cannot live in a character class next to an ASCII hyphen.
    name_part, section, description = line:match("^(.-)%s*%(([^)]+)%)%s+\226\128\147%s*(.*)$")
  end
  if not name_part then
    name_part, section, description = line:match("^(.-)%s*%(([^)]+)%)%s+\226\128\148%s*(.*)$")
  end
  if not name_part or name_part == "" or not section or section == "" then
    return nil
  end

  local names = {}
  for piece in name_part:gmatch("[^,]+") do
    local name = trim(piece)
    if name ~= "" then
      names[#names + 1] = name
    end
  end
  if #names == 0 then
    return nil
  end

  description = trim(description or "")
  return {
    name = names[1],
    names = names,
    section = section,
    description = description,
    ordinal = table.concat(names, " ") .. " " .. section .. " " .. description,
  }
end

--- Parse `name(section)` as stored on `man://` buffer names.
---@param text string
---@return table|nil
function M.ref(text)
  if type(text) ~= "string" then
    return nil
  end
  text = trim(text):gsub("^man://", ""):gsub("%?.*$", "")
  local name, section = text:match("^(.-)%(([^)]+)%)/?$")
  if not name or not section then
    return nil
  end
  name = trim(name)
  section = trim(section)
  if name == "" or section == "" then
    return nil
  end
  return M.apropos_line(string.format("%s (%s) - ", name, section))
end

--- Whether `section` belongs to the filter list.
--- In prefix mode, "1" matches "1" and "1ssl" but not "10": the character
--- after the filter must not be another digit.
---@param section string
---@param filters string[]|nil
---@param mode? "prefix"|"exact"
---@return boolean
function M.section_matches(section, filters, mode)
  if not filters or #filters == 0 then
    return true
  end
  mode = mode or "prefix"
  for _, filter in ipairs(filters) do
    if filter == "all" or filter == "ALL" or filter == "*" then
      return true
    end
    if section == filter then
      return true
    end
    if mode == "prefix" and section:sub(1, #filter) == filter then
      local next_char = section:sub(#filter + 1, #filter + 1)
      if next_char == "" or not next_char:match("%d") then
        return true
      end
    end
  end
  return false
end

local function is_section_heading(line)
  if line == "" or line:find("^%s") then
    return false
  end
  if #line < 2 or #line > 80 then
    return false
  end
  -- Centered running headers ("NAME(1)    User Commands    NAME(1)") use
  -- wide gaps and parentheses. Real section titles do not.
  if line:find("%s%s") or line:find("[()]") then
    return false
  end
  if line:find("[a-z]") then
    return false
  end
  if not line:find("%u%u") then
    return false
  end
  -- Literal ranges only. Lua character classes do not nest (%u inside []).
  if line:find("[^A-Z0-9 %-+/&,:.']") then
    return false
  end
  return true
end

local function is_subheading(line)
  local text = line:match("^   (%S.*)$")
  if not text or #text > 80 or text:find("%s%s") then
    return false
  end
  -- A lone flag ("-h") is an option, not a subsection title.
  if text:find("^[-+]") and not text:find("%s") then
    return false
  end
  if not text:find("^[A-Za-z0-9%-+=]") then
    return false
  end
  return true
end

--- Section and subsection titles from a formatted (`col -bx`) man page.
--- Line numbers are 1-based and refer to `lines` as given.
---@param lines string[]
---@return {lnum:integer,level:integer,title:string,text:string}[]
function M.headings(lines)
  local found = {}
  for lnum, line in ipairs(lines) do
    local text = line:gsub("%s+$", "")
    if is_section_heading(text) then
      found[#found + 1] = {
        lnum = lnum,
        level = 1,
        title = text,
        text = text,
      }
    elseif is_subheading(text) then
      local title = text:match("^   (%S.*)$")
      found[#found + 1] = {
        lnum = lnum,
        level = 2,
        title = title,
        text = text,
      }
    end
  end
  return found
end

return M
