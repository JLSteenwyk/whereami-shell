# whereami-shell

Know which computer you're using before you run a command.

whereami-shell makes the active machine obvious in your terminal prompt,
especially when you SSH between a laptop, workstation, and remote servers. Each
machine can have a recognizable name and color, and remote sessions show an
SSH indicator.

```
LOCAL  macbook       ~/projects $
SSH    threadripper  ~/analysis $
SSH    dgx-spark-1   ~/models $
```

The displayed name and color describe the machine running the shell, not the
computer where the terminal window was opened. Configuration lives on each
machine's own disk, so the identity stays correct through nested SSH hops and
inside tmux.

## Goals

- Show the current machine in every shell prompt.
- Make SSH sessions visually distinct from local sessions.
- Keep the correct identity through nested SSH connections and tmux.
- Provide a `whereami` command for a quick, explicit check.
- Start with Bash and allow simple per-machine configuration.

## Install

Install on your main machine first:

```sh
git clone https://github.com/JLSteenwyk/whereami-shell.git
cd whereami-shell
./install.sh --name macbook --color green
```

`install.sh` copies the script to `~/.local/share/whereami-shell`, appends a
`source` line to `~/.bashrc`, and writes the machine's name and color to
`~/.config/whereami/config`. Open a new shell to see the prompt.

Without `--name`, the short hostname is used and a color is derived from it.

The installer adds its line to `~/.bashrc`, and also to `~/.bash_profile` when
that file exists and does not source `.bashrc`, because SSH logins and macOS
Terminal start login shells.

### Remote machines

The prompt on a server is drawn by that server's own Bash, so each machine
needs its own copy. From a machine that already has whereami-shell:

```sh
whereami deploy threadripper --name threadripper --color magenta
whereami deploy jacob@dgx-spark-1                  # name defaults to the host
```

`deploy` copies the three needed files over SSH and runs the installer on the
remote. The remote needs Bash as its login shell; nothing else.

Requirements: Bash 3.2 or newer (the macOS default works). No other
dependencies.

## The `whereami` command

```
$ whereami
name:    threadripper
session: ssh
host:    threadripper.lab
user:    jacob
tmux:    yes
color:   magenta
config:  /home/jacob/.config/whereami/config

$ whereami name           # just the name, handy in scripts
$ whereami init NAME [COLOR]   # (re)write this machine's config
$ whereami deploy HOST    # install on a remote machine over SSH
$ whereami off            # hide the prompt segment in every shell on this machine
$ whereami on             # show it again (whereami toggle flips it)
$ whereami --help
```

`on`/`off` work by creating or removing `~/.config/whereami/disabled`. The
prompt checks for that file every time it is drawn, so all open shells react
immediately and no restart is needed. The flag is per machine: turning the
prompt off on your laptop does not hide the `SSH` marker on a server.

`bin/whereami` also works without sourcing anything, so `ssh host whereami`
answers from the remote side.

## macOS menu bar app

![menu bar item](docs/menubar.png)

`WhereAmI.app` adds a small computer icon to the menu bar, tinted with this
machine's color (gray while the prompt is off). Clicking it shows the machine
name, host, prompt state, and any SSH sessions currently open from this Mac,
plus a **Show in prompt** toggle. It uses the same flag file as
`whereami on`/`off`, so the menu bar and every terminal stay in sync in both
directions.

```sh
make install-app   # builds with swiftc, copies to ~/Applications, launches
```

The menu offers **Show in prompt**, **Edit config…**, and **Start at login**.
Requires macOS 13 or newer and the Xcode command line tools for the one-time
build. `make app` builds without installing; `make run-app` launches the
build.

## Configuration

`~/.config/whereami/config` is a plain key/value file. It is parsed, never
executed.

```
name=threadripper
color=magenta
```

Colors: `black red green yellow blue magenta cyan white`, any `bright-<color>`,
or a number from 0 to 255 (xterm-256).

Environment variables:

| Variable | Effect |
|---|---|
| `WHEREAMI_NAME`, `WHEREAMI_COLOR` | Override the config file for this shell. |
| `WHEREAMI_PROMPT=0` | Do not modify `PS1`. Put `$(whereami_ps1)` in your own prompt instead. |
| `WHEREAMI_COLOR_ENABLED=0` | Plain text segment, no ANSI escapes. |
| `WHEREAMI_CONFIG` | Use a different config file path. The `disabled` flag lives next to it. |

Custom prompt example:

```sh
export WHEREAMI_PROMPT=0
source ~/.local/share/whereami-shell/whereami.sh
PS1='$(whereami_ps1)\w \$ '
```

The segment includes its own trailing space and prints nothing while the
prompt is turned off.

## How SSH detection works

A shell is marked `SSH` when `SSH_CONNECTION`, `SSH_CLIENT`, or `SSH_TTY` is
set. tmux windows do not always inherit those variables, so as a fallback the
parent process chain is walked looking for `sshd`. The result is computed once
per shell and cached in `WHEREAMI_SESSION`.

## Development

```sh
make test      # runs tests/run.sh, a dependency-free Bash test runner
make app       # compiles the menu bar app into build/WhereAmI.app
```

Design notes live in `docs/superpowers/specs/`.
