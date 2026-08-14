# Homebrew Watchtower

Grouped, scheduled Homebrew updates for macOS—with explicit boundaries between unattended updates and software that requires a human at the keyboard.

Homebrew Watchtower uses ordinary user-level `launchd` jobs. It never runs Homebrew as root and does not leave a privileged daemon resident. Its persistent runner and group policy are root-owned, while Homebrew, logs, state, caches, and scheduled jobs run as the installing user.

## Why?

Homebrew can tell you what is outdated, but a single blanket upgrade schedule is not ideal:

- Security-sensitive software should be checked frequently.
- Development tools may need a slower cadence to avoid surprise breakage.
- GUI applications can quit or restart during upgrades.
- VPNs, system extensions, and package installers may require authorization.
- Two update jobs should never modify the Homebrew installation simultaneously.

Watchtower groups packages by policy and schedule, serializes update runs, records results, and leaves interactive upgrades for a terminal session.

## Install

```bash
brew tap johnseth97/brew-watchtower
brew trust --formula johnseth97/brew-watchtower/brew-watchtower
brew install johnseth97/brew-watchtower/brew-watchtower
brew-watchtower setup
```

`setup` requests administrator authorization to install the protected runtime under `/Library/Application Support/Homebrew AutoUpdate`. It creates a `security` group and schedules it daily at 09:30.

If `~/.config` already exists, installation also seeds
`~/.config/brew-watchtower/config` when that file does not exist. It never
creates `~/.config` and never overwrites an existing user config.

Choose another initial time with:

```bash
brew-watchtower setup 4 30
```

## Quick start

Add Tailscale as an interactive security update. Scheduled runs will detect and report an update; a terminal run can install it and display any macOS authorization prompt:

```bash
brew-watchtower add security cask tailscale-app interactive
```

Add Firefox for unattended updates:

```bash
brew-watchtower add security cask firefox auto
```

Create and schedule a development-tools group:

```bash
brew-watchtower add dev-tools formula git auto
brew-watchtower add dev-tools formula ripgrep auto
brew-watchtower schedule dev-tools 5 0
```

Inspect and run groups:

```bash
brew-watchtower groups
brew-watchtower list security
brew-watchtower check security
brew-watchtower run security
brew-watchtower status security
```

## Shell status blurb and Brewfile drift

Watchtower can print a compact, actionable status line when a shell starts. The
blurb only reads the small Watchtower status files; it never invokes Homebrew,
Git, or the network at shell startup.

Create the user-owned configuration once if installation did not seed it:

```bash
brew-watchtower config init

# Discover the exact path and effective settings.
brew-watchtower config path
brew-watchtower config show
```

Then opt in from `.zshrc` near the top, after `PATH` makes Homebrew available:

```zsh
brew-watchtower blurb
```

The default config shows only actionable state: failed groups, pending
interactive upgrades, or Brewfile drift.

```ini
# actionable prints only failures, pending interactive updates, or drift.
# Use always for a last-check heartbeat, or never to silence it.
blurb=actionable

# Any plain text, emoji, or Nerd Font glyphs are accepted.
prefix=⛫ Watchtower

# Evaluated during Watchtower check/run, never during shell startup.
detect_brewfile_drift=1
brewfile=~/.dotfiles/macos/Brewfile

# Optional generated machine snapshot; never replaces the curated Brewfile.
export_brewfile=0
export_path=~/.config/brew-watchtower/Brewfile.generated

# Disabled by default. During a Watchtower check/run, repair detected drift by
# snapshotting the configured Brewfile and regenerating it from Homebrew.
auto_fix_brewfile_drift=0
# Keep the newest N Watchtower-created backups (0 keeps all); optionally prune
# anything older than N days (0 disables age pruning).
brewfile_backup_keep=5
brewfile_backup_max_age_days=0
```

Drift checks and generated exports run during a scheduled Watchtower
`check`/`run`, not during shell startup. An export is always written to the
separate `export_path` (default: `~/.config/brew-watchtower/Brewfile.generated`)
and never overwrites the curated `brewfile` path.

Set `auto_fix_brewfile_drift=1` to repair detected drift at the end of a
Watchtower `check` or `run`. It is intentionally **not** a global Homebrew hook:
ordinary `brew install`, `upgrade`, or `uninstall` commands do not trigger it.
The repair uses the same backup-first behavior as `drift fix`; retention applies
only to sibling files named `Brewfile.backup-*`; use that name pattern exclusively for Watchtower backups.

Run a manual, no-update drift check at any time:

```bash
brew-watchtower drift
```

It runs `brew bundle check` against the configured Brewfile, records the result
for `brew-watchtower blurb`, and exits nonzero when the manifest does not match.
It does not run `brew update`, modify packages, or inspect Watchtower groups.

To replace a drifted Brewfile with Homebrew's current bundle, use:

```bash
brew-watchtower drift fix
```

This first preserves the curated file beside it as a timestamped sibling such as
`Brewfile.backup-20260813-180000`, then runs `brew bundle dump --force` into the
configured `brewfile`. This is a machine snapshot, so review it before treating
it as your curated cross-machine manifest. `drift fix --clobber` skips the
backup. To put a saved file back, pass its filename (not a path):

```bash
brew-watchtower drift restore Brewfile.backup-20260813-180000
```

Restore also creates a timestamped backup of the currently active Brewfile.

Remove an item:

```bash
brew-watchtower remove security firefox
```

## Commands

