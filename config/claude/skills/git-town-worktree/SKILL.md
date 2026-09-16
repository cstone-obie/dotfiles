---
name: git-town-worktree
description: Branch, stack, sync, and ship using Git Town together with git worktrees. Use whenever creating a branch, stacking branches, running git town sync/hack/append/prepend/propose, opening a PR, working inside a worktree, or diagnosing why a sync did not pick up the main branch's changes.
allowed-tools: Bash(git *), Read, Grep, Glob
---

# Git Town + worktrees

Git Town automates branch creation, syncing, and PRs. Worktrees let several
branches be checked out at once in sibling directories. They combine well, but
there are four rules that must hold or things break quietly.

Read the repo's actual settings before acting — never assume:

```bash
git config --get-regexp '^git-town'     # main branch name, sync strategy, etc.
git worktree list                       # what is checked out where
```

`git-town.sync-feature-strategy` matters most: `merge` merges the parent into
the child, `rebase` replays the child's commits on top. The rest of this skill
writes the main branch as `<main>` — read the real name from
`git-town.main-branch` (usually `main` or `master`).

## Rule 0: never push to `<main>`

`<main>` is what ships. Never push to it, never commit on it. Work lands through
a PR opened with `git town propose` and merged by the user.

- Never `git push origin <main>`, `git push origin HEAD:<main>`, or force-push.
- Before any push, check the branch and its upstream:
  ```bash
  git branch --show-current                                       # not <main>, not HEAD
  git config --get "branch.$(git branch --show-current).merge"    # not refs/heads/<main>
  ```
- Prefer letting `git town sync` push — it pushes the current branch to its own
  remote branch and never to `<main>`.
- Merging a PR is the user's decision. Don't merge, and don't run `git town ship`.
- **Open PRs with `git town propose`, never the GitHub CLI.** No `gh pr create`,
  no `gh` anything. Git Town talks to GitHub through its own API connector
  (`git-town.github-connector = api`), so the CLI is not needed and is not
  installed.

`gh` is especially unsafe here: it is aliased to `git town hack`. In an
interactive shell `gh pr create` expands to `git town hack pr create`, which
**creates a branch** instead of opening a PR — a wrong action that succeeds,
not an error you would notice. In a non-interactive shell the alias does not
exist and there is no binary, so it just fails.

## Rule 1: `<main>` must not be checked out in any worktree

Git refuses to update a branch that is checked out somewhere else:

```
fatal: refusing to fetch into branch 'refs/heads/main' checked out at '...'
```

Git Town does not report this as an error. It silently skips updating `<main>`
and merges a stale copy into the feature branch:

```
<main> free (detached)            <main> checked out in another worktree
──────────────────────            ─────────────────────────────────────
git fetch --prune --tags          git fetch --prune --tags
git checkout <main>               (nothing)
git merge --ff-only origin/<main> (nothing)   ← silently skipped
git checkout <feature>            (nothing)
git merge --no-edit --ff <main>   git merge --no-edit --ff <main>   ← merges STALE <main>
git push                          git push
```

The sync reports success while the branch never receives the new commits. So if
a sync looks like it did nothing, or a branch is missing a commit that is
definitely on `origin/<main>`, check this first:

```bash
git worktree list                     # is any worktree on [<main>]?
git rev-parse <main> origin/<main>    # do they differ?
```

Free it by detaching HEAD in whichever worktree holds it:

```bash
git -C <that-worktree> checkout --detach <main>
```

Detaching means "checked out at this commit, but not on any branch." The files
are identical; the branch is simply unowned, so other worktrees can update it.
Prefer this over parking on a placeholder branch — no extra branch, no Git Town
lineage entry, nothing that can be pushed by accident. The one caveat: a commit
made while detached belongs to no branch and is easy to lose, so don't commit
there.

## Rule 2: every branch needs explicit lineage

Git Town stores the stack in git config, not in the commit history:

```bash
git config git-town-branch.<branch>.parent      <main>
git config git-town-branch.<branch>.branchtype  feature
```

`git town hack` / `append` / `prepend` set this. A branch made with plain
`git checkout -b` or `git worktree add` does not have it, and `git town sync`
then prompts for a parent — which hangs a non-interactive session. Check first:

```bash
git config --get-regexp '^git-town-branch\.' | grep "$(git branch --show-current)"
```

If it's missing, set it with the two commands above rather than letting sync ask.

## Rule 3: never create a worktree branch that tracks `origin/<main>`

```bash
git worktree add -b feat <dir> origin/<main>
# -> "branch 'feat' set up to track 'origin/main'"
```

That upstream turns a bare `git push` in the worktree into a push to `<main>`.
Always pass `--no-track`; Git Town sets the correct upstream on the first sync:

```bash
git worktree add --no-track -b <branch> <dir> origin/<main>
git -C <dir> config git-town-branch.<branch>.parent <main>
git -C <dir> config git-town-branch.<branch>.branchtype feature
```

