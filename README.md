# SilverBullet Kanban

A Kanban board for [SilverBullet](https://silverbullet.md) 2, drawn from a
plain Markdown page: each `##` section is a column, and each top-level task
under it, with its indented lines, is a card. The page stays ordinary
Markdown, so it reads and edits as before, with or without the board, and
moves from Obsidian's Kanban plugin keep working.

```markdown
${kanban.board()}

## Doing

- [ ] Write the release notes
	- Check the changelog first

## Done

- [x] Tag the release
```

On a card, the checkbox checks the task, and the arrows move it, sub-items
included, to the end of the previous or next column.
`${kanban.board("Some/Page")}` shows another page's board, and the
`Kanban: Insert Board` command inserts the expression at the cursor.

## Install

Run `Library: Install` in SilverBullet with this URI:

```text
github:arthurmartelli/silverbullet-kanban@main/Kanban.md
```

It installs to `Library/arthurmartelli/Kanban`.

## Develop

[Kanban.md](Kanban.md) is the whole library. Its first `space-lua` block holds
the text logic, which the tests load and run with plain Lua 5.4:

```sh
lua test/kanban_test.lua
```
