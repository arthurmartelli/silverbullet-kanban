-- Tests the board's text logic, loaded from the first space-lua block in Kanban.md.

local f = assert(io.open("Kanban.md"))
local library = f:read("a")
f:close()

local logic = assert(library:match("```space%-lua\n(.-)\n```"), "no space-lua block")
assert(load(logic, "Kanban.md"))()

local failures = 0

local function show(value)
  return (tostring(value):gsub("\n", "\\n"):gsub("\t", "\\t"))
end

local function check(name, got, expected)
  if got == expected then
    print("ok   " .. name)
    return
  end
  failures = failures + 1
  print("FAIL " .. name .. "\n  expected: " .. show(expected) .. "\n  got:      " .. show(got))
end

-- A board in one line: "List: card, card | List:", where a checked card
-- starts with [x] and +n counts its sub-item lines.
local function outline(text)
  local lists = {}
  for _, column in ipairs(kanban.parse(text).columns) do
    local cards = {}
    for _, card in ipairs(column.cards) do
      local label = card.label
      if card.done then label = "[x] " .. label end
      if #card.body > 0 then label = label .. "+" .. #card.body end
      table.insert(cards, label)
    end
    local list = column.title .. ":"
    if #cards > 0 then list = list .. " " .. table.concat(cards, ", ") end
    table.insert(lists, list)
  end
  return table.concat(lists, " | ")
end

local page = table.concat({
  "---",
  "title: Board",
  "## not a column, frontmatter",
  "---",
  "${kanban.board()}",
  "",
  "## Ideas",
  "",
  "- [ ] one",
  "- [ ] two",
  "",
  "## Doing",
  "",
  "- [ ] three [[Some Page]]",
  "\t- tab-indented",
  "    - space-indented",
  "",
  "## Empty",
  "",
  "## Done",
  "",
  "- [x] four",
  "loose text",
  "\t- not part of a card",
  "",
  "# Notes",
  "",
  "- [ ] not on the board",
}, "\n")

-- Reading a board

check("lists from ## sections, cards from top-level tasks",
  outline(page), "Ideas: one, two | Doing: three [[Some Page]]+2 | Empty: | Done: [x] four")
check("sub-items lose one level of indent",
  table.concat(kanban.parse(page).columns[2].cards[1].body, "\n"), "- tab-indented\n- space-indented")

-- Cards

check("move a card to another list's end",
  outline(kanban.moved(page, 1, 1, 4)), "Ideas: two | Doing: three [[Some Page]]+2 | Empty: | Done: [x] four, one")
check("move a card into an empty list, with its sub-items",
  outline(kanban.moved(page, 2, 1, 3)), "Ideas: one, two | Doing: | Empty: three [[Some Page]]+2 | Done: [x] four")
check("move a card between two others",
  outline(kanban.moved(page, 2, 1, 1, 2)), "Ideas: one, three [[Some Page]]+2, two | Doing: | Empty: | Done: [x] four")
check("move a card to the top of its list",
  outline(kanban.moved(page, 1, 2, 1, 1)), "Ideas: two, one | Doing: three [[Some Page]]+2 | Empty: | Done: [x] four")
check("move a card to the end of its list",
  outline(kanban.moved(page, 1, 1, 1)), "Ideas: two, one | Doing: three [[Some Page]]+2 | Empty: | Done: [x] four")
check("moving a card back restores the page",
  kanban.moved(kanban.moved(page, 2, 1, 3), 3, 1, 2), page)

check("check a card",
  outline(kanban.toggled(page, 1, 2)), "Ideas: one, [x] two | Doing: three [[Some Page]]+2 | Empty: | Done: [x] four")
check("checking twice restores the page",
  kanban.toggled(kanban.toggled(page, 1, 2), 1, 2), page)

check("add a card at a list's end",
  outline(kanban.added(page, 1, "new")), "Ideas: one, two, new | Doing: three [[Some Page]]+2 | Empty: | Done: [x] four")

check("edit a card, keeping its mark",
  outline(kanban.edited(page, 4, 1, "renamed")), "Ideas: one, two | Doing: three [[Some Page]]+2 | Empty: | Done: [x] renamed")
check("edit a card, keeping its sub-items",
  outline(kanban.edited(page, 2, 1, "renamed")), "Ideas: one, two | Doing: renamed+2 | Empty: | Done: [x] four")
check("edit a card to a label with pattern characters",
  outline(kanban.edited(page, 1, 1, "100% %1 [x]")), "Ideas: 100% %1 [x], two | Doing: three [[Some Page]]+2 | Empty: | Done: [x] four")

-- Lists

check("move a list",
  outline(kanban.columnMoved(page, 1, 3)), "Doing: three [[Some Page]]+2 | Empty: | Ideas: one, two | Done: [x] four")
check("moving a list back restores the page",
  kanban.columnMoved(kanban.columnMoved(page, 1, 3), 3, 1), page)
check("add a list before another",
  outline(kanban.columnAdded(page, "New", 2)), "Ideas: one, two | New: | Doing: three [[Some Page]]+2 | Empty: | Done: [x] four")
check("rename a list",
  outline(kanban.columnRenamed(page, 1, "Later")), "Later: one, two | Doing: three [[Some Page]]+2 | Empty: | Done: [x] four")
local withoutDone = kanban.columnRemoved(page, 4)
check("delete a list",
  outline(withoutDone), "Ideas: one, two | Doing: three [[Some Page]]+2 | Empty:")
local tail = "## Empty\n\n# Notes\n\n- [ ] not on the board"
check("deleting a list takes its loose text and keeps what follows the board",
  withoutDone:sub(-#tail), tail)

-- Blank lines and what follows the board

local small = "## A\n\n- [ ] a\n\t- sub\n\n## B\n\n# Notes"
check("move a card into an empty list, above what follows",
  kanban.moved(small, 1, 1, 2), "## A\n\n## B\n\n- [ ] a\n\t- sub\n\n# Notes")
check("add a card to an empty list, above what follows",
  kanban.added(small, 2, "b"), "## A\n\n- [ ] a\n\t- sub\n\n## B\n\n- [ ] b\n\n# Notes")
check("delete a card and its sub-items",
  kanban.removed(small, 1, 1), "## A\n\n## B\n\n# Notes")
check("move a list to the end, above what follows",
  kanban.columnMoved(small, 1, 2), "## B\n\n## A\n\n- [ ] a\n\t- sub\n\n# Notes")
check("add a list at the end, above what follows",
  kanban.columnAdded(small, "C"), "## A\n\n- [ ] a\n\t- sub\n\n## B\n\n## C\n\n# Notes")
check("move the last list first, at the page's end",
  kanban.columnMoved("## A\n\n- [ ] a\n\n## B\n\n- [ ] b", 2, 1), "## B\n\n- [ ] b\n\n## A\n\n- [ ] a\n")

-- Folding

check("a named list starts folded", kanban.startsFolded({ "Ideas", "Done" }, "Done"), true)
check("other lists start unfolded", kanban.startsFolded({ "Ideas" }, "Doing"), false)
check("no titles fold nothing", kanban.startsFolded(nil, "Doing"), false)

if failures > 0 then
  print(failures .. " failed")
  os.exit(1)
end
