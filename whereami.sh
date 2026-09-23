#!/usr/bin/env bash
# whereami-shell: know which computer you're using before you run a command.
#
# Source this file from ~/.bashrc:   source /path/to/whereami.sh
# Works on Bash 3.2 and newer. Never calls `exit`.

WHEREAMI_VERSION="0.2.0"
WHEREAMI_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# --- configuration -----------------------------------------------------------

# Path of the per-machine config file. Override with WHEREAMI_CONFIG.
whereami_config_path() {
  if [ -n "${WHEREAMI_CONFIG:-}" ]; then
    printf '%s\n' "$WHEREAMI_CONFIG"
  else
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/whereami/config"
  fi
}

# Flag file whose presence hides the prompt segment on this machine.
whereami_disabled_path() {
  local cfg; cfg=$(whereami_config_path)
  printf '%s/disabled\n' "${cfg%/*}"
}

# 0 when the prompt segment should be shown. Checked on every prompt so a
# toggle from the menu bar app or another shell takes effect immediately.
whereami_enabled() { [ ! -e "$(whereami_disabled_path)" ]; }

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
  local env_tint="${WHEREAMI_TINT:-}" env_bg="${WHEREAMI_BACKGROUND:-}" env_label="${WHEREAMI_LABEL:-}"
  local file_name="" file_color="" file_tint="" file_bg="" file_label=""
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
        name)       file_name=$value ;;
        color)      file_color=$value ;;
        tint)       file_tint=$value ;;
        background) file_bg=$value ;;
        label)      file_label=$value ;;
      esac
    done < "$file"
  fi
  WHEREAMI_NAME=${env_name:-${file_name:-$(whereami_hostname)}}
  WHEREAMI_COLOR=${env_color:-${file_color:-$(whereami_default_color "$WHEREAMI_NAME")}}
  WHEREAMI_TINT=${env_tint:-${file_tint:-ssh}}          # ssh | always | off
  WHEREAMI_BACKGROUND=${env_bg:-$file_bg}              # optional #rrggbb
  WHEREAMI_LABEL=${env_label:-${file_label:-off}}      # on | off
  export WHEREAMI_NAME WHEREAMI_COLOR WHEREAMI_TINT WHEREAMI_BACKGROUND WHEREAMI_LABEL
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

# A dark terminal background (#rrggbb) for a color name or 0-255 number.
whereami_background_for() {
  local c="$1" r g b i
  case "$c" in
    black|bright-black)     printf '#1a1a1a\n'; return ;;
    red|bright-red)         printf '#3a0f0f\n'; return ;;
    green|bright-green)     printf '#0f2e14\n'; return ;;
    yellow|bright-yellow)   printf '#332b0a\n'; return ;;
    blue|bright-blue)       printf '#0f1a3a\n'; return ;;
    magenta|bright-magenta) printf '#3a0f2e\n'; return ;;
    cyan|bright-cyan)       printf '#0a2e33\n'; return ;;
    white|bright-white)     printf '#2e2e2e\n'; return ;;
  esac
  if ! whereami_color_valid "$c"; then
    whereami_background_for "$(whereami_default_color "${WHEREAMI_NAME:-$(whereami_hostname)}")"
    return
  fi
  # xterm-256 number -> rgb, darkened to 30%
  if [ "$c" -lt 16 ]; then
    set -- 0,0,0 205,0,0 0,205,0 205,205,0 0,0,238 205,0,205 0,205,205 229,229,229 \
           127,127,127 255,0,0 0,255,0 255,255,0 92,92,255 255,0,255 0,255,255 255,255,255
    shift "$c"; IFS=, read -r r g b <<EOF
$1
EOF
  elif [ "$c" -lt 232 ]; then
    i=$((c - 16)); set -- 0 95 135 175 215 255
    r=$(eval "printf '%s' \${$((i / 36 + 1))}")
    g=$(eval "printf '%s' \${$((i / 6 % 6 + 1))}")
    b=$(eval "printf '%s' \${$((i % 6 + 1))}")
  else
    r=$((8 + (c - 232) * 10)); g=$r; b=$r
  fi
  printf '#%02x%02x%02x\n' $((r * 30 / 100)) $((g * 30 / 100)) $((b * 30 / 100))
}

