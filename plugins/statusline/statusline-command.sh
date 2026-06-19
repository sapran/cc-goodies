#!/bin/bash
# Claude Code status line (optimized) — p10k-lean inspired
# L1: user@host  cwd  [branch|wt]  "task" → "latest"   L2: model (effort)  c% s% w%
# Speed: ONE jq parse (was ~9) · transcript reads bounded head/tail (was full-file
# grep+tac every render) · git branch cached 5s · latest cached 3s · pure-bash lstrip.

input=$(cat)
export LC_NUMERIC=C   # locale-proof printf '%.0f' on fractional percentages (uk_UA uses ',')
# Per-user, mode-700 cache dir. macOS $TMPDIR is already private, but on a shared
# host with $TMPDIR unset the bare /tmp is world-readable: cache files hold prompt
# snippets and the `>` writes follow symlinks, so a predictable /tmp path leaks
# those snippets and invites a symlink-clobber. Keep the cache in a dir only we
# own; if the path is hijacked (symlink / not a dir / not ours), use a throwaway.
cache_dir="${TMPDIR:-/tmp}/claude-statusline-$(id -u)"
{ mkdir -p "$cache_dir" && chmod 700 "$cache_dir"; } 2>/dev/null
{ [ -d "$cache_dir" ] && [ ! -L "$cache_dir" ] && [ -O "$cache_dir" ]; } || cache_dir=$(mktemp -d)

