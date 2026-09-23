test_install_copies_files_and_appends_source_line() {
  touch "$HOME/.bashrc"
  "$WHEREAMI_ROOT/install.sh" >/dev/null
  [ -f "$HOME/.local/share/whereami-shell/whereami.sh" ]
  [ -x "$HOME/.local/share/whereami-shell/bin/whereami" ]
  grep -q 'whereami-shell/whereami.sh' "$HOME/.bashrc"
}

test_install_is_idempotent() {
  touch "$HOME/.bashrc"
  "$WHEREAMI_ROOT/install.sh" >/dev/null
  "$WHEREAMI_ROOT/install.sh" >/dev/null
  n=$(grep -c 'whereami-shell/whereami.sh' "$HOME/.bashrc")
  assert_eq 1 "$n"
}

test_install_creates_bashrc_when_missing() {
  "$WHEREAMI_ROOT/install.sh" >/dev/null
  grep -q 'whereami-shell/whereami.sh' "$HOME/.bashrc"
}

test_install_with_name_writes_config() {
  "$WHEREAMI_ROOT/install.sh" --name macbook --color green >/dev/null
  assert_eq "name=macbook
color=green" "$(cat "$HOME/.config/whereami/config")"
}

test_installed_copy_works_from_bashrc() {
  "$WHEREAMI_ROOT/install.sh" --name box --color red >/dev/null
  out=$(bash -ic 'whereami name' 2>/dev/null)
  assert_eq box "$out"
}