# Escape sequence that tints (or resets) the terminal window background.
# Emitted on every prompt so leaving an SSH session restores the local color.
whereami_tint() {
  local seq bg
  case "${TERM:-}" in dumb|'') return 0 ;; esac
  [ -n "${WHEREAMI_NAME:-}" ] || whereami_load_config
  whereami_detect_session
  case "${WHEREAMI_TINT:-ssh}" in off) return 0 ;; esac
  if whereami_enabled && { [ "${WHEREAMI_TINT:-ssh}" = always ] || [ "${WHEREAMI_SESSION:-local}" = ssh ]; }; then
    bg=${WHEREAMI_BACKGROUND:-$(whereami_background_for "${WHEREAMI_COLOR:-}")}
    seq=$(printf '\033]11;%s\007' "$bg")
  else
    seq=$(printf '\033]111\007')
  fi
  if whereami_in_tmux; then
    printf '\033Ptmux;\033%s\033\\' "$seq"
  else
    printf '%s' "$seq"
  fi
}

# The prompt segment: "LOCAL  name" or "SSH    name", colored. Only shown when
# label=on. Escapes are wrapped in \001/\002 (readline's ignore markers)
# because \[ \] are not interpreted when they come out of a $(...) in PS1.
whereami_ps1() {
  local marker color reset
  whereami_enabled || return 0
  [ -n "${WHEREAMI_NAME:-}" ] || whereami_load_config
  [ "${WHEREAMI_LABEL:-off}" = on ] || return 0
  whereami_detect_session
  if [ "$WHEREAMI_SESSION" = ssh ]; then marker="SSH   "; else marker="LOCAL "; fi
  if [ "${WHEREAMI_COLOR_ENABLED:-1}" = 0 ]; then
    printf '%s %s ' "$marker" "$WHEREAMI_NAME"
    return 0
  fi
  color=$(whereami_color_code "${WHEREAMI_COLOR:-}") \
    || color=$(whereami_color_code "$(whereami_default_color "$WHEREAMI_NAME")")
  reset=$(printf '\033[0m')
  if [ "$WHEREAMI_SESSION" = ssh ]; then
    # bold + reverse for the SSH marker so remote shells stand out
    printf '\001%s\033[1;7m\002 %s\001%s\002 \001%s\033[1m\002%s\001%s\002 ' \
      "$color" "$marker" "$reset" "$color" "$WHEREAMI_NAME" "$reset"
  else
    printf '\001%s\002%s \001%s\033[1m\002%s\001%s\002 ' \
      "$color" "$marker" "$color" "$WHEREAMI_NAME" "$reset"
  fi
}

# Prefix PS1 with the tint sequence and the (optional) label unless
# WHEREAMI_PROMPT=0. Safe to call twice.
whereami_setup() {
  whereami_load_config
  whereami_detect_session
  [ "${WHEREAMI_PROMPT:-1}" = 0 ] && return 0
  case "${PS1:-}" in *whereami_tint*) return 0 ;; esac
  PS1='\[$(whereami_tint)\]$(whereami_ps1)'"${PS1:-\\w \\$ }"
}

# --- command -----------------------------------------------------------------