# single jq parse → one field per line. Empty-safe: a per-line `read` preserves empty
# fields, whereas `IFS=$'\t' read` would collapse adjacent tabs and shift every field.
{ IFS= read -r cwd; IFS= read -r model; IFS= read -r used; IFS= read -r rl_5h
  IFS= read -r rl_7d; IFS= read -r worktree_name; IFS= read -r transcript; IFS= read -r effort
} < <(printf '%s' "$input" | jq -r '
  (.cwd // .workspace.current_dir // ""),
  (.model.display_name // "" | sub(" context\\)"; ")")),
  (.context_window.used_percentage // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.seven_day.used_percentage // ""),
  (.worktree.name // ""),
  (.transcript_path // ""),
  (.effort.level // "")')

if [ -z "$effort" ] && [ -f "$HOME/.claude/settings.json" ]; then
  effort=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
fi
[ -z "$effort" ] && effort="auto"

rl_5h_int=$(printf '%.0f' "${rl_5h:-0}" 2>/dev/null)
rl_7d_int=$(printf '%.0f' "${rl_7d:-0}" 2>/dev/null)
rl_cache="$cache_dir/claude-ratelimits.cache"
if [ "${rl_5h_int:-0}" -gt 0 ] 2>/dev/null || [ "${rl_7d_int:-0}" -gt 0 ] 2>/dev/null; then
  printf '%s %s' "$rl_5h_int" "$rl_7d_int" > "$rl_cache"
elif [ -f "$rl_cache" ]; then
  read -r cached_5h cached_7d < "$rl_cache"; rl_5h_int="${cached_5h:-0}"; rl_7d_int="${cached_7d:-0}"
fi

user=$(whoami); host=$(hostname -s)

short_cwd="${cwd/#$HOME/~}"
if [ "${#short_cwd}" -gt 30 ]; then
  last_dir=$(basename "$short_cwd"); parent=$(dirname "$short_cwd")
  oldIFS="$IFS"; IFS='/'; set -f
  # shellcheck disable=SC2086  # deliberate word-split on '/'; set -f above disables globbing
  set -- $parent
  set +f; IFS="$oldIFS"; compressed=""; first=1
  for seg; do
    if [ "$first" -eq 1 ]; then compressed="$seg"; first=0
    else compressed="$compressed/$(printf '%.1s' "$seg")"; fi
  done
  short_cwd="$compressed/$last_dir"
fi

branch=""
if [ -n "$cwd" ]; then
  key=$(printf '%s' "$cwd" | { md5 -q 2>/dev/null || md5sum | cut -d' ' -f1; })
  bcache="$cache_dir/claude-branch-$key"; bmtime=$(stat -f %m "$bcache" 2>/dev/null || echo 0)
  if [ -f "$bcache" ] && [ $(( $(date +%s) - bmtime )) -lt 5 ]; then
    branch=$(cat "$bcache")
  else
    git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
      branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
    printf '%s' "$branch" > "$bcache"
  fi
fi

short_worktree=""
if [ -n "$worktree_name" ]; then
  if [ "${#worktree_name}" -gt 20 ]; then
    short_worktree=$(printf '%s' "$worktree_name" | sed 's/\([^-]\)[^-]*/\1/g')
  else short_worktree="$worktree_name"; fi
fi

first_real() {
  jq -r 'select(.type=="user") |
    if (.message.content|type)=="string" then .message.content
    elif (.message.content|type)=="array" then ([.message.content[]|select(.type=="text")|.text]|join(""))
    else "" end' 2>/dev/null | while IFS= read -r line; do
      stripped="${line#"${line%%[![:space:]]*}"}"
      case "$stripped" in ''|'<'*|'/'*) continue ;; *) printf '%s' "$stripped"; break ;; esac
    done
}

task=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  key=$(printf '%s' "$transcript" | { md5 -q 2>/dev/null || md5sum | cut -d' ' -f1; })
  tcache="$cache_dir/claude-task-$key.txt"
  if [ -f "$tcache" ]; then task=$(cat "$tcache")
  else
    raw=$(head -n 500 "$transcript" 2>/dev/null | grep '"type":"user"' | first_real)
    if [ -n "$raw" ]; then
      task=$(printf '%s' "$raw" | cut -c1-40); [ "${#raw}" -gt 40 ] && task="${task}…"
      printf '%s' "$task" > "$tcache"
    fi
  fi
fi

latest=""
if [ -n "$transcript" ] && [ -f "$transcript" ] && [ -n "$task" ]; then
  key=$(printf '%s' "$transcript" | { md5 -q 2>/dev/null || md5sum | cut -d' ' -f1; })
  lcache="$cache_dir/claude-latest-$key.txt"; lmtime=$(stat -f %m "$lcache" 2>/dev/null || echo 0)
  if [ -f "$lcache" ] && [ $(( $(date +%s) - lmtime )) -lt 3 ]; then
    latest=$(cat "$lcache")
  else
    raw=$(tail -n 500 "$transcript" 2>/dev/null | tail -r | grep '"type":"user"' | first_real)
    if [ -n "$raw" ]; then
      latest=$(printf '%s' "$raw" | cut -c1-40); [ "${#raw}" -gt 40 ] && latest="${latest}…"
    fi
    printf '%s' "$latest" > "$lcache"
  fi
  [ "$latest" = "$task" ] && latest=""
fi

printf "\033[32m%s@%s\033[0m  \033[34m%s\033[0m" "$user" "$host" "$short_cwd"
[ -n "$branch" ] && [ -z "$short_worktree" ] && printf "  \033[33m[%s]\033[0m" "$branch"
[ -n "$short_worktree" ] && printf "  \033[33mwt:%s\033[0m" "$short_worktree"
if [ -n "$task" ]; then
  if [ -n "$latest" ]; then printf "  \033[2;37m\"%s\" → \"%s\"\033[0m" "$task" "$latest"
  else printf "  \033[2;37m\"%s\"\033[0m" "$task"; fi
fi
printf "\n"
printf "\033[36m%s\033[0m" "$model"
[ -n "$effort" ] && printf " \033[2;36m(%s)\033[0m" "$effort"
[ -n "$used" ] && printf "  \033[35mc:%s%%\033[0m" "$(printf '%.0f' "$used")"
[ -n "$rl_5h" ] && [ "${rl_5h_int:-0}" -gt 0 ] 2>/dev/null && printf " \033[35ms:%s%%\033[0m" "$rl_5h_int"
[ -n "$rl_7d" ] && [ "${rl_7d_int:-0}" -gt 0 ] 2>/dev/null && printf " \033[35mw:%s%%\033[0m" "$rl_7d_int"
printf "\n"
