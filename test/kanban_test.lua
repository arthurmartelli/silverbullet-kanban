-- Tests the board's text logic, loaded from the first space-lua block in
-- Kanban.md, with plain Lua 5.4: lua test/kanban_test.lua
local f = assert(io.open("Kanban.md"))
local page = f:read("a")
f:close()
local logic = assert(page:match("```space%-lua\n(.-)\n```"), "no space-lua block")
assert(load(logic, "Kanban.md"))()

local failures = 0
local function check(name, ok)
  print((ok and "ok   " or "FAIL ") .. name)
  if not ok then failures = failures + 1 end
end

local function sortedLines(text)
  local lines = {}
  for line in text:gmatch("[^\n]+") do table.insert(lines, line) end
  table.sort(lines)
  return table.concat(lines, "\n")
end

local page = table.concat({
  "---",
  "title: Board",
  "## not a column, frontmatter",
  "---",
  "",
  "${kanban.board()}",
  "",
  "## Ideas",
  "",
  "- [ ] First idea",
  "- [ ] Second idea with a [link](https://example.com)",
  "",
  "## Doing",
  "",
  "- [ ] Working on [[Some Page]]",
  "\t- A sub-item",
  "    - Another, indented with spaces",
  "",
  "## Empty",
  "",
  "## Done",
  "",
  "- [x] Finished",
  "Loose text ends a card",
  "\t- not part of any card",
  "",
  "# Notes",
  "",
  "- [ ] Not on the board",
}, "\n")

local board = kanban.parse(page)
check("columns from ## sections only", #board.columns == 4)
check("column titles", board.columns[1].title == "Ideas" and board.columns[4].title == "Done")
check("cards per column", #board.columns[1].cards == 2 and #board.columns[2].cards == 1
  and #board.columns[3].cards == 0 and #board.columns[4].cards == 1)
local doing = board.columns[2].cards[1]
check("card label", doing.label == "Working on [[Some Page]]")
check("indented lines belong to the card, dedented", #doing.body == 2
  and doing.body[1] == "- A sub-item" and doing.body[2] == "- Another, indented with spaces")
check("done state", board.columns[4].cards[1].done and not board.columns[1].cards[1].done)
check("loose text ends a card", #board.columns[4].cards[1].body == 0)

local moved = kanban.moved(page, 2, 1, 3)
local after = kanban.parse(moved)
check("move into an empty column", #after.columns[2].cards == 0 and #after.columns[3].cards == 1
  and #after.columns[3].cards[1].body == 2)
check("blank line kept before the next heading", moved:find("Another, indented with spaces\n\n## Done", 1, true) ~= nil)
check("move keeps every line", sortedLines(moved) == sortedLines(page))

local back = kanban.moved(moved, 3, 1, 2)
check("move back restores the page", back == page)

local appended = kanban.parse(kanban.moved(page, 1, 1, 4))
check("move to the end of a column", #appended.columns[4].cards == 2
  and appended.columns[4].cards[2].label == "First idea")

local toggled = kanban.toggled(page, 1, 2)
check("toggle checks a card", kanban.parse(toggled).columns[1].cards[2].done)
check("toggle twice restores the page", kanban.toggled(toggled, 1, 2) == page)

if failures > 0 then
  print(failures .. " failed")
  os.exit(1)
end
