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

# ---------- dev workspace ----------

# Print the dev-server commands for a repo, one per line.
# Non-glob workspace entries are treated as apps; globbed ones are libraries
# unless they define a "dev" script (packages/* often has stray "start" scripts).
_dev_commands() {
  python3 - "$1" <<'PY'
import json, os, sys, glob

root = sys.argv[1]
pkg = os.path.join(root, "package.json")
if not os.path.isfile(pkg):
    sys.exit(0)

try:
    data = json.load(open(pkg))
except Exception:
    sys.exit(0)

scripts = data.get("scripts") or {}
if "dev" in scripts:
    print("yarn dev")
    sys.exit(0)

workspaces = [w for w in (data.get("workspaces") or []) if isinstance(w, str)]

def ws_script(d, wanted):
    p = os.path.join(d, "package.json")
    if not os.path.isfile(p):
        return None, None
    try:
        w = json.load(open(p))
    except Exception:
        return None, None
    s = w.get("scripts") or {}
    for c in wanted:
        if c in s:
            return w.get("name"), c
    return None, None

out = []
for entry in workspaces:
    if "*" in entry:
        continue
    name, script = ws_script(os.path.join(root, entry), ("dev", "start"))
    if name:
        out.append(f"yarn workspace {name} {script}")

if not out:
    for entry in workspaces:
        if "*" not in entry:
            continue
        for d in sorted(glob.glob(os.path.join(root, entry))):
            name, script = ws_script(d, ("dev",))
            if name:
                out.append(f"yarn workspace {name} {script}")

if out:
    print("\n".join(out))
elif "start" in scripts:
    print("yarn start")
PY
}

# Open a new kitty OS window laid out for working on the repo in $1 (default $PWD):
# Claude on the left half, git + one window per dev server stacked on the right.
# Dev-server commands are typed into their windows but not run.
# Usage: devwin [dir] [claude-prompt]
devwin() {
  local dir="${1:-$PWD}"
  local prompt="$2"

  dir=$(cd "$dir" 2>/dev/null && pwd) || { echo "devwin: no such directory: $1" >&2; return 1; }

  local kitty_bin
  kitty_bin=$(command -v kitty || echo /Applications/kitty.app/Contents/MacOS/kitty)
  [[ -x "$kitty_bin" ]] || { echo "devwin: kitty not found" >&2; return 1; }

  local session_dir="${HOME}/.local/state/devwin"
  mkdir -p "$session_dir"
  local session_file="${session_dir}/${dir:t}.kitty-session"

  {
    echo "layout splits"
    echo "cd ${dir}"
    if [[ -n "$prompt" ]]; then
      # Quotes in the prompt would end the argument early in the session file.
      echo "launch --var window=focus --title claude claude \"${prompt//\"/\\\"}\""
    else
      echo "launch --var window=focus --title claude claude"
    fi
    echo "launch --location=vsplit --title git"

    local cmd title
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      # "yarn workspace api start" -> api ; "yarn dev" -> dev
      if [[ "$cmd" == "yarn workspace "* ]]; then
        title="${${cmd#yarn workspace }%% *}"
      else
        title="${cmd##* }"
      fi
      echo "launch --location=hsplit --title \"${title}\" --env DEV_PREFILL=\"${cmd}\""
    done < <(_dev_commands "$dir")

    echo "focus_matching_window var:window=focus"
  } > "$session_file"

  "$kitty_bin" --single-instance --session "$session_file" >/dev/null 2>&1 &
  disown 2>/dev/null
  echo "==> kitty window for ${dir:t} (session: ${session_file})"
}



# yabai query that retries when the JSON comes back truncated, which it can
# do while windows are being created rapidly.
_yq() {
  local out try
  for try in 1 2 3; do
    out=$(yabai -m query "$@" 2>/dev/null)
    if print -r -- "$out" | python3 -c "import json,sys; json.load(sys.stdin)" >/dev/null 2>&1; then
      print -r -- "$out"
      return 0
    fi
    sleep 0.25
  done
  echo "[]"
}

_yabai_all_ids() {
  _yq --windows | python3 -c "
import json, sys
print(' '.join(str(w['id']) for w in json.load(sys.stdin)))
"
}