Branching from `origin/<main>` rather than local `<main>` is deliberate:
`git fetch` can always update `origin/<main>` (no worktree can own a
remote-tracking ref), so it works even when `<main>` is checked out, and the new
branch starts from current code instead of whenever local `<main>` last moved.

## Stacking

A stack is a chain of branches, each based on the one below:
`<main> -> a -> b -> c`.

```bash
git town hack    <name>   # <main> -> new
git town append  <name>   # current -> new   (child, extends the stack)
git town prepend <name>   # parent -> new -> current  (inserts above current)
```

`git town sync` from anywhere in the stack works bottom-up, merging each parent
into its child and pushing each one.

### Merge order: always bottom-up

**The branch closest to `<main>` merges first, then the next one up.** Two
reasons.

**Deploys must stay safe.** Each merge to `<main>` can reach production on its
own, so the stack has to be ordered so that shipping any one branch leaves
things working. In practice:

- **Lower branches stay backward compatible.** A change that merges ahead of the
  code using it must keep working with what's already deployed — add new fields,
  endpoints, or columns beside the old ones; don't remove or rename anything the
  shipped code still depends on.
- **New behavior ships behind a feature flag**, turned off, so merging changes
  nothing until the flag is flipped — and can be turned back off if it misbehaves.

When proposing a split, order it so this holds and say why each branch is safe
to ship alone. If it can't be split that way, keep it as one branch.

**Git Town reparents children automatically.** When the bottom branch merges and
its remote branch is deleted, the next sync deletes the local branch and moves
its children up. Verified for `<main> -> backend -> fe1 -> fe2` after `backend`
was squash-merged:

```
- [deleted]  (none) -> origin/backend
deleted branch backend

git-town-branch.fe1.parent = <main>   ← moved up automatically
git-town-branch.fe2.parent = fe1      ← rest of the chain untouched
```

Merging out of order would move branches underneath a change that already
shipped, which is the same thing that makes the deploy unsafe.

### Splitting a change into branches

One focused change per PR. Size follows the change — there is no target number
of files or lines — but these three always go in separate branches:

- **Migrations.** The schema change ships and runs before any code reads or
  writes the new shape.
- **Backend.** Merges before the frontend calling it, and keeps working for the
  frontend already deployed.
- **Frontend.** Merges last, once what it calls is live.

Stacked in that order: `<main> -> migration -> backend -> frontend`.

The reason is that the frontend and the backend deploy as separate units, and
not necessarily at the same moment. One PR touching both can have its two halves
go out minutes apart, in either order — leaving a window where the frontend is
calling an endpoint that has not shipped, or the backend is running against a
column the migration has not created. Split apart, each merge is complete on its
own and there is no window.

So a ticket that needs a migration, an API change, and a UI change is three
branches, not one. If a change genuinely cannot be split this way, say why
rather than opening a mixed PR.

### Phantom conflicts after a parent merges

A squash-merge collapses a PR into one new commit on `<main>`. The originals
still exist on the branches above, so a child ends up holding both copies:

```
*   Merge branch 'main' into fe1
|\
| * backend change (squashed)   ← copy that arrived via <main>
* | frontend 1
* | backend change              ← original, still on fe1
|/
* base
```

Same content, two commits. Sync can report a conflict where both sides are
identical. Git Town's `--auto-resolve` handles these and is on by default; if
one slips through, take either side. A conflict right after a parent merged is
almost always this, not a real disagreement.

### Opening PRs

`git town propose` from each branch, bottom-up, so each PR's base already
exists. Keep each small enough to review alone. Opening PRs when asked is fine;
merging is the user's call.

`git town propose` is the only way to open a PR here — see Rule 0 for why the
GitHub CLI is both unnecessary and actively unsafe.

## Cleaning up a finished worktree

**Never remove the worktree you are working in.** Check before touching anything:

```bash
git rev-parse --show-toplevel     # if this is the worktree to delete, stop here
```

Removing it deletes the directory the session is running in. Every command after
that fails with `cd: no such file or directory`, and an editor left open on those
files is pointing at paths that no longer exist. Say so and let the user run the
cleanup from the main checkout or another session.

Otherwise, only after the PR is merged and the remote branch is gone:

```bash
git worktree list
git -C <main-checkout> worktree remove <worktree-dir>
git -C <main-checkout> branch -D <branch>
git -C <main-checkout> fetch --prune origin <main>
git -C <main-checkout> worktree list     # confirm <main> is still unowned
```

`branch -D` (capital D) is needed because a squash-merged branch still looks
unmerged — its original commits never appear on `<main>`. The branch being gone
from the remote is what proves it shipped, so check that before deleting.

Afterward, make sure no worktree ended up back on `[<main>]`. If one did, detach
it, or every other worktree's sync starts silently skipping `<main>` again.

## Recovering

`git town undo` reverses the last Git Town command. A sync stopped by a conflict
resumes with `git town continue` after `git add`, or backs out with
`git town undo`.
