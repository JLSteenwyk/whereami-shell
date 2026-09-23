. "$WHEREAMI_ROOT/whereami.sh"

# Fake ssh: runs the remote command locally with HOME set to a "remote" dir.
fake_ssh() {
  mkdir -p "$HOME/fakebin" "$HOME/remote"
  cat > "$HOME/fakebin/ssh" <<'SSH'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_SSH_LOG"
# skip options, take host, rest is the command
while [ $# -gt 0 ]; do case "$1" in -*) shift 2;; *) break;; esac; done
host=$1; shift
HOME="$FAKE_REMOTE_HOME" exec bash -c "$*"
SSH
  chmod +x "$HOME/fakebin/ssh"
  export FAKE_SSH_LOG="$HOME/ssh.log" FAKE_REMOTE_HOME="$HOME/remote"
  PATH="$HOME/fakebin:$PATH"
}

test_deploy_installs_on_remote_with_name_and_color() {
  fake_ssh
  whereami deploy threadripper --name threadripper --color magenta >/dev/null
  grep -q '^threadripper' "$FAKE_SSH_LOG"
  [ -f "$HOME/remote/.local/share/whereami-shell/whereami.sh" ]
  grep -q 'whereami-shell/whereami.sh' "$HOME/remote/.bashrc"
  assert_eq "name=threadripper
color=magenta" "$(cat "$HOME/remote/.config/whereami/config")"
}

test_deploy_defaults_name_to_host() {
  fake_ssh
  whereami deploy dgx-spark-1 >/dev/null
  grep -q 'name=dgx-spark-1' "$HOME/remote/.config/whereami/config"
}

test_deploy_strips_user_from_default_name() {
  fake_ssh
  whereami deploy jacob@dgx-spark-1 >/dev/null
  grep -q 'name=dgx-spark-1' "$HOME/remote/.config/whereami/config"
}

test_deploy_requires_host() {
  ! whereami deploy >/dev/null 2>&1
}

test_deploy_rejects_bad_color() {
  fake_ssh
  ! whereami deploy box --color purple >/dev/null 2>&1
  [ ! -e "$FAKE_SSH_LOG" ]
}