# Title match ($3) wins, else a window absent from the $2 snapshot, else newest.
# The title check exists because VS Code refocuses a folder it already shows
# rather than opening a window, so there is nothing "new" to find.
_yabai_new_win() {
  _yq --windows | python3 -c "
import json, sys
app, before = sys.argv[1], set(sys.argv[2].split())
want = sys.argv[3] if len(sys.argv) > 3 else ''
strict = len(sys.argv) > 4 and sys.argv[4] == 'strict'
ws = [w for w in json.load(sys.stdin) if w.get('app') == app]
if want:
    titled = [str(w['id']) for w in ws if want in (w.get('title') or '')]
    if titled:
        print(titled[-1]); raise SystemExit
ids = [str(w['id']) for w in ws]
fresh = [i for i in ids if i not in before]
print((fresh[-1] if fresh else ('' if strict else (ids[-1] if ids else ''))))
" "$1" "$2" "$3" "$4"
}

# Open VS Code, a browser and the kitty layout for a project, then stack them
# full-size on one space.
#
#   workspace --dir D [--name N] [--prompt P] [--url U]...
workspace() {
  local dir prompt name
  local -a urls
  while (( $# )); do
    case "$1" in
      --dir)    dir="$2";      shift 2 ;;
      --prompt) prompt="$2";   shift 2 ;;
      --url)    urls+=("$2");  shift 2 ;;
      --name)   name="$2";     shift 2 ;;
      *) echo "workspace: unknown option '$1'" >&2; return 1 ;;
    esac
  done

  dir=$(cd "${dir:-$PWD}" 2>/dev/null && pwd) || { echo "workspace: no such directory" >&2; return 1; }

  local before
  before=$(_yabai_all_ids)

  code "$dir"

  if (( ${#urls} )); then
    open -na "Google Chrome" --args --new-window "${urls[@]}"
  fi

  devwin "$dir" "$prompt"

  # strict: never fall back to an existing window while still polling, or the
  # first pass grabs an unrelated one.
  local tries=0 vscode kitty chrome
  local want_chrome=0
  (( ${#urls} )) && want_chrome=1

  while (( tries < 40 )); do
    vscode=$(_yabai_new_win "Code" "$before" "${dir:t}" strict)
    kitty=$(_yabai_new_win "kitty" "$before" "" strict)
    chrome=$(_yabai_new_win "Google Chrome" "$before" "" strict)
    if [[ -n "$vscode" && -n "$kitty" ]] &&
       { (( ! want_chrome )) || [[ -n "$chrome" ]]; }; then
      break
    fi
    sleep 0.5
    (( tries++ ))
  done

  if (( tries >= 40 )); then
    echo "workspace: gave up waiting for:${vscode:- VSCode}${kitty:- kitty}${chrome:- Chrome}" >&2
  fi

  _workspace_arrange "$vscode" "$kitty" "$chrome"
  _ws_save "${name:-${dir:t}}" "$vscode" "$kitty" "$chrome" "$_WS_SPACE"
}

_win_prop() {
  _yq --windows | python3 -c "
import json, sys
wid, key = int(sys.argv[1]), sys.argv[2]
print(next((str(w.get(key)) for w in json.load(sys.stdin) if w['id'] == wid), ''))
" "$1" "$2"
}

# First space on the main display with nothing on it. Spaces cannot be created
# without the scripting addition, so keep a few spares made by hand.
_ws_empty_space() {
  _yq --spaces | python3 -c "
import json, sys
for s in json.load(sys.stdin):
    if s['display'] == 1 and not s.get('windows'):
        print(s['index']); break
"
}

# Only *creating* a space needs the scripting addition; moving windows into an
# existing one does not. --grid 1:1:0:0:1:1 fills the usable area, with yabai
# working out the menu bar, Dock and padding.
_workspace_arrange() {
  local vscode="$1" space="$4" id
  _WS_SPACE=""
  [[ -z "$vscode" ]] && { echo "workspace: no VS Code window to arrange" >&2; return 1; }

  if [[ -z "$space" ]]; then
    space=$(_ws_empty_space)
    if [[ -z "$space" ]]; then
      space=$(_yq --spaces --space | python3 -c "import json,sys; print(json.load(sys.stdin)['index'])")
      echo "workspace: no empty space free; using space ${space}." >&2
      echo "           Add spares in Mission Control to keep tickets apart." >&2
    fi
  fi

  yabai -m space "$space" --layout float >/dev/null 2>&1

  for id in "$3" "$2" "$vscode"; do
    [[ -z "$id" ]] && continue
    # A native-fullscreen window owns its own space and will not move.
    if [[ "$(_win_prop "$id" is-native-fullscreen)" == "True" ]]; then
      yabai -m window "$id" --toggle native-fullscreen >/dev/null 2>&1
      sleep 1.2
    fi
    yabai -m window "$id" --space "$space" >/dev/null 2>&1
    sleep 0.3
    yabai -m window "$id" --grid 1:1:0:0:1:1 >/dev/null 2>&1
    yabai -m window "$id" --focus >/dev/null 2>&1
    sleep 0.2
  done

  # Focusing a space restores whichever window that space had focused last, so
  # put VS Code back in front afterwards.
  yabai -m space --focus "$space" >/dev/null 2>&1
  sleep 0.3
  yabai -m window "$vscode" --focus >/dev/null 2>&1
  _WS_SPACE="$space"
}

workspace_tile() {
  command -v yabai >/dev/null 2>&1 || return 0
  _yq --spaces >/dev/null 2>&1 || {
    echo "workspace: yabai is not running (yabai --start-service)" >&2
    return 1
  }
  local cur
  cur=$(_yq --spaces --space | python3 -c "import json,sys; print(json.load(sys.stdin)['index'])")
  _workspace_arrange "$(_yabai_new_win Code '' '')" "$(_yabai_new_win kitty '' '')" \
                     "$(_yabai_new_win 'Google Chrome' '' '')" "$cur"
}



_ws_dir() { echo "${HOME}/.local/state/workspace"; }

# Line 1: the three window ids ("-" for absent). Line 2: the space it claimed.
_ws_save() {
  local d; d=$(_ws_dir); mkdir -p "$d"
  {
    print -r -- "${2:--} ${3:--} ${4:--}"
    print -r -- "${5:--}"
  } > "${d}/${1}.ids"
}

_ws_alive() {
  [[ "$1" == <-> ]] || return 0
  _yq --windows | python3 -c "
import json, sys
wid = int(sys.argv[1])
print(sys.argv[1] if any(w['id'] == wid for w in json.load(sys.stdin)) else '')
" "$1"
}

#   ws            list saved workspaces
#   ws NAME       go to NAME's space
#   ws --forget NAME
ws() {
  local d; d=$(_ws_dir)

  if [[ "$1" == "--forget" ]]; then
    [[ -z "$2" ]] && { echo "ws: --forget needs a name" >&2; return 1; }
    rm -f "${d}/${2}.ids" && echo "forgot ${2}"
    return 0
  fi

  local f name id
  if [[ -z "$1" ]]; then
    local -a files=("${d}"/*.ids(N))
    (( ${#files} )) || { echo "no saved workspaces"; return 0; }
    for f in "${files[@]}"; do
      name="${${f:t}%.ids}"
      local -a fl=("${(@f)$(<$f)}")
      local -a ids=(${(z)fl[1]}) live=()
      local sp="${fl[2]:-?}"
      for id in "${ids[@]}"; do
        [[ -n "$(_ws_alive "$id")" ]] && live+=("$id")
      done
      printf "  %-28s space %-4s %d/3 windows\n" "$name" "$sp" "${#live}"
    done
    return 0
  fi

  f="${d}/${1}.ids"
  [[ -f "$f" ]] || { echo "ws: no saved workspace '$1'" >&2; return 1; }

  local -a lines=("${(@f)$(<$f)}")
  local -a raw=(${(z)lines[1]}) ids=()
  local space="${lines[2]:-}"
  for id in "${raw[@]}"; do
    ids+=("$(_ws_alive "$id")")
  done

  [[ "$space" == <-> ]] && yabai -m space --focus "$space" >/dev/null 2>&1
  sleep 0.3

  for id in "${ids[3]}" "${ids[2]}" "${ids[1]}"; do
    [[ -n "$id" ]] && yabai -m window "$id" --focus >/dev/null 2>&1 && sleep 0.15
  done
}
