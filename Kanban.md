---
name: Library/arthurmartelli/Kanban
tags: meta/library
---
A Kanban board drawn from a plain Markdown page: each `##` section is a
column, and each top-level task under it, with its indented lines, is a card.
The page stays ordinary Markdown, so it reads and edits as before, with or
without the board.

# Usage
Put the board on the page it shows, for instance below the frontmatter:

```markdown
${kanban.board()}

## Doing

- [ ] Write the release notes
	- Check the changelog first

## Done

- [x] Tag the release
```

Or show another page's board with `${kanban.board("Projects/Board")}`. The
`Kanban: Insert Board` command inserts the expression at the cursor.

The chevron on a list folds it to a narrow strip with its title and card count,
until the app reloads. To have lists start folded each time the page opens,
name them in the frontmatter of the page they're on:

```yaml
---
kanban.folded: [Ideas, Chores]
---
```

Or name them on the board itself, which suits a board of another page:

```markdown
${kanban.board{ page = "Projects/Board", folded = {"Ideas"} }}
```

Drag a card to reorder it or move it to another list, sub-items included, and
drag a list by its title to reorder the lists. On a touch screen, drag by the
grip. `+ Add a card` adds a card at the end of a list. The `⋮` menu on a card
edits, checks, moves, inserts next to, duplicates, or deletes it; the one on a
list renames, inserts next to, or deletes it.

Checked cards are struck through. To check them from a box on each card, pass
`checkboxes = true`.

A heading of another level, or a `%%` comment, ends the board, so notes can
follow it.

