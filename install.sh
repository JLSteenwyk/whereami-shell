#!/usr/bin/env bash
# Install whereami-shell for the current user.
#
#   ./install.sh [--name NAME] [--color COLOR] [--prefix DIR]
#
# Copies whereami.sh and bin/ to $PREFIX (default ~/.local/share/whereami-shell)
# and appends a source line to ~/.bashrc if one is not already present.
set -eu

SRC=$(cd "$(dirname "$0")" && pwd)
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/whereami-shell"
NAME=""; COLOR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --name)   NAME=$2;   shift 2 ;;
    --color)  COLOR=$2;  shift 2 ;;
    --prefix) PREFIX=$2; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) printf 'install.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
  esac
done

mkdir -p "$PREFIX/bin"
cp "$SRC/whereami.sh" "$PREFIX/whereami.sh"
cp "$SRC/bin/whereami" "$PREFIX/bin/whereami"
chmod +x "$PREFIX/bin/whereami"
printf 'installed to %s\n' "$PREFIX"

BASHRC="$HOME/.bashrc"
LINE="[ -f \"$PREFIX/whereami.sh\" ] && . \"$PREFIX/whereami.sh\"  # whereami-shell"
touch "$BASHRC"
if grep -qF 'whereami-shell/whereami.sh' "$BASHRC"; then
  printf 'source line already present in %s\n' "$BASHRC"
else
  printf '\n# whereami-shell: show which machine this shell is on\n%s\n' "$LINE" >> "$BASHRC"
  printf 'added source line to %s\n' "$BASHRC"
fi

if [ -n "$NAME" ]; then
  WHEREAMI_NO_SETUP=1 . "$PREFIX/whereami.sh"
  whereami init --force "$NAME" ${COLOR:+"$COLOR"}
fi

printf '\nOpen a new shell, or run:  source %s\n' "$BASHRC"
