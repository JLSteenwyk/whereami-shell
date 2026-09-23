. "$WHEREAMI_ROOT/whereami.sh"

# Put a fake ps on PATH that reports the given parent chain: "pid ppid comm" rows.
fake_ps() {
  mkdir -p "$HOME/fakebin"
  printf '%s\n' "$1" > "$HOME/fakebin/ps.table"
  cat > "$HOME/fakebin/ps" <<'PS'
#!/usr/bin/env bash
# supports: ps -o ppid= -o comm= -p PID
pid="${@: -1}"
awk -v pid="$pid" '$1 == pid { print $2, $3 }' "$(dirname "$0")/ps.table"
PS
  chmod +x "$HOME/fakebin/ps"
  PATH="$HOME/fakebin:$PATH"
}

test_ssh_connection_env_means_ssh() {
  SSH_CONNECTION="1.2.3.4 5 6.7.8.9 22"
  whereami_is_ssh
}

test_ssh_tty_env_means_ssh() {
  SSH_TTY=/dev/pts/3
  whereami_is_ssh
}

test_no_env_and_no_sshd_ancestor_means_local() {
  fake_ps "$$ 100 bash
100 1 login
1 0 launchd"
  ! whereami_is_ssh
}

test_sshd_ancestor_means_ssh_even_without_env() {
  fake_ps "$$ 200 bash
200 300 tmux: server
300 400 bash
400 500 sshd: user@pts/0
500 1 sshd
1 0 init"
  whereami_is_ssh
}

test_process_walk_stops_at_pid_1() {
  fake_ps "$$ 1 bash
1 0 init"
  ! whereami_is_ssh
}

test_session_is_cached_in_WHEREAMI_SESSION() {
  SSH_TTY=/dev/pts/1
  whereami_detect_session
  assert_eq ssh "$WHEREAMI_SESSION"
  unset SSH_TTY
  whereami_detect_session
  assert_eq ssh "$WHEREAMI_SESSION" "cached value should survive env change"
}

test_in_tmux_reads_TMUX_var() {
  ! whereami_in_tmux
  TMUX=/tmp/tmux-501/default,123,0
  whereami_in_tmux
}
