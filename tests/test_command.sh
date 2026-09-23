. "$WHEREAMI_ROOT/whereami.sh"

test_whereami_prints_name_session_and_host() {
  mkdir -p "$HOME/.config/whereami"
  printf 'name=dgx-spark-1\ncolor=cyan\n' > "$HOME/.config/whereami/config"
  SSH_TTY=/dev/pts/0
  out=$(whereami)
  assert_contains "$out" "dgx-spark-1"
  assert_contains "$out" "ssh"
  assert_contains "$out" "$(hostname)"
  assert_contains "$out" "cyan"
  assert_contains "$out" "$HOME/.config/whereami/config"
}

test_whereami_reports_tmux() {
  TMUX=/tmp/tmux-1/default,1,0
  whereami | grep -q "^tmux: *yes$"
  unset TMUX
  whereami | grep -q "^tmux: *no$"
}

test_whereami_name_prints_only_the_name() {
  WHEREAMI_NAME=macbook
  assert_eq macbook "$(whereami name)"
}

test_whereami_init_writes_config() {
  whereami init threadripper magenta >/dev/null
  assert_eq "name=threadripper
color=magenta" "$(cat "$HOME/.config/whereami/config")"
}

test_whereami_init_refuses_to_overwrite_without_force() {
  whereami init one red >/dev/null
  ! whereami init two blue >/dev/null 2>&1
  assert_contains "$(cat "$HOME/.config/whereami/config")" "name=one"
  whereami init --force two blue >/dev/null
  assert_contains "$(cat "$HOME/.config/whereami/config")" "name=two"
}

test_whereami_init_rejects_bad_color() {
  ! whereami init box purple >/dev/null 2>&1
  [ ! -e "$HOME/.config/whereami/config" ]
}

test_whereami_help_and_version() {
  assert_contains "$(whereami --help)" "Usage"
  assert_contains "$(whereami --version)" "$WHEREAMI_VERSION"
}

test_whereami_unknown_subcommand_fails() {
  ! whereami bogus >/dev/null 2>&1
}

test_bin_wrapper_runs_without_sourcing() {
  export WHEREAMI_NAME=viaBin
  out=$("$WHEREAMI_ROOT/bin/whereami" name)
  assert_eq viaBin "$out"
}
