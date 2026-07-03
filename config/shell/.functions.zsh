_fzf_custom() {
  fzf \
    --style full \
    --input-label " Input " \
    --preview "bat \
      --theme=Dracula \
      --style=default,-header-filename,-grid,+numbers \
      --color=always \
      {}" \
    --bind "result:transform-list-label:
        if [[ -z $FZF_QUERY ]]; then
          echo \" $FZF_MATCH_COUNT items \"
        else
          echo \" $FZF_MATCH_COUNT matches for [$FZF_QUERY] \"
        fi
        " \
    --bind "focus:+transform-header:file --brief {} || \
        echo \"No file selected\"" \
    --color "preview-border:cyan,preview-label:cyan" \
    --color "list-border:green,list-label:green" \
    --color "input-border:magenta,input-label:magenta" \
    --color "header-border:blue,header-label:blue"
}

op() {
  local file
  file=$(_fzf_custom) && [[ -n "$file" ]] && "$EDITOR" "$file"
}

opq() {
  local file
  file=$(_fzf_custom) && [[ -n "$file" ]] && nano "$file"
}

show() {
  local file
  file=$(_fzf_custom) && [[ -n "$file" ]] && bat "$file"
}




# WIP


# gw() {
#   if [[ "$1" == "cleanup" ]]; then
#     shift
#     _gw_cleanup "$@"
#     return $?
#   fi

#   local input="$1"
#   local prefix="cs"
#   local branch="${prefix}/${input}"

#   local current_dir=$(pwd)

#   local dir_prefix=""
#   if [[ "$current_dir" == *"/risk-management"* ]]; then
#       dir_prefix="rm_"
#       cd ~/projects/risk-management
#   elif [[ "$current_dir" == *"/surefin"* ]]; then
#       dir_prefix="sf_"
#       cd ~/projects/surefin
#   else
#     echo "Error: Not in a code directory"
#     return 1
#   fi

#   local directory="../${dir_prefix}${input//\//_}"

#   git checkout main

#   git worktree add -b "$branch" "$directory"

#   code "$directory"

#   cd "$directory"
# }

# # Tear down a worktree created by `gw`, e.g. `gw cleanup foo_bar`.
# _gw_cleanup() {
#   local name="$1"

#   if [[ -z "$name" ]]; then
#     echo "Usage: gw cleanup <worktree>" >&2
#     return 1
#   fi

#   local worktree_dir="${HOME}/projects/${name}"
#   if [[ ! -d "$worktree_dir" ]]; then
#     echo "Error: worktree directory not found: $worktree_dir" >&2
#     return 1
#   fi

#   # Resolve the branch + owning repo before sync, since sync may delete them.
#   # Capture the push state now too: a successful sync deletes a shipped branch
#   # together with its tracking config, so reading it afterward would look "unpushed".
#   local branch common_git_dir main_repo remote
#   branch=$(git -C "$worktree_dir" rev-parse --abbrev-ref HEAD) || return 1
#   common_git_dir=$(git -C "$worktree_dir" rev-parse --path-format=absolute --git-common-dir) || return 1
#   main_repo="${common_git_dir:h}"
#   remote=$(git -C "$worktree_dir" config "branch.${branch}.remote")

#   if [[ "$branch" == "main" || "$branch" == "HEAD" ]]; then
#     echo "Error: '$name' is on '$branch'; refusing to clean up." >&2
#     return 1
#   fi

#   # 1 + 2. Sync (git town sync). Abort if it can't sync (conflicts, dirty tree, etc.).
#   echo "==> git town sync ($branch)"
#   if [[ -d "$worktree_dir" ]] && ! git -C "$worktree_dir" town sync; then
#     echo "Error: 'git town sync' failed; aborting cleanup." >&2
#     return 1
#   fi

#   # Safety gate. If 'git town sync' already deleted the local branch, that is the
#   # strongest possible signal the PR shipped -- proceed. If the branch still exists,
#   # it wasn't auto-deleted, so confirm it shipped (was pushed AND its remote branch
#   # is now gone, the signature of a squash-merged PR) before removing anything.
#   if git -C "$main_repo" show-ref --verify --quiet "refs/heads/${branch}"; then
#     if [[ -z "$remote" ]]; then
#       echo "Error: '$branch' was never pushed; can't confirm it shipped. Aborting." >&2
#       return 1
#     fi
#     if git -C "$main_repo" ls-remote --exit-code --heads "$remote" "$branch" >/dev/null 2>&1; then
#       echo "Error: '$branch' still exists on '$remote'; it doesn't look merged. Aborting." >&2
#       return 1
#     fi
#   fi

#   # 3. Remove the worktree (refuses if there are uncommitted/untracked changes).
#   if [[ -d "$worktree_dir" ]]; then
#     echo "==> git worktree remove $worktree_dir"
#     git -C "$main_repo" worktree remove "$worktree_dir" || return 1
#   fi

#   # 4. Delete the local branch. Force (-D) because a squash-merged branch reads as
#   #    unmerged to git; the remote-gone gate above is what proves it's safe.
#   if git -C "$main_repo" show-ref --verify --quiet "refs/heads/${branch}"; then
#     echo "==> git branch -D $branch"
#     git -C "$main_repo" branch -D "$branch" || return 1
#   fi

#   # 5. Drop back into the main repo on main (git town switch).
#   cd "$main_repo" || return 1
#   git town switch main
# }

# # Completion: `gw <TAB>` -> cleanup; `gw cleanup <TAB>` -> available worktrees.
# _gw() {
#   if (( CURRENT == 2 )); then
#     compadd cleanup
#     return
#   fi
#   if (( CURRENT == 3 )) && [[ "${words[2]}" == cleanup ]]; then
#     local -a names
#     local repo line base
#     for repo in ~/projects/risk-management ~/projects/surefin; do
#       [[ -d "$repo" ]] || continue
#       for line in ${(f)"$(git -C "$repo" worktree list --porcelain 2>/dev/null)"}; do
#         [[ "$line" == "worktree "* ]] || continue
#         base=${line#worktree }
#         base=${base:t}
#         [[ "$base" == risk-management || "$base" == surefin ]] && continue
#         names+=$base
#       done
#     done
#     compadd -a names
#   fi
# }
# compdef _gw gw

