. "$WHEREAMI_ROOT/whereami.sh"

flag() { printf '%s/.config/whereami/disabled' "$HOME"; }

test_enabled_by_default() {
  whereami_enabled
}

test_off_creates_flag_and_ps1_prints_nothing() {
  WHEREAMI_NAME=macbook WHEREAMI_SESSION=local
  whereami off >/dev/null
  [ -e "$(flag)" ]
  ! whereami_enabled
  assert_eq "" "$(whereami_ps1)"
}

test_on_removes_flag_and_ps1_returns() {
  WHEREAMI_NAME=macbook WHEREAMI_SESSION=local WHEREAMI_COLOR_ENABLED=0
  whereami off >/dev/null
  whereami on >/dev/null
  [ ! -e "$(flag)" ]
  assert_eq "LOCAL  macbook " "$(whereami_ps1)"
}

test_on_is_fine_when_already_on() {
  whereami on >/dev/null
  whereami on >/dev/null
  whereami_enabled
}

test_toggle_flips_state() {
  whereami toggle >/dev/null
  ! whereami_enabled
  whereami toggle >/dev/null
  whereami_enabled
}

test_status_reports_prompt_state() {
  whereami | grep -q '^prompt: *on$'
  whereami off >/dev/null
  whereami | grep -q '^prompt: *off$'
}

test_flag_is_checked_live_not_cached() {
  WHEREAMI_NAME=macbook WHEREAMI_SESSION=local WHEREAMI_COLOR_ENABLED=0
  first=$(whereami_ps1)
  mkdir -p "$(dirname "$(flag)")"; touch "$(flag)"
  second=$(whereami_ps1)
  assert_eq "LOCAL  macbook " "$first"
  assert_eq "" "$second"
}
