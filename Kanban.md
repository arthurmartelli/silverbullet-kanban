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

On a card, the checkbox checks the task, and the `<` and `>` buttons move it to the end of
the previous or next column, sub-items included. A heading of another level,
or a `%%` comment, ends the board, so notes can follow it.

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
      column = { title = title, heading = i, cards = {} }
      table.insert(board.columns, column)
      card = nil
    elseif string.match(line, "^#") or string.match(line, "^%%%%") then
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

--- The page's text with a card moved to the end of another column.
function kanban.moved(text, fromColumn, cardIndex, toColumn)
  local board = kanban.parse(text)
  local lines = board.lines
  local card = board.columns[fromColumn].cards[cardIndex]
  local target = board.columns[toColumn]
  local at
  if #target.cards > 0 then
    at = target.cards[#target.cards].last + 1
  else
    at = target.heading + 1
    if lines[at] == "" then at = at + 1 end -- Keep the blank line under the heading.
  end
  local out = {}
  local function insertCard()
    for j = card.first, card.last do table.insert(out, lines[j]) end
    -- Into an empty column, keep a blank line before the next heading.
    if #target.cards == 0 and lines[at] and lines[at] ~= "" then table.insert(out, "") end
  end
  -- A card between blank lines leaves two behind; drop one.
  local last = card.last
  if lines[card.first - 1] == "" and lines[last + 1] == "" then last = last + 1 end
  for j = 1, #lines do
    if j == at then insertCard() end
    if j < card.first or j > last then table.insert(out, lines[j]) end
  end
  if at > #lines then insertCard() end
  return table.concat(out, "\n")
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

```space-lua
-- priority: 5

--- The board of a page, the current one when no name is given.
---@param pageName string? Page whose sections become the columns.
function kanban.board(pageName)
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

      local board = kanban.parse(read())
      local columns = { class = "kb-board" }
      for ci, column in ipairs(board.columns) do
        local element = {
          class = "kb-column",
          dom.div {
            class = "kb-title",
            dom.span { __rawText = column.title },
            dom.span { class = "kb-count", __rawText = tostring(#column.cards) },
          },
        }
        for ki, card in ipairs(column.cards) do
          local text = card.label
          if #card.body > 0 then
            text = text .. "\n\n" .. table.concat(card.body, "\n")
          end
          -- A button, since the editor keeps clicks from real checkboxes in widgets.
          local check = dom.button {
            class = "kb-check",
            role = "checkbox",
            ["aria-checked"] = card.done and "true" or "false",
            title = card.done and "Uncheck" or "Check",
            onclick = function() write(kanban.toggled(read(), ci, ki)) end,
          }
          local moves = { class = "kb-moves" }
          if ci > 1 then
            table.insert(moves, dom.button {
              title = "Move to " .. board.columns[ci - 1].title,
              onclick = function() write(kanban.moved(read(), ci, ki, ci - 1)) end,
              __rawText = "<",
            })
          end
          if ci < #board.columns then
            table.insert(moves, dom.button {
              title = "Move to " .. board.columns[ci + 1].title,
              onclick = function() write(kanban.moved(read(), ci, ki, ci + 1)) end,
              __rawText = ">",
            })
          end
          table.insert(element, dom.div {
            class = card.done and "kb-card kb-done" or "kb-card",
            check,
            dom.div { class = "kb-text", text },
            dom.div(moves),
          })
        end
        if #column.cards == 0 then
          table.insert(element, dom.div { class = "kb-empty", __rawText = "No cards" })
        end
        table.insert(columns, dom.div(element))
      end
      if #board.columns == 0 then
        return "*No `##` sections to make columns from.*"
      end
      return widget.htmlBlock(dom.div(columns))
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
  flex: 1 0 12rem;
  max-width: 18rem;
  background: var(--panel-background-color);
  border: 1px solid var(--panel-border-color);
  border-radius: 8px;
  padding: 0.5rem;
}
.kb-title {
  display: flex;
  justify-content: space-between;
  font-weight: 600;
  padding: 0.125rem 0.25rem 0.5rem;
}
.kb-count {
  opacity: 0.6;
  font-weight: normal;
}
.kb-card {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 0 0.5rem;
  background: var(--root-background-color);
  border: 1px solid var(--panel-border-color);
  border-radius: 6px;
  padding: 0.375rem 0.5rem;
  margin-bottom: 0.5rem;
  font-size: 0.9em;
}
.kb-check {
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
.kb-moves {
  grid-column: 2;
  display: flex;
  justify-content: flex-end;
  gap: 0.25rem;
}
.kb-moves button {
  border: none;
  background: transparent;
  color: inherit;
  opacity: 0.6;
  cursor: pointer;
  padding: 0 0.375rem;
}
.kb-moves button:hover {
  opacity: 1;
}
.kb-empty {
  opacity: 0.6;
  font-size: 0.85em;
  padding: 0.25rem;
}
```
