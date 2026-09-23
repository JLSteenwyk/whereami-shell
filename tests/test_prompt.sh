. "$WHEREAMI_ROOT/whereami.sh"

ESC=$(printf '\033')

test_color_code_maps_named_colors() {
  assert_eq "${ESC}[31m" "$(whereami_color_code red)"
  assert_eq "${ESC}[36m" "$(whereami_color_code cyan)"
  assert_eq "${ESC}[95m" "$(whereami_color_code bright-magenta)"
}

test_color_code_maps_256_numbers() {
  assert_eq "${ESC}[38;5;208m" "$(whereami_color_code 208)"
}

test_color_code_rejects_unknown_and_out_of_range() {
  ! whereami_color_code purple >/dev/null
  ! whereami_color_code 999 >/dev/null
  ! whereami_color_code 12abc >/dev/null
}

test_ps1_local_segment_has_marker_name_and_guards() {
  WHEREAMI_NAME=macbook WHEREAMI_COLOR=green WHEREAMI_SESSION=local
  out=$(whereami_ps1)
  assert_contains "$out" "LOCAL"
  assert_contains "$out" "macbook"
  assert_contains "$out" '\['
  assert_contains "$out" '\]'
  assert_contains "$out" "${ESC}[32m"
  assert_contains "$out" "${ESC}[0m"
}

test_ps1_ssh_segment_uses_ssh_marker() {
  WHEREAMI_NAME=threadripper WHEREAMI_COLOR=magenta WHEREAMI_SESSION=ssh
  out=$(whereami_ps1)
  assert_contains "$out" "SSH"
  assert_contains "$out" "threadripper"
  case "$out" in *LOCAL*) echo "should not contain LOCAL" >&2; return 1;; esac
}

test_ps1_unknown_color_falls_back_to_derived_color() {
  WHEREAMI_NAME=macbook WHEREAMI_COLOR=purple WHEREAMI_SESSION=local
  out=$(whereami_ps1)
  assert_contains "$out" "$(whereami_color_code "$(whereami_default_color macbook)")"
}

test_ps1_plain_has_no_escapes_when_color_disabled() {
  WHEREAMI_NAME=macbook WHEREAMI_COLOR=green WHEREAMI_SESSION=local WHEREAMI_COLOR_ENABLED=0
  out=$(whereami_ps1)
  assert_eq "LOCAL  macbook" "$out"
}

test_setup_prefixes_PS1_by_default() {
  PS1='\w \$ '
  WHEREAMI_NAME=macbook
  whereami_setup
  assert_contains "$PS1" '$(whereami_ps1)'
  assert_contains "$PS1" '\w \$ '
}

test_setup_does_not_touch_PS1_when_prompt_disabled() {
  PS1='\w \$ '
  WHEREAMI_PROMPT=0
  whereami_setup
  assert_eq '\w \$ ' "$PS1"
}

test_setup_is_idempotent() {
  PS1='\w \$ '
  whereami_setup; whereami_setup
  n=$(printf '%s' "$PS1" | grep -o 'whereami_ps1' | wc -l | tr -d ' ')
  assert_eq 1 "$n"
}
