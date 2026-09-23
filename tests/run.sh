#!/usr/bin/env bash
# Minimal test runner: every tests/test_*.sh file is sourced; each function
# named test_* is run in a subshell with a fresh temp HOME.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export WHEREAMI_ROOT="$ROOT"
pass=0; fail=0; failed_names=""

assert_eq() { # expected actual [message]
  if [ "$1" != "$2" ]; then
    printf '    expected: %s\n    actual:   %s\n' "$1" "$2" >&2
    [ -n "${3:-}" ] && printf '    %s\n' "$3" >&2
    return 1
  fi
}
assert_contains() { # haystack needle
  case "$1" in *"$2"*) return 0;; esac
  printf '    expected to contain: %s\n    actual: %s\n' "$2" "$1" >&2
  return 1
}

for file in "$ROOT"/tests/test_*.sh; do
  names=$(grep -o '^test_[A-Za-z0-9_]*' "$file")
  for name in $names; do
    tmp=$(mktemp -d)
    if ( set -e
         export HOME="$tmp" TMPDIR="$tmp" PATH="$PATH"
         unset SSH_CONNECTION SSH_CLIENT SSH_TTY TMUX WHEREAMI_NAME WHEREAMI_COLOR \
               WHEREAMI_SESSION WHEREAMI_PROMPT WHEREAMI_CONFIG
         . "$file"
         "$name" ) 2>"$tmp/err"; then
      pass=$((pass + 1))
      printf 'ok   %s\n' "$name"
    else
      fail=$((fail + 1)); failed_names="$failed_names $name"
      printf 'FAIL %s\n' "$name"
      sed 's/^/     /' "$tmp/err"
    fi
    rm -rf "$tmp"
  done
done
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