whereami_usage() {
  cat <<'USAGE'
Usage: whereami [COMMAND]

  (none)               Show the machine name, session type, host, tmux, color
  name                 Print only the machine name
  ps1                  Print the raw prompt segment (for custom PS1)
  on | off | toggle    Enable or disable whereami in every shell on this
                       machine (creates/removes ~/.config/whereami/disabled)
  init [--force] NAME [COLOR]
                       Write ~/.config/whereami/config for this machine
  deploy HOST [--name NAME] [--color COLOR]
                       Install whereami-shell on a remote machine over SSH
                       (NAME defaults to HOST without any user@ prefix)
  --help, -h           Show this help
  --version            Show version

Colors: black red green yellow blue magenta cyan white, bright-<color>, or 0-255.
Config keys (~/.config/whereami/config):
  name, color          Machine name and color
  tint=ssh|always|off  Tint the terminal window background (default: ssh only)
  background=#rrggbb   Explicit window color (default: dark shade of color)
  label=on|off         Also show "SSH name" text in the prompt (default: off)
Environment: WHEREAMI_NAME, _COLOR, _TINT, _BACKGROUND, _LABEL override the
             file; WHEREAMI_PROMPT=0 leaves PS1 alone; WHEREAMI_CONFIG sets the file.
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

# Copy whereami.sh, bin/whereami and install.sh to HOST over ssh and run the
# installer there. No git or network access is needed on the remote side.
whereami_deploy() {
  local host="" name="" color=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name)  name=${2:-};  shift 2 ;;
      --color) color=${2:-}; shift 2 ;;
      -*) printf 'whereami deploy: unknown option %s\n' "$1" >&2; return 2 ;;
      *) if [ -z "$host" ]; then host=$1; else
           printf 'whereami deploy: unexpected argument %s\n' "$1" >&2; return 2; fi
         shift ;;
    esac
  done
  if [ -z "$host" ]; then
    printf 'usage: whereami deploy HOST [--name NAME] [--color COLOR]\n' >&2; return 2
  fi
  [ -n "$name" ] || { name=${host##*@}; name=${name%%.*}; }
  [ -n "$color" ] || color=$(whereami_default_color "$name")
  if ! whereami_color_valid "$color"; then
    printf 'whereami deploy: unknown color "%s"\n' "$color" >&2; return 2
  fi
  for f in whereami.sh bin/whereami install.sh; do
    if [ ! -f "$WHEREAMI_DIR/$f" ]; then
      printf 'whereami deploy: missing %s in %s\n' "$f" "$WHEREAMI_DIR" >&2; return 1
    fi
  done
  printf 'deploying to %s as "%s" (%s)\n' "$host" "$name" "$color"
  tar -C "$WHEREAMI_DIR" -cf - whereami.sh bin/whereami install.sh \
    | ssh "$host" "d=\$(mktemp -d) && tar -xf - -C \"\$d\" \
        && bash \"\$d/install.sh\" --name '$name' --color '$color'; s=\$?; rm -rf \"\$d\"; exit \$s"
}

whereami_on() {
  rm -f "$(whereami_disabled_path)" || return 1
  printf 'prompt: on\n'
}

whereami_off() {
  local flag; flag=$(whereami_disabled_path)
  mkdir -p "${flag%/*}" && : > "$flag" || return 1
  printf 'prompt: off\n'
}

whereami_toggle() {
  if whereami_enabled; then whereami_off; else whereami_on; fi
}

whereami_status() {
  local tmux=no prompt=on
  whereami_load_config
  whereami_detect_session
  whereami_in_tmux && tmux=yes
  whereami_enabled || prompt=off
  printf 'name:    %s\n' "$WHEREAMI_NAME"
  printf 'session: %s\n' "$WHEREAMI_SESSION"
  printf 'host:    %s\n' "$(hostname 2>/dev/null || printf unknown)"
  printf 'user:    %s\n' "${USER:-$(id -un 2>/dev/null)}"
  printf 'tmux:    %s\n' "$tmux"
  printf 'color:   %s\n' "$WHEREAMI_COLOR"
  printf 'enabled: %s\n' "$prompt"
  printf 'tint:    %s%s\n' "$WHEREAMI_TINT" "${WHEREAMI_BACKGROUND:+ ($WHEREAMI_BACKGROUND)}"
  printf 'label:   %s\n' "$WHEREAMI_LABEL"
  printf 'config:  %s\n' "$(whereami_config_path)"
}

whereami() {
  case "${1:-}" in
    '')          whereami_status ;;
    name)        whereami_load_config; printf '%s\n' "$WHEREAMI_NAME" ;;
    ps1)         whereami_ps1; printf '\n' ;;
    init)        shift; whereami_init "$@" ;;
    deploy)      shift; whereami_deploy "$@" ;;
    on)          whereami_on ;;
    off)         whereami_off ;;
    toggle)      whereami_toggle ;;
    -h|--help|help) whereami_usage ;;
    --version|version) printf 'whereami-shell %s\n' "$WHEREAMI_VERSION" ;;
    *) printf 'whereami: unknown command "%s"\n\n' "$1" >&2; whereami_usage >&2; return 2 ;;
  esac
}

# --- entry point when sourced from an interactive shell -----------------------

if [ -z "${WHEREAMI_NO_SETUP:-}" ]; then
  case "$-" in *i*) whereami_setup ;; esac
fi