# Text logic
```space-lua
-- priority: 10
-- The board's text logic: a page's ## sections are columns, and each
-- top-level task under one, with its indented lines, is a card. Moves and
-- toggles return the page's new text, so the page stays plain Markdown.
kanban = kanban or {}

local function splitLines(text)
  local lines, start = {}, 1
  while true do
    local i = string.find(text, "\n", start, true)
    if not i then
      table.insert(lines, string.sub(text, start))
      return lines
    end
    table.insert(lines, string.sub(text, start, i - 1))
    start = i + 1
  end
end

local function dedent(line)
  if string.sub(line, 1, 1) == "\t" then return string.sub(line, 2) end
  return (string.gsub(line, "^    ", "", 1))
end

--- Columns and cards of a board page.
function kanban.parse(text)
  local lines = splitLines(text)
  local board = { lines = lines, columns = {} }
  local i = 1
  if lines[1] == "---" then -- Frontmatter.
    i = 2
    while i <= #lines and lines[i] ~= "---" do i = i + 1 end
    i = i + 1
  end
  local column, card
  while i <= #lines do
    local line = lines[i]
    local title = string.match(line, "^## +(.-)%s*$")
    if title then
      if column then column.last = i - 1 end
      column = { title = title, heading = i, last = #lines, cards = {} }
      table.insert(board.columns, column)
      card = nil
    elseif string.match(line, "^#") or string.match(line, "^%%%%") then
      if column then column.last = i - 1 end
      column, card = nil, nil -- Another heading or a comment ends the board.
    elseif column then
      local mark, label = string.match(line, "^[-*] %[([ xX])%] ?(.*)$")
      if mark then
        card = { first = i, last = i, label = label, done = mark ~= " ", body = {} }
        table.insert(column.cards, card)
      elseif card and string.match(line, "^%s+%S") then
        card.last = i
        table.insert(card.body, dedent(line))
      elseif not string.match(line, "^%s*$") then
        card = nil
      end
    end
    i = i + 1
  end
  return board
end

local function join(...)
  local out = {}
  for _, part in ipairs({ ... }) do
    for _, line in ipairs(part) do table.insert(out, line) end
  end
  return table.concat(out, "\n")
end

local function slice(lines, first, last)
  local out = {}
  for j = first, last do table.insert(out, lines[j]) end
  return out
end

-- Text with lines put at a card position of a column, by default its end.
local function withCardLines(text, column, position, cardLines)
  local board = kanban.parse(text)
  local lines = board.lines
  local target = board.columns[column]
  local at
  local after = {}
  if target.cards[position] then
    at = target.cards[position].first
  elseif #target.cards > 0 then
    at = target.cards[#target.cards].last + 1
  else
    at = target.heading + 1
    if lines[at] == "" then at = at + 1 end -- Keep the blank line under the heading.
    -- Into an empty column, keep a blank line before the next heading.
    if lines[at] and lines[at] ~= "" then after = { "" } end
  end
  return join(slice(lines, 1, at - 1), cardLines, after, slice(lines, at, #lines))
end

local function withoutCard(board, card)
  local lines = board.lines
  local last = card.last
  -- A card between blank lines leaves two behind; drop one.
  if lines[card.first - 1] == "" and lines[last + 1] == "" then last = last + 1 end
  return join(slice(lines, 1, card.first - 1), slice(lines, last + 1, #lines))
end

--- The page's text with a card moved, to a position in another or the same
--- column, counted once the card has left it, or to the column's end.
function kanban.moved(text, fromColumn, cardIndex, toColumn, position)
  local board = kanban.parse(text)
  local card = board.columns[fromColumn].cards[cardIndex]
  local cardLines = slice(board.lines, card.first, card.last)
  return withCardLines(withoutCard(board, card), toColumn, position, cardLines)
end

--- The page's text with a new card at a position of a column, or at its end.
function kanban.added(text, column, label, position)
  return withCardLines(text, column, position, { "- [ ] " .. label })
end

--- The page's text with a card's first line relabelled.
function kanban.edited(text, column, cardIndex, label)
  local board = kanban.parse(text)
  local lines = board.lines
  local first = board.columns[column].cards[cardIndex].first
  lines[first] = string.match(lines[first], "^[-*] %[[ xX]%] ?") .. label
  return table.concat(lines, "\n")
end

--- The page's text with a copy of a card right after it.
function kanban.duplicated(text, column, cardIndex)
  local board = kanban.parse(text)
  local card = board.columns[column].cards[cardIndex]
  return withCardLines(text, column, cardIndex + 1, slice(board.lines, card.first, card.last))
end

--- The page's text without a card.
function kanban.removed(text, column, cardIndex)
  local board = kanban.parse(text)
  return withoutCard(board, board.columns[column].cards[cardIndex])
end

-- Text with a section's lines put before a column, by default after the last.
local function withSection(text, position, section)
  local board = kanban.parse(text)
  local lines = board.lines
  local target = board.columns[position]
  if target then
    return join(slice(lines, 1, target.heading - 1), section, { "" }, slice(lines, target.heading, #lines))
  end
  local at = board.columns[#board.columns].last + 1
  return join(slice(lines, 1, at - 1), lines[at - 1] ~= "" and { "" } or {}, section,
    lines[at] and { "" } or {}, slice(lines, at, #lines))
end

local function withoutSection(board, column)
  local section = board.columns[column]
  return join(slice(board.lines, 1, section.heading - 1), slice(board.lines, section.last + 1, #board.lines))
end

--- The page's text with a column moved to a position, counted once it has left.
function kanban.columnMoved(text, column, position)
  local board = kanban.parse(text)
  local section = board.columns[column]
  local last = section.last
  while last > section.heading and board.lines[last] == "" do last = last - 1 end
  return withSection(withoutSection(board, column), position, slice(board.lines, section.heading, last))
end

--- The page's text with a new, empty column before a position, or after the last.
function kanban.columnAdded(text, title, position)
  return withSection(text, position, { "## " .. title })
end

--- The page's text with a column retitled.
function kanban.columnRenamed(text, column, title)
  local board = kanban.parse(text)
  board.lines[board.columns[column].heading] = "## " .. title
  return table.concat(board.lines, "\n")
end

--- The page's text without a column and all that its section holds.
function kanban.columnRemoved(text, column)
  return withoutSection(kanban.parse(text), column)
end

--- Whether a column starts folded, given the title or titles configured to.
function kanban.startsFolded(folded, title)
  if type(folded) == "string" then folded = { folded } end
  if type(folded) ~= "table" then return false end
  for _, name in ipairs(folded) do
    if name == title then return true end
  end
  return false
end

--- The page's text with a card checked or unchecked.
function kanban.toggled(text, column, cardIndex)
  local board = kanban.parse(text)
  local lines = board.lines
  local card = board.columns[column].cards[cardIndex]
  local mark = card.done and "[ ]" or "[x]"
  lines[card.first] = string.gsub(lines[card.first], "%[[ xX]%]", mark, 1)
  return table.concat(lines, "\n")
end
```