| Command | Purpose |
|---|---|
| `brew-watchtower groups` | List configured groups and item counts |
| `brew-watchtower list [GROUP]` | List all items or one group’s contents |
| `brew-watchtower add GROUP TYPE TOKEN [MODE]` | Add or replace a group entry |
| `brew-watchtower remove GROUP TOKEN` | Remove an entry |
| `brew-watchtower check GROUP` | Refresh metadata and report outdated entries |
| `brew-watchtower run GROUP` | Upgrade eligible entries |
| `brew-watchtower status [GROUP]` | Show last-run state and pending interactive items |
| `brew-watchtower drift` | Check the entire configured Brewfile without `brew update` or group processing |
| `brew-watchtower drift fix [--clobber]` | Dump current Homebrew state into the configured Brewfile, saving a timestamped backup unless clobbered |
| `brew-watchtower drift restore BACKUP` | Restore a timestamped sibling backup while preserving the current file |
| `brew-watchtower blurb` | Print a fast, actionable shell-start status line |
| `brew-watchtower config init` | Create a missing default user config |
| `brew-watchtower config show` | Print effective user config values |
| `brew-watchtower config path` | Print the user config path |
| `brew-watchtower schedule GROUP HOUR MINUTE` | Create or replace a daily schedule |
| `brew-watchtower setup [HOUR [MINUTE]]` | Install or refresh the protected runtime |

### Shell completion

Bash and Zsh completions install with the formula. Start a new shell after
installation, or reload completion support (`autoload -Uz compinit && compinit`
in Zsh). Tab completion covers top-level commands, config and drift subcommands, package
types/modes, timestamped Brewfile backups, and existing Watchtower group names. Completion queries group names
only; it does not update Homebrew.

Full documentation is included:

```bash
man brew-watchtower
```

## Update modes

### `auto`

The package may be upgraded by a scheduled background run. Use this only when unattended installation and any associated application restart are acceptable.

### `interactive`

Background runs detect and report the update but do not install it. Run the group from a terminal to perform the upgrade:

```bash
brew-watchtower run security
```

Re-adding a token updates its existing policy rather than creating a duplicate:

```bash
brew-watchtower add security cask tailscale-app auto
```

## Scheduling

Watchtower uses `StartCalendarInterval` in per-user LaunchAgents. It is not a continuously running service. Each group can have its own daily time:

```bash
brew-watchtower schedule security 9 30
brew-watchtower schedule dev-tools 5 0
```

Inspect a loaded job with:

```bash
launchctl print "gui/$(id -u)/local.homebrew-autoupdate.security"
```

## Logs and status

```bash
tail -100 "$HOME/Library/Logs/Homebrew AutoUpdate/security.log"
tail -100 "$HOME/Library/Logs/Homebrew AutoUpdate/launchd-security.log"
brew-watchtower status security
```

## Files and ownership

| Path | Ownership | Mode |
|---|---|---:|
| `/Library/Application Support/Homebrew AutoUpdate/bin/autoupdate` | `root:wheel` | `0755` |
| `/Library/Application Support/Homebrew AutoUpdate/groups/*.conf` | `root:wheel` | `0644` |
| `~/Library/LaunchAgents/local.homebrew-autoupdate.*.plist` | installing user | `0644` |
| `~/Library/Logs/Homebrew AutoUpdate` | installing user | `0700` |
| `~/Library/Application Support/Homebrew AutoUpdate` | installing user | `0700` |
| `~/Library/Caches/Homebrew AutoUpdate` | installing user | `0700` |

Group files contain tab-delimited declarative data. They are never sourced or evaluated as shell code.

## Security model

- Checks and upgrades refuse to run as root.
- Adding, removing, and scheduling entries uses the protected runtime and requests `sudo` authorization.
- No administrator password or sudo timestamp is stored.
- A global lock prevents overlapping Homebrew jobs.
- Package tokens, modes, types, and group names are validated before use.
- Homebrew is invoked through the fixed path `/opt/homebrew/bin/brew` with a minimal `PATH`.
- Automated runs disable Homebrew analytics and automatic cleanup.
- Logs and state are private to the installing user.

Root ownership protects Watchtower’s persistent policy from silent modification by an ordinary user process. It cannot prevent software already running as that user from invoking Homebrew directly or creating a separate LaunchAgent.

Homebrew casks may execute vendor installers and package scripts. Automatic mode is therefore a trust decision, not a sandbox.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and supported versions.

## Development

Install the current checkout as a user-local development build (no sudo and no
changes to Homebrew-managed files):

```bash
make install
# Use another executable name or user-local prefix when needed:
make install DEV_NAME=brew-watchtower-dev
make install PREFIX="$HOME/.local"
```

The default launcher is `~/.local/bin/brew-watchtower-dev`; its isolated runtime
and local completion files live in `~/.local/libexec/brew-watchtower-dev`.
`make uninstall` removes only that development installation. Ensure
`~/.local/bin` precedes Homebrew on `PATH` while testing it.

```bash
make verify-release VERSION=0.5.1
```

The release archive is deterministic. `verify-release` rebuilds the archive and
fails unless the requested version, archive filename, formula URL, and formula
SHA-256 all agree.

For a release, update the version in `bin/brew-watchtower`, formula URL, formula
test expectation, and manpage; then generate the archive, copy its SHA-256 into
the formula, and verify again:

```bash
make dist VERSION=X.Y.Z
cat dist/brew-watchtower-X.Y.Z.tar.gz.sha256
# Update Formula/brew-watchtower.rb with that SHA-256.
make verify-release VERSION=X.Y.Z
git add -A && git commit -m "Release brew-watchtower vX.Y.Z"
git push origin main
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push origin vX.Y.Z
```

Only tag the commit that passes `make verify-release VERSION=X.Y.Z`. The tag
push runs the release workflow, which rebuilds and verifies the same source
before uploading the archive.

## License

MIT. See [LICENSE](LICENSE).

## Author

[github.com/johnseth97](https://github.com/johnseth97)
