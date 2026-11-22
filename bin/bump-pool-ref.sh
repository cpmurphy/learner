#!/usr/bin/env bash
# Bump stockfish-pool pins and open a PR.
#
# Updates POOL_REF, the Gemfile stockfish_pool_client tag, Gemfile.lock
# (bundle install), and lib/chess_rules (bin/sync-chess-rules), then runs
# bin/check-pool-ref, commits, pushes, and creates a PR if needed.
#
#   bin/bump-pool-ref.sh [tag]
#
# Tag resolution: argv, else a dirty/edited POOL_REF that differs from the
# Gemfile pin, else a TTY prompt (non-interactive: exit 2 with usage).
#
# Re-running with the same tag recreates local branch bump-pool-ref from
# main and pushes with --force-with-lease (intended "rerun the bump" path).
# If pins and chess-rules already match the target on main, exits 0.
set -euo pipefail

branch=bump-pool-ref
pool_repo_url=${POOL_REPO_URL:-https://github.com/cpmurphy/stockfish-pool.git}

usage() {
  echo "usage: bin/bump-pool-ref.sh [tag]" >&2
  exit 2
}

cd "$(dirname "$0")/.."

gemfile_tag() {
  awk '
    /^[[:space:]]*gem[[:space:]]+["'\'']stockfish_pool_client["'\'']/ { in_gem = 1 }
    in_gem && match($0, /tag:[[:space:]]*["'\''][^"'\'']+["'\'']/) {
      s = substr($0, RSTART, RLENGTH); sub(/^tag:[[:space:]]*["'\'']/, "", s); sub(/["'\'']$/, "", s)
      print s; exit
    }
    in_gem && !/,[[:space:]]*$/ { exit }
  ' Gemfile
}

lock_tag() {
  awk '
    /^GIT$/ { in_git = 1; pool = 0; next }
    /^[^[:space:]]/ { in_git = 0 }
    in_git && /^  remote:.*stockfish-pool/ { pool = 1 }
    in_git && pool && /^  tag:/ { print $2; exit }
  ' Gemfile.lock
}

pool_ref_value() {
  tr -d '[:space:]' <POOL_REF
}

path_allowed_dirty() {
  case "$1" in
    POOL_REF|bin/bump-pool-ref.sh) return 0 ;;
    *) return 1 ;;
  esac
}

assert_clean_enough() {
  local line path
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    path=${line:3}
    path=${path#\"}
    path=${path%\"}
    case "$path" in
      *' -> '*) path=${path##* -> } ;;
    esac
    if ! path_allowed_dirty "$path"; then
      echo "working tree is dirty (only POOL_REF may be edited): $path" >&2
      exit 1
    fi
  done < <(git status --porcelain --untracked-files=normal)
}

set_gemfile_tag() {
  local tag=$1 tmp
  tmp=$(mktemp)
  awk -v tag="$tag" '
    /^[[:space:]]*gem[[:space:]]+["'\'']stockfish_pool_client["'\'']/ { in_gem = 1 }
    in_gem && /tag:[[:space:]]*["'\''][^"'\'']+["'\'']/ {
      sub(/tag:[[:space:]]*["'\''][^"'\'']+["'\'']/, "tag: '\''" tag "'\''")
      print
      in_gem = 0
      next
    }
    in_gem && !/,[[:space:]]*$/ { in_gem = 0 }
    { print }
  ' Gemfile >"$tmp"
  mv "$tmp" Gemfile
}

tag_exists_on_remote() {
  local tag=$1
  git ls-remote --exit-code --tags "$pool_repo_url" "refs/tags/${tag}" >/dev/null 2>&1
}

pins_agree_at() {
  local tag=$1
  [ "$(pool_ref_value)" = "$tag" ] || return 1
  [ "$(gemfile_tag)" = "$tag" ] || return 1
  [ "$(lock_tag)" = "$tag" ] || return 1
}

chess_rules_current() {
  bin/sync-chess-rules --check >/dev/null 2>&1
}

ensure_pr() {
  local tag=$1 url
  url=$(gh pr list --head "$branch" --base main --state open --json url --jq '.[0].url // empty')
  if [ -n "$url" ]; then
    printf '%s\n' "$url"
    return 0
  fi
  gh pr create --base main --head "$branch" \
    --title "chore: bump stockfish-pool to ${tag}" \
    --body "$(cat <<EOF
Bump stockfish-pool to \`${tag}\`.

- \`POOL_REF\`, Gemfile client tag, and Gemfile.lock
- \`lib/chess_rules\` synced via \`bin/sync-chess-rules\`
EOF
)"
}

# --- resolve tag -----------------------------------------------------------

[ "$#" -le 1 ] || usage

current_gemfile_tag=$(gemfile_tag)
: "${current_gemfile_tag:?no stockfish_pool_client tag in Gemfile}"

if [ "$#" -eq 1 ]; then
  tag=$1
  [ -n "$tag" ] || usage
else
  working_ref=$(pool_ref_value)
  if [ -n "$working_ref" ] && [ "$working_ref" != "$current_gemfile_tag" ]; then
    tag=$working_ref
    echo "using POOL_REF tag: $tag"
  elif [ -t 0 ]; then
    read -r -p "stockfish-pool tag: " tag
    [ -n "$tag" ] || usage
  else
    usage
  fi
fi

assert_clean_enough

if pins_agree_at "$tag" && chess_rules_current; then
  echo "already at $tag"
  if [ "$(git branch --show-current)" = "$branch" ]; then
    ensure_pr "$tag" || true
  fi
  exit 0
fi

if ! tag_exists_on_remote "$tag"; then
  sibling=$(cd .. && pwd)/stockfish-pool
  if [ -d "$sibling/.git" ] && \
     git -C "$sibling" rev-parse "${tag}^{commit}" >/dev/null 2>&1; then
    echo "tag ${tag} exists in ${sibling} but is not on ${pool_repo_url}; push the tag first" >&2
  else
    echo "tag not found on ${pool_repo_url}: ${tag}" >&2
  fi
  exit 1
fi

# Discard a dirty POOL_REF; the resolved $tag is authoritative from here.
git checkout -- POOL_REF

git fetch origin
git checkout main
git pull --ff-only origin main

# After updating main, "already at tag" may now hold.
current_gemfile_tag=$(gemfile_tag)
if pins_agree_at "$tag" && chess_rules_current; then
  echo "already at $tag"
  exit 0
fi

git checkout -B "$branch"

printf '%s\n' "$tag" >POOL_REF
set_gemfile_tag "$tag"
bundle install
bin/sync-chess-rules
bin/check-pool-ref

git add POOL_REF Gemfile Gemfile.lock lib/chess_rules
if git diff --cached --quiet; then
  echo "no changes to commit (pins already at $tag on $branch)"
else
  git commit -m "chore: bump stockfish-pool to ${tag}"
fi

git push -u origin "$branch" --force-with-lease
ensure_pr "$tag"
