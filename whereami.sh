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