# Widget
Children are added one at a time and text through `__rawText`, the forms every
SilverBullet 2 release's `dom` accepts: older ones take no lists of children,
`false` children, class lists, or `dom.text`.

Dragging uses pointer events rather than HTML drag and drop, which touch
screens don't fire and which needs answers Lua callbacks may give too late.

```space-lua
-- priority: 5

-- Columns folded or unfolded by hand, which outlive the board's redraws.
kanban.folds = kanban.folds or {}

-- A list of actions in the filter box, running the one picked.
local function menu(label, items)
  local options = {}
  for i, item in ipairs(items) do
    table.insert(options, { name = item.name, value = i, orderId = i })
  end
  local picked = editor.filterBox(label, options)
  if picked then items[picked.value].run() end
end

-- Whether a line of text was given, to act on.
local function given(text)
  return text and string.match(text, "%S") ~= nil
end

-- Makes a handle drag a node: past a few pixels a copy follows the pointer,
-- `over` marks the spot under it and returns what to `drop` there. A mouse
-- drags from anywhere on the handle, a touch only from its grip, so the page
-- still scrolls under a finger.
local function draggable(handle, node, scroller, over, drop)
  local drag
  local function finish()
    if drag and drag.copy then
      drag.copy.remove()
      node.classList.remove("kb-dragging")
      over(nil, nil)
    end
    drag = nil
  end
  handle.addEventListener("pointerdown", function(event)
    if event.button ~= 0 or event.target.closest("button") then return end
    if event.pointerType ~= "mouse" and not event.target.closest(".kb-grip") then return end
    local rect = node.getBoundingClientRect()
    drag = {
      x = event.clientX,
      y = event.clientY,
      left = rect.left - event.clientX,
      top = rect.top - event.clientY,
      width = rect.width,
    }
  end)
  handle.addEventListener("pointermove", function(event)
    if not drag then return end
    local x, y = event.clientX, event.clientY
    if not drag.copy then
      if math.abs(x - drag.x) + math.abs(y - drag.y) < 5 then return end
      handle.setPointerCapture(event.pointerId)
      drag.copy = node.cloneNode(true)
      drag.copy.classList.add("kb-drag-copy")
      scroller.appendChild(drag.copy)
      node.classList.add("kb-dragging")
    end
    drag.copy.setAttribute("style", "left:" .. (x + drag.left) .. "px;top:" .. (y + drag.top)
      .. "px;width:" .. drag.width .. "px")
    local edges = scroller.getBoundingClientRect()
    if x < edges.left + 30 then
      scroller.scrollLeft = scroller.scrollLeft - 15
    elseif x > edges.right - 30 then
      scroller.scrollLeft = scroller.scrollLeft + 15
    end
    drag.spot = over(x, y)
  end)
  handle.addEventListener("pointerup", function()
    local spot = drag and drag.copy and drag.spot
    finish()
    if spot then drop(spot) end
  end)
  handle.addEventListener("pointercancel", finish)
end

-- The class marking a drop spot on one node at a time.
local function marker()
  local node, class
  return function(newNode, newClass)
    if node then node.classList.remove(class) end
    node, class = newNode, newClass
    if node then node.classList.add(class) end
  end
end

--- The board of a page, the current one when no name is given.
---@param options string|table? A page name, or `page`, `folded`, the section titles that start folded, and `checkboxes`, whether cards show a box to check them.
function kanban.board(options)
  if type(options) ~= "table" then options = { page = options } end
  local pageName = options.page
  return widget.new {
    refreshOn = { "edit", "index" },
    content = function()
      local current = editor.getCurrentPage()
      local page = pageName or current
      local function read()
        if page == current then return editor.getText() end
        return space.readPage(page)
      end
      local function write(text)
        if page == current then
          editor.setText(text, true)
        else
          space.writePage(page, text)
        end
      end

      local text = read()
      local board = kanban.parse(text)
      if #board.columns == 0 then
        return "*No `##` sections to make columns from.*"
      end

      local function askCard(ci, position)
        local label = editor.prompt("New card in " .. board.columns[ci].title .. ":")
        if given(label) then write(kanban.added(read(), ci, label, position)) end
      end
      local function askColumn(position)
        local title = editor.prompt("New list:")
        if given(title) then write(kanban.columnAdded(read(), title, position)) end
      end

      local function cardMenu(ci, ki)
        local card = board.columns[ci].cards[ki]
        local items = {
          { name = "Edit card", run = function()
            local label = editor.prompt("Card:", card.label)
            if given(label) then write(kanban.edited(read(), ci, ki, label)) end
          end },
          { name = card.done and "Uncheck card" or "Check card", run = function()
            write(kanban.toggled(read(), ci, ki))
          end },
          { name = "Move to top", run = function() write(kanban.moved(read(), ci, ki, ci, 1)) end },
          { name = "Move to bottom", run = function() write(kanban.moved(read(), ci, ki, ci)) end },
        }
        for ti, target in ipairs(board.columns) do
          if ti ~= ci then
            table.insert(items, { name = "Move to list: " .. target.title, run = function()
              write(kanban.moved(read(), ci, ki, ti))
            end })
          end
        end
        table.insert(items, { name = "Insert card before", run = function() askCard(ci, ki) end })
        table.insert(items, { name = "Insert card after", run = function() askCard(ci, ki + 1) end })
        table.insert(items, { name = "Duplicate card", run = function()
          write(kanban.duplicated(read(), ci, ki))
        end })
        table.insert(items, { name = "Delete card", run = function()
          if editor.confirm("Delete this card?\n\n" .. card.label) then
            write(kanban.removed(read(), ci, ki))
          end
        end })
        menu("Card", items)
      end

      local function columnMenu(ci)
        local column = board.columns[ci]
        menu("List", {
          { name = "Rename list", run = function()
            local title = editor.prompt("List:", column.title)
            if given(title) then write(kanban.columnRenamed(read(), ci, title)) end
          end },
          { name = "Insert list before", run = function() askColumn(ci) end },
          { name = "Insert list after", run = function() askColumn(ci + 1) end },
          { name = "Delete list", run = function()
            local cards = #column.cards == 1 and "1 card" or #column.cards .. " cards"
            if editor.confirm("Delete " .. column.title .. " and its " .. cards .. "?") then
              write(kanban.columnRemoved(read(), ci))
            end
          end },
        })
      end

      local attributes = index.extractFrontmatter(text).frontmatter
      local pageFolded = attributes["kanban.folded"]
      if pageFolded == nil and type(attributes.kanban) == "table" then
        pageFolded = attributes.kanban.folded
      end

      local columns = { class = "kb-board" }
      local views = {}
      for ci, column in ipairs(board.columns) do
        local foldKey = page .. "\n" .. column.title
        local folded = kanban.folds[foldKey]
        if folded == nil then
          folded = kanban.startsFolded(options.folded, column.title)
            or kanban.startsFolded(pageFolded, column.title)
        end
        local node, foldButton
        foldButton = dom.button {
          class = "kb-fold",
          title = folded and "Unfold" or "Fold",
          ["aria-expanded"] = folded and "false" or "true",
          onclick = function()
            local now = not node.classList.contains("kb-folded")
            kanban.folds[foldKey] = now
            node.classList.toggle("kb-folded")
            foldButton.title = now and "Unfold" or "Fold"
            foldButton.setAttribute("aria-expanded", now and "false" or "true")
          end,
        }
        local title = dom.div {
          class = "kb-title",
          dom.span { class = "kb-grip" },
          foldButton,
          dom.span { class = "kb-name", title = column.title, __rawText = column.title },
          dom.span { class = "kb-count", __rawText = tostring(#column.cards) },
          dom.button {
            class = "kb-menu",
            title = "List menu",
            onclick = function() columnMenu(ci) end,
          },
        }
        local element = {
          class = folded and "kb-column kb-folded" or "kb-column",
          title,
        }
        local view = { handle = title, cards = {} }
        for ki, card in ipairs(column.cards) do
          local text = card.label
          if #card.body > 0 then
            text = text .. "\n\n" .. table.concat(card.body, "\n")
          end
          local spec = {
            class = card.done and "kb-card kb-done" or "kb-card",
            dom.span { class = "kb-grip" },
          }
          if options.checkboxes then
            -- A button, since the editor keeps clicks from real checkboxes in widgets.
            table.insert(spec, dom.button {
              class = "kb-check",
              role = "checkbox",
              ["aria-checked"] = card.done and "true" or "false",
              title = card.done and "Uncheck" or "Check",
              onclick = function() write(kanban.toggled(read(), ci, ki)) end,
            })
          end
          table.insert(spec, dom.div { class = "kb-text", text })
          table.insert(spec, dom.button {
            class = "kb-menu",
            title = "Card menu",
            onclick = function() cardMenu(ci, ki) end,
          })
          local cardNode = dom.div(spec)
          -- A link in a card drags the card; a plain click still follows it.
          local links = cardNode.querySelectorAll("a")
          for li = 1, links.length do links[li].setAttribute("draggable", "false") end
          table.insert(view.cards, cardNode)
          table.insert(element, cardNode)
        end
        table.insert(element, dom.button {
          class = "kb-add",
          onclick = function() askCard(ci) end,
          __rawText = "+ Add a card",
        })
        node = dom.div(element)
        view.node = node
        table.insert(views, view)
        table.insert(columns, node)
      end
      local boardNode = dom.div(columns)

      local mark = marker()
      -- The card position under the pointer in a list, counted without the
      -- dragged card, and the card it goes before.
      local function cardSpot(view, dragged, y)
        local position = 1
        for _, cardNode in ipairs(view.cards) do
          if cardNode ~= dragged then
            local rect = cardNode.getBoundingClientRect()
            if rect.height > 0 and y < rect.top + rect.height / 2 then
              return position, cardNode
            end
            position = position + 1
          end
        end
        return position, nil
      end
      for ci, view in ipairs(views) do
        for ki, cardNode in ipairs(view.cards) do
          draggable(cardNode, cardNode, boardNode, function(x, y)
            if not x then return mark(nil) end
            for ti, target in ipairs(views) do
              local rect = target.node.getBoundingClientRect()
              if x >= rect.left and x <= rect.right then
                local position, before = cardSpot(target, cardNode, y)
                if before then
                  mark(before, "kb-drop-before")
                else
                  mark(target.node, "kb-drop-end")
                end
                return { column = ti, position = position }
              end
            end
            mark(nil)
            return nil
          end, function(spot)
            if spot.column == ci and spot.position == ki then return end
            write(kanban.moved(read(), ci, ki, spot.column, spot.position))
          end)
        end
        draggable(view.handle, view.node, boardNode, function(x)
          if not x then return mark(nil) end
          local position = 1
          for _, target in ipairs(views) do
            if target ~= view then
              local rect = target.node.getBoundingClientRect()
              if x < rect.left + rect.width / 2 then
                mark(target.node, "kb-drop-left")
                return { position = position }
              end
              position = position + 1
            end
          end
          local last = views[#views] ~= view and views[#views] or views[#views - 1]
          if last then mark(last.node, "kb-drop-right") end
          return { position = position }
        end, function(spot)
          if spot.position == ci then return end
          write(kanban.columnMoved(read(), ci, spot.position))
        end)
      end
      return widget.htmlBlock(boardNode)
    end,
  }
end

command.define {
  name = "Kanban: Insert Board",
  run = function()
    editor.insertAtCursor("${kanban.board()}\n")
  end,
}
```

# Style
```space-style
.kb-board {
  display: flex;
  gap: 0.75rem;
  overflow-x: auto;
  align-items: flex-start;
  padding-bottom: 0.5rem;
}
.kb-column {
  flex: 1 0 13rem;
  max-width: 20rem;
  background: var(--panel-background-color);
  border: 1px solid var(--panel-border-color);
  border-radius: 8px;
}
.kb-title {
  display: flex;
  align-items: center;
  gap: 0.375rem;
  padding: 0.375rem 0.5rem;
  border-bottom: 1px solid var(--panel-border-color);
  margin-bottom: 0.5rem;
  user-select: none;
}
.kb-name {
  flex: 1;
  min-width: 0;
  font-weight: 600;
  overflow-wrap: anywhere;
}
.kb-count {
  opacity: 0.6;
  font-size: 0.85em;
}
.kb-grip {
  flex: none;
  width: 8px;
  height: 14px;
  opacity: 0.45;
  cursor: grab;
  touch-action: none;
  background-image: radial-gradient(currentColor 1px, transparent 1.25px);
  background-size: 4px 4px;
}
.kb-title,
.kb-card {
  cursor: grab;
}
.kb-fold,
.kb-menu {
  flex: none;
  width: 1.25rem;
  height: 1.25rem;
  padding: 0;
  border: none;
  border-radius: 4px;
  background: transparent;
  color: inherit;
  opacity: 0.6;
  cursor: pointer;
  position: relative;
}
.kb-fold:hover,
.kb-menu:hover {
  opacity: 1;
  background: color-mix(in srgb, currentColor 12%, transparent);
}
.kb-fold::before {
  content: "";
  position: absolute;
  left: 50%;
  top: 50%;
  width: 0.4rem;
  height: 0.4rem;
  border-right: 1.5px solid currentColor;
  border-bottom: 1.5px solid currentColor;
  transform: translate(-50%, -70%) rotate(45deg);
}
.kb-folded .kb-fold::before {
  transform: translate(-70%, -50%) rotate(-45deg);
}
.kb-menu::before {
  content: "";
  position: absolute;
  left: 50%;
  top: 50%;
  width: 3px;
  height: 3px;
  margin: -1.5px;
  border-radius: 50%;
  background: currentColor;
  box-shadow: 0 -5px currentColor, 0 5px currentColor;
}
.kb-folded {
  flex: 0 0 auto;
}
.kb-folded .kb-title {
  flex-direction: column;
  padding: 0.5rem 0.25rem;
  border-bottom: none;
  margin-bottom: 0;
}
.kb-folded .kb-name {
  flex: none;
  writing-mode: vertical-rl;
  transform: rotate(180deg);
  max-height: 14rem;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.kb-folded .kb-card,
.kb-folded .kb-add,
.kb-folded .kb-menu {
  display: none;
}
.kb-card {
  display: flex;
  align-items: flex-start;
  gap: 0.375rem;
  background: color-mix(in srgb, currentColor 6%, transparent);
  border-radius: 6px;
  padding: 0.375rem 0.25rem 0.375rem 0.5rem;
  margin: 0 0.5rem 0.5rem;
  font-size: 0.9em;
  user-select: none;
}
.kb-card .kb-grip {
  margin-top: 0.25em;
}
@media (hover: hover) {
  .kb-card .kb-grip {
    display: none;
  }
}
.kb-text {
  flex: 1;
  min-width: 0;
  overflow-wrap: anywhere;
}
.kb-text p,
.kb-text ul {
  margin: 0;
}
.kb-text ul {
  padding-left: 1.1em;
  opacity: 0.7;
}
.kb-done .kb-text {
  text-decoration: line-through;
  opacity: 0.6;
}
.kb-check {
  flex: none;
  width: 1em;
  height: 1em;
  margin-top: 0.25em;
  padding: 0;
  border: 1px solid currentColor;
  border-radius: 3px;
  background: transparent;
  cursor: pointer;
}
.kb-check[aria-checked="true"] {
  background: currentColor;
}
.kb-add {
  display: block;
  width: calc(100% - 1rem);
  margin: 0 0.5rem 0.5rem;
  padding: 0.375rem;
  border: none;
  border-radius: 6px;
  background: transparent;
  color: inherit;
  opacity: 0.65;
  font: inherit;
  font-size: 0.85em;
  cursor: pointer;
}
.kb-add:hover {
  opacity: 1;
  background: color-mix(in srgb, currentColor 8%, transparent);
}
.kb-dragging {
  opacity: 0.35;
}
.kb-drag-copy {
  position: fixed;
  z-index: 1000;
  margin: 0;
  pointer-events: none;
  cursor: grabbing;
  color: var(--root-color);
  background: var(--panel-background-color);
  box-shadow: 0 4px 16px rgb(0 0 0 / 35%);
}
.kb-drop-before {
  box-shadow: 0 -3px 0 var(--ui-accent-color, currentColor);
}
.kb-drop-end {
  box-shadow: inset 0 -3px 0 var(--ui-accent-color, currentColor);
}
.kb-drop-left {
  box-shadow: -3px 0 0 var(--ui-accent-color, currentColor);
}
.kb-drop-right {
  box-shadow: 3px 0 0 var(--ui-accent-color, currentColor);
}
```
