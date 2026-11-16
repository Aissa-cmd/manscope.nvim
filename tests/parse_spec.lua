local source = arg and arg[0] or ""
local root = source:match("^(.*)/tests/parse_spec%.lua$")
if not root or root == "" then
  root = "."
end
package.path = root .. "/lua/?.lua;" .. package.path

local parse = require("manscope.parse")

local failures = 0

local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL " .. message .. "\n")
end

local function eq(actual, expected, message)
  if actual ~= expected then
    fail(message .. "\n  expected: " .. tostring(expected) .. "\n  actual:   " .. tostring(actual))
  end
end

local function page(line)
  local parsed = parse.apropos_line(line)
  if not parsed then
    fail("did not parse: " .. line)
    return {}
  end
  return parsed
end

local printf = page("printf (1)            - format and print data")
eq(printf.name, "printf", "name with spaced section")
eq(printf.section, "1", "section with spaced parens")
eq(printf.description, "format and print data", "description")

local libc = page("printf(3) - formatted output conversion")
eq(libc.name, "printf", "name without space before paren")
eq(libc.section, "3", "section without space")

local git = page("git-commit (1) - Record changes to the repository")
eq(git.name, "git-commit", "hyphenated name")

local alias = page("alacritty, Alacritty (1) - A fast terminal emulator")
eq(alias.name, "alacritty", "first alias is the page name")
eq(alias.names[2], "Alacritty", "second alias kept")
eq(alias.ordinal:find("Alacritty", 1, true) ~= nil, true, "ordinal includes aliases")
eq(alias.ordinal:find("fast terminal", 1, true) ~= nil, true, "ordinal includes the description")

local perl = page("App::CLI (3perl) - Dispatcher for command line programs")
eq(perl.name, "App::CLI", "perl module name")
eq(perl.section, "3perl", "extended section")

local dashed = page("widget (1) -- draw a widget")
eq(dashed.description, "draw a widget", "double hyphen separator")

local empty_desc = page("widget (1) -")
eq(empty_desc.name, "widget", "empty description still parses")
eq(empty_desc.description, "", "description may be empty")

local en_dash = page("widget (1) \226\128\147 draw a widget")
eq(en_dash.description, "draw a widget", "en dash separator")

if parse.apropos_line("") ~= nil then
  fail("blank line should not parse")
end
if parse.apropos_line("apropos: nothing appropriate") ~= nil then
  fail("prose should not parse")
end
if parse.apropos_line(nil) ~= nil then
  fail("nil should not parse")
end

local ref = parse.ref("man://printf(1)?new=2")
if not ref then
  fail("man:// ref should parse")
else
  eq(ref.name, "printf", "ref name")
  eq(ref.section, "1", "ref section")
end

eq(parse.section_matches("1", nil), true, "nil filter matches everything")
eq(parse.section_matches("3perl", {}), true, "empty filter matches everything")
eq(parse.section_matches("3perl", { "3" }), true, "prefix 3 matches 3perl")
eq(parse.section_matches("1p", { "1" }), true, "prefix 1 matches 1p")
eq(parse.section_matches("1", { "1" }), true, "exact digit section")
eq(parse.section_matches("10", { "1" }), false, "prefix 1 does not match 10")
eq(parse.section_matches("21", { "1" }), false, "21 is not section 1")
eq(parse.section_matches("3perl", { "3" }, "exact"), false, "exact mode keeps 3perl out of 3")
eq(parse.section_matches("n", { "n" }), true, "letter section")
eq(parse.section_matches("8", { "ALL" }), true, "ALL matches")

local lines = {
  "JAVA(1)                      JDK Commands                      JAVA(1)",
  "",
  "NAME",
  "       java - launch a Java application",
  "",
  "DESCRIPTION",
  "       The java command starts a Java application.",
  "   Overview",
  "       more text",
  "   -h",
  "   -Xlog Tags and Levels",
  "SEE ALSO",
  "GNU coreutils                   2024                       JAVA(1)",
}
local headings = parse.headings(lines)
local titles = {}
for _, heading in ipairs(headings) do
  titles[#titles + 1] = heading.level .. ":" .. heading.title .. "@" .. heading.lnum
end
eq(table.concat(titles, ","), "1:NAME@3,1:DESCRIPTION@6,2:Overview@8,2:-Xlog Tags and Levels@11,1:SEE ALSO@12", "headings")

local function run()
  return failures
end

if arg and arg[0] and arg[0]:match("parse_spec%.lua$") then
  if failures > 0 then
    os.exit(1)
  end
  print("parse_spec: ok")
end

return run
