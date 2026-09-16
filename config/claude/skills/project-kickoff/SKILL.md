---
name: project-kickoff
description: Start work on a task in a repository — orient in the codebase, ask any blocking questions, present a plan, then implement it. Also sets up the kitty dev workspace (Claude plus git plus one window per dev server) via the `devwin` shell function. Use when beginning a new piece of work, picking up a ticket or issue, or when asked to open a dev workspace for a project.
argument-hint: "[task description or ticket id]"
---

# Starting work on a task

The goal is to reach a concrete plan and begin executing it without making the
user re-explain what they already wrote down somewhere.

## 1. Understand the task

Get the actual text of the request — a ticket, an issue, a description in chat.
If a tracker is available as an MCP server or CLI, read the item directly rather
than working from its title. Pull out the summary, acceptance criteria, status,
linked items, and the comments, which often carry the real requirements and any
late changes of scope.

If you can't reach the source, say so plainly and ask for the text. Don't guess
at requirements from a branch name.

## 2. Orient in the code

Read the repo's `CLAUDE.md` first, then `README` and any contributing guide.

Find the code the task touches by searching for the domain words in the request,
not by guessing file paths. Before writing anything, note the patterns already
in use near the change site — how similar features are structured, where their
tests live, what the naming looks like. Match that instead of introducing new
structure.

If the repo uses git worktrees or Git Town, check where this branch sits:

```bash
git config --get-regexp '^git-town-branch\.'
git town diff-parent      # if the parent isn't the main branch
```

A branch with a non-main parent builds on unmerged work — read that diff first.
See the `git-town-worktree` skill.

## 3. Ask before planning, not after

Ask only questions that change the plan, and ask them together. Worth asking
about: ambiguous acceptance criteria, two equally plausible places to make the
change, an implied schema or API change, or scope that looks like more than one
reviewable PR.

If nothing is genuinely ambiguous, skip this and plan.

## 4. Plan, then build

A short plan: what changes, in which files, in what order, and how it gets
verified. Flag anything that needs the user's decision. Then **implement it** —
do not wait for approval unless a question from step 3 is still unanswered.

The kickoff prompt may carry extra context the user typed when starting the
session (`ready "check the form ordering logic"`). Treat that as their steer on
where to look, and weight it above your own first guess.

While building:

- Match the surrounding style. Reuse existing helpers rather than adding
  abstractions.
- Comments: default to none. Write one only where the code cannot explain
  itself — a constraint, a workaround, a reason the order matters. Never restate
  the line below it, and never add section-header banners. Before finishing,
  re-read your diff and delete every comment that only says what the code says.
  If you edited code a comment describes, update that comment in the same edit.
- Add or update tests, using the repo's own runner and conventions.
- If the work splits into independently reviewable pieces, propose a stack and
  order it so each piece is safe to ship on its own.
- Commit as you go, referencing the ticket or issue id.

## The dev workspace

`devwin [dir] [claude-prompt]` opens a new kitty OS window laid out for the repo:

```
┌────────────────────┬──────────────────┐
│                    │  git / commands  │
│                    ├──────────────────┤
│   CLAUDE           │  dev server 1    │
│   (focused)        ├──────────────────┤
│                    │  dev server 2    │
└────────────────────┴──────────────────┘
```

Claude takes the left half and starts focused. The right column holds a shell
for git and one window per dev server. **Server commands are typed into their
prompts but not run** — the user presses Enter when dependencies are installed
and they actually want them up.

Commands are inferred from `package.json`:

1. A root `dev` script wins — one window running `yarn dev`.
2. Otherwise, each **non-glob** workspace entry with a `dev` or `start` script
   gets a window. Globbed entries like `packages/*` are treated as libraries,
   since they often carry unrelated `start` scripts.
3. Failing that, globbed workspaces with a `dev` script specifically.
4. Failing that, a root `start` script.

The generated session file lands in `~/.local/state/devwin/<dir-name>.kitty-session`.
Read it to see exactly what was set up. If the inference picked the wrong
servers, edit that file and rerun `kitty --single-instance --session <file>`, and
tell the user which rule guessed wrong so it can be corrected.

`devwin` and the prompt-prefill hook live in `~/dotfiles/config/shell/`
(`.functions.zsh` and `.zshrc`).

## The ticket workspace

`workspace` opens the whole working set and puts it on one dedicated space:

```
workspace --dir D [--name N] [--prompt P] [--url U]...
```

VS Code, kitty and the browser each fill the whole space and are stacked, with
VS Code in front. Cmd+Tab moves between them; each is full size rather than a
cramped quarter.

What the placement relies on, all verified on this machine:

- **Moving a window to an existing space works without the scripting addition**
  (`window --space N`, `window --display N`). Only `space --create` is blocked,
  so keep a few spare spaces made by hand in Mission Control — `workspace`
  claims the first one on the main display with no windows on it.
- `--grid 1:1:0:0:1:1` fills the usable area, with yabai computing the menu bar,
  Dock and padding. Prefer it over absolute move/resize, which has to work
  around apps that refuse to grow near a screen edge and apps with minimum
  sizes (Chrome will not go below ~375px tall).
- A **native-fullscreen window owns its own space and will not move**. VS Code
  often opens that way, so un-fullscreen it first (`--toggle native-fullscreen`)
  before moving it.
- Focusing a space restores whichever window that space last had focused, so
  re-focus the window you want in front afterwards.

`workspace_tile` re-fills and re-stacks whatever is on the current space — safe
to rerun, takes no arguments.

## Switching between workspaces

`workspace` records its window ids and space under
`~/.local/state/workspace/<NAME>.ids`.

```
ws                 list saved workspaces, their space, and surviving windows
ws NAME            focus NAME's space and restore its stacking order
ws --forget NAME   drop a saved workspace
```

yabai must be running (`yabai --start-service`) with macOS Accessibility
permission, or it aborts with "could not access accessibility features".
Config lives in `~/.yabairc`.
