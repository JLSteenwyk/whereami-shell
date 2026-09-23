. "$WHEREAMI_ROOT/whereami.sh"

ESC=$(printf '\033'); BEL=$(printf '\007')

test_named_colors_map_to_dark_backgrounds() {
  assert_eq "#3a0f2e" "$(whereami_background_for magenta)"
  assert_eq "#0f1a3a" "$(whereami_background_for blue)"
  assert_eq "#3a0f2e" "$(whereami_background_for bright-magenta)"
}

test_numeric_color_maps_to_darkened_xterm_rgb() {
  # 208 = rgb(255,135,0) in the xterm cube; darkened to ~30%
  assert_eq "#4c2800" "$(whereami_background_for 208)"
}

test_unknown_color_falls_back_to_derived_name_color() {
  WHEREAMI_NAME=macbook
  assert_eq "$(whereami_background_for "$(whereami_default_color macbook)")" "$(whereami_background_for purple)"
}

test_explicit_background_wins() {
  WHEREAMI_NAME=x WHEREAMI_COLOR=red WHEREAMI_BACKGROUND='#123456' WHEREAMI_SESSION=ssh
  assert_eq "${ESC}]11;#123456${BEL}" "$(whereami_tint)"
}

test_ssh_session_emits_set_background_by_default() {
  WHEREAMI_NAME=x WHEREAMI_COLOR=magenta WHEREAMI_SESSION=ssh
  assert_eq "${ESC}]11;#3a0f2e${BEL}" "$(whereami_tint)"
}

test_local_session_emits_reset_by_default() {
  WHEREAMI_NAME=x WHEREAMI_COLOR=magenta WHEREAMI_SESSION=local
  assert_eq "${ESC}]111${BEL}" "$(whereami_tint)"
}

test_tint_always_colors_local_too() {
  WHEREAMI_NAME=x WHEREAMI_COLOR=green WHEREAMI_SESSION=local WHEREAMI_TINT=always
  assert_eq "${ESC}]11;#0f2e14${BEL}" "$(whereami_tint)"
}

test_tint_off_emits_nothing() {
  WHEREAMI_NAME=x WHEREAMI_COLOR=green WHEREAMI_SESSION=ssh WHEREAMI_TINT=off
  assert_eq "" "$(whereami_tint)"
}

test_tint_disabled_flag_emits_reset_so_windows_return_to_normal() {
  WHEREAMI_NAME=x WHEREAMI_COLOR=green WHEREAMI_SESSION=ssh
  whereami off >/dev/null
  assert_eq "${ESC}]111${BEL}" "$(whereami_tint)"
}

test_tint_is_wrapped_for_tmux_passthrough() {
  WHEREAMI_NAME=x WHEREAMI_COLOR=magenta WHEREAMI_SESSION=ssh TMUX=/tmp/tmux-1/default,1,0
  assert_eq "${ESC}Ptmux;${ESC}${ESC}]11;#3a0f2e${BEL}${ESC}\\" "$(whereami_tint)"
}

test_tint_skipped_on_dumb_terminal() {
  WHEREAMI_NAME=x WHEREAMI_COLOR=magenta WHEREAMI_SESSION=ssh TERM=dumb
  assert_eq "" "$(whereami_tint)"
}

test_config_file_sets_tint_background_and_label() {
  mkdir -p "$HOME/.config/whereami"
  printf 'name=a\ncolor=red\ntint=always\nbackground=#0a0a0a\nlabel=on\n' > "$HOME/.config/whereami/config"
  whereami_load_config
  assert_eq always "$WHEREAMI_TINT"
  assert_eq '#0a0a0a' "$WHEREAMI_BACKGROUND"
  assert_eq on "$WHEREAMI_LABEL"
}

test_label_defaults_off_so_ps1_text_is_empty() {
  WHEREAMI_NAME=macbook WHEREAMI_SESSION=local
  whereami_load_config
  assert_eq "" "$(whereami_ps1)"
}

test_setup_puts_tint_in_PS1_inside_guards() {
  PS1='\w \$ '
  whereami_setup
  assert_contains "$PS1" '\[$(whereami_tint)\]$(whereami_ps1)\w \$ '
}
