#!/usr/bin/env bash
# whereami-shell: know which computer you're using before you run a command.
#
# Source this file from ~/.bashrc:   source /path/to/whereami.sh
# Works on Bash 3.2 and newer. Never calls `exit`.

WHEREAMI_VERSION="0.1.0"

# --- configuration -----------------------------------------------------------

# Path of the per-machine config file. Override with WHEREAMI_CONFIG.
whereami_config_path() {
  if [ -n "${WHEREAMI_CONFIG:-}" ]; then
    printf '%s\n' "$WHEREAMI_CONFIG"
  else
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/whereami/config"
  fi
}

whereami_hostname() {
  local h
  h=$(hostname -s 2>/dev/null) || h=$(hostname 2>/dev/null) || h=${HOSTNAME:-unknown}
  printf '%s\n' "${h%%.*}"
}

# Deterministic color from a name so unconfigured machines still differ.
whereami_default_color() {
  local name="$1" sum=0 i c
  local palette="red green yellow blue magenta cyan"
  i=0
  while [ "$i" -lt "${#name}" ]; do
    c=$(printf '%d' "'${name:$i:1}")
    sum=$(( (sum * 31 + c) % 6 ))
    i=$((i + 1))
  done
  set -- $palette
  shift "$sum"
  printf '%s\n' "$1"
}

# Populate WHEREAMI_NAME and WHEREAMI_COLOR.
# Precedence: environment > config file > hostname / derived color.
# The config file is parsed line by line, never sourced.
whereami_load_config() {
  local file key value line
  local env_name="${WHEREAMI_NAME:-}" env_color="${WHEREAMI_COLOR:-}"
  local file_name="" file_color=""
  file=$(whereami_config_path)
  if [ -r "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue ;; esac
      case "$line" in *=*) ;; *) continue ;; esac
      key=${line%%=*}; value=${line#*=}
      # trim whitespace
      key=${key#"${key%%[![:space:]]*}"};   key=${key%"${key##*[![:space:]]}"}
      value=${value#"${value%%[![:space:]]*}"}; value=${value%"${value##*[![:space:]]}"}
      case "$key" in
        name)  file_name=$value ;;
        color) file_color=$value ;;
      esac
    done < "$file"
  fi
  WHEREAMI_NAME=${env_name:-${file_name:-$(whereami_hostname)}}
  WHEREAMI_COLOR=${env_color:-${file_color:-$(whereami_default_color "$WHEREAMI_NAME")}}
  export WHEREAMI_NAME WHEREAMI_COLOR
}

# --- session detection -------------------------------------------------------

whereami_in_tmux() { [ -n "${TMUX:-}" ]; }

# True when an ancestor of this shell is sshd. Covers tmux windows that were
# created under SSH but did not inherit SSH_* variables.
whereami_has_sshd_ancestor() {
  local pid=$$ ppid comm out guard=0
  while [ "$pid" -gt 1 ] && [ "$guard" -lt 64 ]; do
    out=$(ps -o ppid= -o comm= -p "$pid" 2>/dev/null) || return 1
    [ -n "$out" ] || return 1
    set -- $out
    ppid=$1; shift; comm="$*"
    case "${comm##*/}" in sshd|sshd:*|sshd-session*) return 0 ;; esac
    [ "$ppid" != "$pid" ] || return 1
    pid=$ppid; guard=$((guard + 1))
  done
  return 1
}

whereami_is_ssh() {
  [ -n "${SSH_CONNECTION:-}" ] && return 0
  [ -n "${SSH_CLIENT:-}" ] && return 0
  [ -n "${SSH_TTY:-}" ] && return 0
  whereami_has_sshd_ancestor
}

# Compute once per shell and cache in WHEREAMI_SESSION ("ssh" or "local").
whereami_detect_session() {
  if [ -z "${WHEREAMI_SESSION:-}" ]; then
    if whereami_is_ssh; then WHEREAMI_SESSION=ssh; else WHEREAMI_SESSION=local; fi
    export WHEREAMI_SESSION
  fi
}

# --- colors and prompt -------------------------------------------------------

# Print the SGR escape for a color name or a 0-255 number. Fails on unknown.
whereami_color_code() {
  local c="$1" n
  case "$c" in
    black)          n=30 ;; red)            n=31 ;; green)          n=32 ;;
    yellow)         n=33 ;; blue)           n=34 ;; magenta)        n=35 ;;
    cyan)           n=36 ;; white)          n=37 ;;
    bright-black)   n=90 ;; bright-red)     n=91 ;; bright-green)   n=92 ;;
    bright-yellow)  n=93 ;; bright-blue)    n=94 ;; bright-magenta) n=95 ;;
    bright-cyan)    n=96 ;; bright-white)   n=97 ;;
    *[!0-9]*|'')    return 1 ;;
    *) [ "$c" -le 255 ] || return 1; n="38;5;$c" ;;
  esac
  printf '\033[%sm' "$n"
}

whereami_color_valid() { whereami_color_code "$1" >/dev/null 2>&1; }

