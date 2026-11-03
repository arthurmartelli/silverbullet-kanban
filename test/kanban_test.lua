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

check("named columns start folded", kanban.startsFolded({ "Ideas", "Done" }, "Done"))
check("other columns start unfolded", not kanban.startsFolded({ "Ideas" }, "Doing"))
check("no folded list folds nothing", not kanban.startsFolded(nil, "Doing"))
check("a single title folds", kanban.startsFolded("Doing", "Doing") and not kanban.startsFolded("Doing", "Ideas"))
check("anything else folds nothing", not kanban.startsFolded(true, "Doing"))

local top = kanban.moved(page, 1, 2, 1, 1)
check("move to the top of a column", kanban.parse(top).columns[1].cards[1].label:find("Second idea", 1, true) ~= nil)
check("move to the top keeps every line", sortedLines(top) == sortedLines(page))
check("move to a column's end by default", kanban.parse(kanban.moved(top, 1, 1, 1)) .columns[1].cards[2].label:find("Second idea", 1, true) ~= nil)
local between = kanban.parse(kanban.moved(page, 2, 1, 1, 2)).columns[1].cards
check("move between cards, with its sub-items", #between == 3 and between[2].label == "Working on [[Some Page]]"
  and #between[2].body == 2 and between[3].label:find("Second idea", 1, true) ~= nil)

local added = kanban.parse(kanban.added(page, 1, "New")).columns[1].cards
check("add at a column's end", #added == 3 and added[3].label == "New" and not added[3].done)
local inserted = kanban.parse(kanban.added(page, 1, "New", 1)).columns[1].cards
check("add at a position", inserted[1].label == "New" and inserted[2].label == "First idea")
local into = kanban.added(page, 3, "New")
check("add to an empty column", kanban.parse(into).columns[3].cards[1].label == "New"
  and into:find("## Empty\n\n- [ ] New\n\n## Done", 1, true) ~= nil)

local edited = kanban.parse(kanban.edited(page, 4, 1, "Renamed")).columns[4].cards[1]
check("edit keeps the mark", edited.label == "Renamed" and edited.done)
local editedBody = kanban.parse(kanban.edited(page, 2, 1, "Renamed")).columns[2].cards[1]
check("edit keeps the sub-items", #editedBody.body == 2)
check("edit keeps odd characters", kanban.parse(kanban.edited(page, 1, 1, "100% %1 [x]")).columns[1].cards[1].label == "100% %1 [x]")

local copies = kanban.parse(kanban.duplicated(page, 2, 1)).columns[2].cards
check("duplicate comes right after, with its sub-items", #copies == 2 and copies[2].label == copies[1].label and #copies[2].body == 2)
local removed = kanban.removed(page, 2, 1)
check("delete a card and its sub-items", #kanban.parse(removed).columns[2].cards == 0
  and not removed:find("A sub-item", 1, true))

local reordered = kanban.columnMoved(page, 1, 3)
local titles = kanban.parse(reordered).columns
check("move a column", titles[1].title == "Doing" and titles[2].title == "Empty" and titles[3].title == "Ideas" and titles[4].title == "Done")
check("a moved column keeps its cards", #titles[3].cards == 2)
check("moving a column keeps every line", sortedLines(reordered) == sortedLines(page))
check("move a column back restores the page", kanban.columnMoved(reordered, 3, 1) == page)
local toEnd = kanban.columnMoved(page, 2, 4)
local ends = kanban.parse(toEnd).columns
check("move a column to the end stays above what follows the board", ends[4].title == "Doing"
  and toEnd:find("Another, indented with spaces\n\n# Notes", 1, true) ~= nil and #ends[4].cards == 1)
check("that keeps every line", sortedLines(toEnd) == sortedLines(page))
check("what follows the board stays off it", not toEnd:find("# Notes\n\n## ", 1, true))

local plain = "## A\n\n- [ ] a\n\n## B\n\n- [ ] b"
check("move the last column first at the page's end", kanban.columnMoved(plain, 2, 1) == "## B\n\n- [ ] b\n\n## A\n\n- [ ] a\n")

local lists = kanban.parse(kanban.columnAdded(page, "New", 2)).columns
check("add a column before another", #lists == 5 and lists[2].title == "New" and lists[3].title == "Doing")
local appendedList = kanban.columnAdded(page, "New")
check("add a column after the last, above what follows", appendedList:find("## New\n\n# Notes", 1, true) ~= nil)
check("rename a column", kanban.parse(kanban.columnRenamed(page, 1, "Later")).columns[1].title == "Later")
local noLoose = kanban.columnRemoved(page, 4)
check("delete a column with its section", #kanban.parse(noLoose).columns == 3
  and not noLoose:find("Loose text", 1, true) and noLoose:find("# Notes", 1, true) ~= nil)

if failures > 0 then
  print(failures .. " failed")
  os.exit(1)
end
