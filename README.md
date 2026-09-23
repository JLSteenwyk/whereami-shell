# whereami-shell

Know which computer you're using before you run a command.

whereami-shell makes the active machine obvious in your terminal, especially
when you SSH between a laptop, workstation, and remote servers. Each machine has
a recognizable name and color. When you are on a remote machine, the terminal
window's background takes that machine's color; when you exit, it goes back to
normal. Optionally the prompt can also carry a text label:

```
LOCAL  macbook       ~/projects $
SSH    threadripper  ~/analysis $
SSH    dgx-spark-1   ~/models $
```

The window tint works in macOS Terminal, iTerm2, and most modern terminals,
because the shell emits the standard "set background color" escape sequence
(OSC 11) on every prompt. It works through nested SSH and inside tmux.

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
$ whereami off            # disable tint and label in every shell on this machine
$ whereami on             # enable again (whereami toggle flips it)
$ whereami --help
```

`on`/`off` work by creating or removing `~/.config/whereami/disabled`. The
prompt checks for that file every time it is drawn, so all open shells react
immediately and no restart is needed. The flag is per machine: turning it off
on your laptop does not stop a server from tinting the window.

`bin/whereami` also works without sourcing anything, so `ssh host whereami`
answers from the remote side.

## macOS menu bar app

![menu bar item](docs/menubar.png)

`WhereAmI.app` adds a small terminal icon to the menu bar, tinted with this
machine's color (gray while whereami is off). Clicking it shows the machine
name, host, state, and any SSH sessions currently open from this Mac, plus an
**Enabled on this Mac** toggle. It uses the same flag file as
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
# optional:
tint=ssh            # ssh (default): tint only when reached over SSH; always; off
background=#3a0f2e  # explicit window color; default is a dark shade of `color`
label=off           # on: also show "SSH threadripper" text in the prompt
```

Colors: `black red green yellow blue magenta cyan white`, any `bright-<color>`,
or a number from 0 to 255 (xterm-256). With `tint=ssh`, a local shell resets
the window to your profile's normal background on every prompt, which is what
restores it after you leave a remote session.

Environment variables:

| Variable | Effect |
|---|---|
| `WHEREAMI_NAME`, `WHEREAMI_COLOR`, `WHEREAMI_TINT`, `WHEREAMI_BACKGROUND`, `WHEREAMI_LABEL` | Override the config file for this shell. |
| `WHEREAMI_PROMPT=0` | Do not modify `PS1`. Put `\[$(whereami_tint)\]$(whereami_ps1)` in your own prompt instead. |
| `WHEREAMI_COLOR_ENABLED=0` | Plain text segment, no ANSI escapes. |
| `WHEREAMI_CONFIG` | Use a different config file path. The `disabled` flag lives next to it. |

Custom prompt example:

```sh
export WHEREAMI_PROMPT=0
source ~/.local/share/whereami-shell/whereami.sh
PS1='\[$(whereami_tint)\]$(whereami_ps1)\w \$ '
```

`whereami_tint` emits the window color escape (zero width, hence the `\[ \]`).
`whereami_ps1` prints the text label with its own trailing space, or nothing
when `label=off` or whereami is turned off.

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
