---
name: project-kickoff
description: Start work on a task in a repository — research the codebase with subagents, ask any blocking questions, plan, have the plan reviewed, then build it test-first with a code review per branch. Also sets up the kitty dev workspace (Claude plus git plus one window per dev server) via the `devwin` shell function. Use when beginning a new piece of work, picking up a ticket or issue, or when asked to open a dev workspace for a project.
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

## 2. Size the work

For a small, obvious change (a few lines, one file, no design choices), skip
the subagents: read the code, make the change, test it, and follow "While
building" below. Use the full workflow for anything bigger.

## 3. The workflow

Uses the subagents in `~/.claude/agents/` (kept in
`~/dotfiles/config/claude/agents/`): `researcher`, `reviewer`, `tester`.
A subagent sees only the prompt you write, so every prompt includes the full
task text (with acceptance criteria and comments), the repo and worktree path,
any steer the user gave, and any repo-specific rules a calling skill adds
(deploy rules, test and typecheck commands). Design is judged by `design-principles.md` in
this skill's folder; the subagents read it themselves.

Run subagents in the foreground. Launch subagents that run at the same time in
one message; launched in separate messages they run one after another.
Background subagents get only a limited set of built-in tools.

If a subagent fails or returns nothing useful, say so and do that step
yourself.

### Research

Read the repo's `CLAUDE.md` first. If the repo uses git worktrees or Git Town,
check where this branch sits:

```bash
git config --get-regexp '^git-town-branch\.'
git town diff-parent      # if the parent isn't the main branch
```

A branch with a non-main parent builds on unmerged work — include that diff in
the research prompt. See the `git-town-worktree` skill.

Launch `researcher` with focus "feature research", in the same message as any
other research a calling skill adds.

### Cleanup scan, then questions

Launch `researcher` with focus "adjacent cleanup" and the "Files involved" list
from research.

Then ask the user any questions that would change the plan, all at once. Worth
asking about: ambiguous acceptance criteria, two equally plausible places to
make the change, an implied schema or API change, scope that looks like more
than one reviewable PR, or a task that seems to ask for the wrong thing. If
nothing is ambiguous, don't ask.

### Plan

Write the plan yourself, from the reports. Include:

- The approach, and why it beats the main alternative.
- The branches in order, if the work splits into pieces that are each safe to
  ship on their own.
- For each branch: the files to change, and new or changed functions,
  endpoints, and types by exact name and signature. The tester writes tests
  against these names before the code exists.
- Each edge case from research and how it's handled.
- Cleanups: `fix now` ones go into the relevant branch; `ticket` ones go in a
  "Proposed tickets" list, not done now (see "Surrounding code" in
  `design-principles.md`).
- Which test covers each acceptance criterion.

### Plan review

Launch `reviewer` in plan review mode with the task, the research reports, and
the plan.

For each critical and medium item, either change the plan or reject the item
with a one-line reason. Apply low items only if cheap. Send the revision and
what you did with each item to the **same** reviewer with `SendMessage`, so it
checks its own feedback instead of starting over.

Stop when the verdict is `ready`, or after 3 rounds. If critical or medium
items are still open after 3, show them to the user and ask how to proceed.
Ask the user any `question` items that would change the plan before building.
Otherwise show the user the final plan and the rejected items with their
reasons, then build without waiting for approval.

### Build, one branch at a time

For each branch in the plan:

This is test-driven development, one branch at a time: failing tests, then
the code that passes them, then cleanup with the tests still passing.

1. **Red.** Launch `tester` in write mode with that branch's part of the plan
   and the acceptance criteria. It writes the tests and runs them to confirm
   they fail because the behavior is missing. Writing them before the code
   means they test what the task asks for, not what the code happens to do.
2. **Green.** Write the simplest code that makes them pass, following "While
   building" below. If you find a better structure than the plan's, take it,
   and keep a list of where the code differs from the plan: renames, moved
   files, changed signatures, split modules, and any change in behavior with
   the reason.
3. Send `tester` run mode with `SendMessage`, including that list. It updates
   the tests for structural differences, then runs them and the typecheck. If
   it says the code is wrong, fix it. If it says a test is wrong, check against
   the task before agreeing. Repeat until both pass.
4. **Refactor.** With the tests passing, clean up your code and the `fix now`
   items in the surrounding code against `design-principles.md`. Have `tester`
   rerun after.
5. Send the same `reviewer` code review mode with `SendMessage`: the branch,
   its parent branch, and the list of differences from the plan. Handle its
   feedback the way you did in plan review, at most 3 rounds. Rerun the tester
   after any fix.
6. Commit, then start the next branch.

### Finish

Show the user the "Proposed tickets" list collected from research, review, and
building, each with a title, short description, and `path:line` locations.
Create them only if the user says yes.

### While building

- Match the surrounding style. Reuse existing helpers rather than adding
  abstractions.
- Comments: default to none. Write one only where the code cannot explain
  itself — a constraint, a workaround, a reason the order matters. Never restate
  the line below it, and never add section-header banners. Before finishing,
  re-read your diff and delete every comment that only says what the code says.
  If you edited code a comment describes, update that comment in the same edit.
- Commit as you go, referencing the ticket or issue id.

The kickoff prompt may carry extra context the user typed when starting the
session (`ready "check the form ordering logic"`). Treat that as their steer on
where to look, and weight it above your own first guess.

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
