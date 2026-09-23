. "$WHEREAMI_ROOT/whereami.sh"

test_name_falls_back_to_short_hostname() {
  whereami_load_config
  assert_eq "$(hostname -s 2>/dev/null || hostname)" "$WHEREAMI_NAME"
}

test_config_file_sets_name_and_color() {
  mkdir -p "$HOME/.config/whereami"
  printf 'name=threadripper\ncolor=magenta\n' > "$HOME/.config/whereami/config"
  whereami_load_config
  assert_eq threadripper "$WHEREAMI_NAME"
  assert_eq magenta "$WHEREAMI_COLOR"
}

test_config_ignores_comments_blank_lines_and_spaces() {
  mkdir -p "$HOME/.config/whereami"
  printf '# comment\n\n  name = dgx-spark-1  \ncolor= cyan\n' > "$HOME/.config/whereami/config"
  whereami_load_config
  assert_eq dgx-spark-1 "$WHEREAMI_NAME"
  assert_eq cyan "$WHEREAMI_COLOR"
}

test_config_file_is_not_executed() {
  mkdir -p "$HOME/.config/whereami"
  printf 'name=safe\ntouch %s/pwned\n$(touch %s/pwned2)\n' "$HOME" "$HOME" > "$HOME/.config/whereami/config"
  whereami_load_config
  assert_eq safe "$WHEREAMI_NAME"
  [ ! -e "$HOME/pwned" ] && [ ! -e "$HOME/pwned2" ]
}

test_env_overrides_config_file() {
  mkdir -p "$HOME/.config/whereami"
  printf 'name=fromfile\ncolor=red\n' > "$HOME/.config/whereami/config"
  WHEREAMI_NAME=fromenv WHEREAMI_COLOR=blue
  whereami_load_config
  assert_eq fromenv "$WHEREAMI_NAME"
  assert_eq blue "$WHEREAMI_COLOR"
}

test_whereami_config_env_points_to_alternate_file() {
  printf 'name=alt\n' > "$HOME/alt.conf"
  WHEREAMI_CONFIG="$HOME/alt.conf"
  whereami_load_config
  assert_eq alt "$WHEREAMI_NAME"
}

test_default_color_is_deterministic_and_in_palette() {
  a=$(whereami_default_color macbook)
  b=$(whereami_default_color macbook)
  c=$(whereami_default_color threadripper)
  assert_eq "$a" "$b"
  case "$a" in red|green|yellow|blue|magenta|cyan) ;; *) echo "bad color $a" >&2; return 1;; esac
  case "$c" in red|green|yellow|blue|magenta|cyan) ;; *) echo "bad color $c" >&2; return 1;; esac
}
