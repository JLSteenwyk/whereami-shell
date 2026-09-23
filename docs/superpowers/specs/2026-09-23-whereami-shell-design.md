# whereami-shell design

Date: 2026-09-23

## Purpose

Make the machine that is running the current shell obvious in the prompt, so a
user who SSHes between a laptop, a workstation, and remote servers does not run
a command on the wrong computer. The prompt shows a per-machine name and color
plus an `SSH` or `LOCAL` marker. A `whereami` command gives an explicit check.

The name and color always describe the machine running the shell, never the
machine where the terminal window was opened. Because configuration lives on
each machine's own disk, this property holds through nested SSH hops and tmux.

## Scope (v1)

- Bash only (works on Bash 3.2, the macOS default, and newer).
- Per-machine config file, `~/.config/whereami/config`, with `name` and `color`.
- Environment overrides `WHEREAMI_NAME` and `WHEREAMI_COLOR`.
- SSH detection via `SSH_CONNECTION` / `SSH_CLIENT` / `SSH_TTY`, with a
  fallback that walks the parent process chain looking for `sshd`, so shells
  inside tmux (which may not inherit SSH variables) are still classified.
- Prompt segment `LOCAL name` or `SSH name` with ANSI color, prepended to the
  user's `PS1` by default. Users can opt out and place `$(whereami_ps1)`
  themselves.
- `whereami` command: prints name, hostname, session type, tmux state, color
  and config path. `whereami init NAME [COLOR]` writes the config file.
- `install.sh` that copies the script to `~/.local/share/whereami-shell` and
  appends a `source` line to `~/.bashrc`.

Out of scope for v1: zsh/fish support, per-directory names, remote config sync.

## Addendum (2026-09-23): on/off toggle and macOS menu bar app

- `~/.config/whereami/disabled` is a flag file. While it exists `whereami_ps1`
  prints nothing. The check runs on every prompt (one `stat`), so all open
  shells on the machine react at once. `whereami on|off|toggle` manage it.
- `macos/WhereAmI.swift` is a single-file AppKit app built with `swiftc`
  (`make app`, `make install-app`). It shows the name in the configured color
  as an `NSStatusItem`, toggles the same flag file, watches the config
  directory with a `DispatchSource` (plus a 3 s poll for in-place edits), and
  registers itself as a login item through `SMAppService`.
- The app reads the config with the same rules as the shell and uses
  `gethostname` so the derived default color matches the shell's.
- The flag is intentionally per machine so hiding the local prompt never hides
  the SSH marker on a remote host.

## Architecture

Single sourceable file `whereami.sh` with small functions, each testable on its
own by sourcing the file in a subshell:

| Function | Responsibility |
|---|---|
| `whereami_load_config` | Read config file and env overrides into `WHEREAMI_NAME`, `WHEREAMI_COLOR`. |
| `whereami_hostname` | Short hostname fallback for the name. |
| `whereami_default_color` | Deterministic color from the name when none is configured. |
| `whereami_is_ssh` | Return 0 when the shell is (transitively) inside an SSH session. |
| `whereami_in_tmux` | Return 0 when `TMUX` is set. |
| `whereami_color_code` | Map a color name or 0-255 number to an ANSI SGR sequence. |
| `whereami_ps1` | Emit the colored prompt segment with `\[ \]` guards for PS1. |
| `whereami` | The user-facing command. |

`bin/whereami` is a thin wrapper that sources `whereami.sh` and calls the
function, so the command also works from scripts and `ssh host whereami`.

## Config format

Plain `key=value` lines, parsed line by line (not sourced) so a stray command in
the file cannot execute:

```
name=threadripper
color=magenta
```

Colors: `black red green yellow blue magenta cyan white`, their `bright-`
variants, or an integer 0-255 (xterm-256). Unknown values fall back to the
derived default.

## Data flow

Shell starts -> `.bashrc` sources `whereami.sh` -> `whereami_load_config`
(config file, then env overrides, then hostname fallback) -> SSH state is
computed once and cached in `WHEREAMI_SESSION` -> `PS1` is prefixed with
`$(whereami_ps1)` unless `WHEREAMI_PROMPT=0`.

## Error handling

- Missing config file: silently fall back to hostname and derived color.
- Malformed lines: ignored.
- `ps` unavailable or unexpected output: process walk returns "not ssh"; the
  environment variable check still applies.
- Never `exit` from a sourced file; functions return non-zero instead.

## Testing

`tests/run.sh` is a small Bash test runner (no bats dependency). Each test file
sources `whereami.sh` in a controlled environment (temp `HOME`, cleared SSH
variables, fake `ps` on `PATH` where needed) and asserts on function output and
exit codes. `make test` runs them all.