# The prompt segment: "LOCAL  name" or "SSH    name", colored, with \[ \]
# guards so Bash does not count the escapes toward the line width.
whereami_ps1() {
  local marker color reset
  [ -n "${WHEREAMI_NAME:-}" ] || whereami_load_config
  whereami_detect_session
  if [ "$WHEREAMI_SESSION" = ssh ]; then marker="SSH   "; else marker="LOCAL "; fi
  if [ "${WHEREAMI_COLOR_ENABLED:-1}" = 0 ]; then
    printf '%s %s' "$marker" "$WHEREAMI_NAME"
    return 0
  fi
  color=$(whereami_color_code "${WHEREAMI_COLOR:-}") \
    || color=$(whereami_color_code "$(whereami_default_color "$WHEREAMI_NAME")")
  reset=$(printf '\033[0m')
  if [ "$WHEREAMI_SESSION" = ssh ]; then
    # bold + reverse for the SSH marker so remote shells stand out
    printf '\[%s\033[1;7m\] %s\[%s\] \[%s\033[1m\]%s\[%s\]' \
      "$color" "$marker" "$reset" "$color" "$WHEREAMI_NAME" "$reset"
  else
    printf '\[%s\]%s \[%s\033[1m\]%s\[%s\]' \
      "$color" "$marker" "$color" "$WHEREAMI_NAME" "$reset"
  fi
}

# Prefix PS1 with the segment unless WHEREAMI_PROMPT=0. Safe to call twice.
whereami_setup() {
  whereami_load_config
  whereami_detect_session
  [ "${WHEREAMI_PROMPT:-1}" = 0 ] && return 0
  case "${PS1:-}" in *whereami_ps1*) return 0 ;; esac
  PS1='$(whereami_ps1) '"${PS1:-\\w \\$ }"
}

# --- command -----------------------------------------------------------------

whereami_usage() {
  cat <<'USAGE'
Usage: whereami [COMMAND]

  (none)               Show the machine name, session type, host, tmux, color
  name                 Print only the machine name
  ps1                  Print the raw prompt segment (for custom PS1)
  init [--force] NAME [COLOR]
                       Write ~/.config/whereami/config for this machine
  --help, -h           Show this help
  --version            Show version

Colors: black red green yellow blue magenta cyan white, bright-<color>, or 0-255.
Environment: WHEREAMI_NAME, WHEREAMI_COLOR override the config file;
             WHEREAMI_PROMPT=0 leaves PS1 alone; WHEREAMI_CONFIG sets the file.
USAGE
}

whereami_init() {
  local force=0 name color file dir
  while [ $# -gt 0 ]; do
    case "$1" in
      --force|-f) force=1; shift ;;
      -*) printf 'whereami init: unknown option %s\n' "$1" >&2; return 2 ;;
      *) break ;;
    esac
  done
  name=${1:-}; color=${2:-}
  if [ -z "$name" ]; then
    printf 'whereami init: NAME is required\n' >&2; return 2
  fi
  [ -n "$color" ] || color=$(whereami_default_color "$name")
  if ! whereami_color_valid "$color"; then
    printf 'whereami init: unknown color "%s"\n' "$color" >&2; return 2
  fi
  file=$(whereami_config_path); dir=${file%/*}
  if [ -e "$file" ] && [ "$force" != 1 ]; then
    printf 'whereami init: %s exists (use --force to overwrite)\n' "$file" >&2
    return 1
  fi
  mkdir -p "$dir" || return 1
  printf 'name=%s\ncolor=%s\n' "$name" "$color" > "$file" || return 1
  WHEREAMI_NAME=$name WHEREAMI_COLOR=$color
  printf 'wrote %s\n' "$file"
  whereami_status
}

whereami_status() {
  local tmux=no
  whereami_load_config
  whereami_detect_session
  whereami_in_tmux && tmux=yes
  printf 'name:    %s\n' "$WHEREAMI_NAME"
  printf 'session: %s\n' "$WHEREAMI_SESSION"
  printf 'host:    %s\n' "$(hostname 2>/dev/null || printf unknown)"
  printf 'user:    %s\n' "${USER:-$(id -un 2>/dev/null)}"
  printf 'tmux:    %s\n' "$tmux"
  printf 'color:   %s\n' "$WHEREAMI_COLOR"
  printf 'config:  %s\n' "$(whereami_config_path)"
}

whereami() {
  case "${1:-}" in
    '')          whereami_status ;;
    name)        whereami_load_config; printf '%s\n' "$WHEREAMI_NAME" ;;
    ps1)         whereami_ps1; printf '\n' ;;
    init)        shift; whereami_init "$@" ;;
    -h|--help|help) whereami_usage ;;
    --version|version) printf 'whereami-shell %s\n' "$WHEREAMI_VERSION" ;;
    *) printf 'whereami: unknown command "%s"\n\n' "$1" >&2; whereami_usage >&2; return 2 ;;
  esac
}

# --- entry point when sourced from an interactive shell -----------------------

if [ -z "${WHEREAMI_NO_SETUP:-}" ]; then
  case "$-" in *i*) whereami_setup ;; esac
fi
