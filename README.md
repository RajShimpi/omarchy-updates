# Updates

One Omarchy bar widget for every update on your machine: Omarchy itself,
system packages (pacman), AUR apps, mise dev tools, git-managed shell plugins
and git themes. It checks in the background, tells you once when something
new arrives, and updates **only after you confirm**, in a terminal you can
watch.

Plugin id: `techspawn.updates`

## What it does

- **Bar:** an update icon with a badge showing how many updates are waiting.
  The badge turns red when a new Omarchy version is out. Click it to open the
  panel.
- **Panel:** one row per source, each with its own **Update…** button, plus
  **Update all…** and **Check now**. Click a row to see what is waiting:
  package versions, or the new commits for a plugin or theme.
  - **Omarchy:** shows the new version, with a link to the release notes.
  - **System & apps (pacman):** what `checkupdates` reports.
  - **AUR apps:** `yay -Qua`, minus packages that have moved to a repo.
  - **Dev tools (mise):** `mise outdated`, checked the same way Omarchy
    updates (without mise's release-age cooldown), so the list matches what
    an update installs.
  - **Shell plugins:** every plugin in `~/.config/omarchy/plugins` that is a
    git checkout. Each one is fetched (in parallel) from the branch it
    tracks. Plugins without a git remote are counted as "not from git" and
    left alone.
  - **Themes:** git themes from `omarchy theme extras` (hidden when you have
    none).
- **Nothing updates without your OK.** Every update starts with a
  confirmation card in the panel, then runs in a floating terminal, where you
  see the output and answer Omarchy's own questions.
- After an update the list checks itself again. If you reboot from Omarchy's
  prompt instead, it checks again right after you log back in.
- Errors stay visible: offline mirrors, an unreachable AUR, plugin remotes
  that don't answer, and plugins that need a manual update are shown on their
  row instead of silently counting as "up to date".

### Notifications

The background service checks every `checkHours` and sends one notification
when updates show up that weren't there before. Click it to open the panel.
An update you've already been told about isn't announced again, even if a
check in between failed because you were offline. With two monitors there are
two bars, but only the service notifies, so you get each notification once.

### Keyboard

When the panel is open:

- `r` checks now
- `Enter` confirms the update card, `Esc` cancels it or closes the panel
- `Tab` moves to the next bar panel

## Install

```bash
omarchy plugin add https://github.com/RajShimpi/omarchy-updates
omarchy plugin enable techspawn.updates
omarchy bar put techspawn.updates
```

You can also use **Install plugin** in the Omarchy menu with the repository URL.

## Remove

```bash
omarchy plugin remove techspawn.updates
```

To clear what it left behind (the cached list, lock files, notification
state, saved plugin patches and your settings):

```bash
rm -rf ~/.cache/omarchy/updates.json ~/.cache/omarchy/updates*.lock \
  ~/.local/state/omarchy/updates-notified.json ~/.local/state/omarchy/updates-patches \
  ~/.config/omarchy/updates.json
```

## Settings

Optional. Create `~/.config/omarchy/updates.json`; the plugin never writes it.
Missing keys use these defaults:

```json
{
  "checkHours": 6,
  "notify": true
}
```

| Key | Meaning |
| --- | --- |
| `checkHours` | Hours between background checks (whole number). The service looks every 30 minutes, so `0` means every 30 minutes. Opening the panel also checks when the list is older than 30 minutes. |
| `notify` | `false` turns notifications off. The badge and panel still update. |

## What runs with privileges, and when

Checking never needs your password and never changes anything:

- `checkupdates` syncs a private copy of the package database in a temporary
  folder, not the real one
- `yay -Qua`, `mise outdated` and `omarchy-update-available` only read
- `git fetch` downloads plugin and theme commits without changing your files

Privileges are used only inside the terminal that opens after you click
**Yes, update**, and only by Omarchy's own commands:

| You choose | What runs | Password |
| --- | --- | --- |
| System & apps, or Update all with packages waiting | `omarchy-update`: snapshot, keyring, `pacman -Syu`, migrations, AUR apps, mise tools, then it may offer a reboot and restarts the shell. It asks "Continue with update?" itself before it starts. | yes (sudo) |
| AUR apps | `omarchy-update-aur-pkgs` (`yay -Sua`) | yes (sudo, to install) |
| Dev tools | `omarchy-update-mise` (`mise up`) | no |
| Shell plugins | the reviewed git update described below | no |
| Themes | `git pull --ff-only` in each git theme | no |

**Update all** runs plugins first, then themes, then Omarchy's full update,
and skips Omarchy's full update when no packages, apps or dev tools are
waiting. The plugin never edits sudoers, never stores your password, never
runs a downloaded script, and never updates anything from the background
service.

## How plugin updates stay safe

Plugins are code that runs inside your shell, so each one is reviewed before
it moves:

1. The plugin's remote is fetched and the exact commit is pinned.
2. The terminal lists the new commits and a file summary, and offers the full
   diff (quitting the pager with `q` is safe).
3. You answer yes or no per plugin. No means nothing changes.
4. The plugin fast-forwards to exactly the commit you reviewed, never to
   something fetched later. A plugin with commits of its own, or whose
   upstream rewrote its history, is never force-moved: the panel lists it as
   "update by hand".
5. The new version must pass `omarchy plugin validate`, or it is rolled back.

**Your own edits to a plugin are never dropped silently.** If you have
uncommitted changes in a plugin (a local fix, say), the check works out
beforehand what the update will do with them, and the panel and terminal tell
you:

- **kept:** your changes don't touch what the update changes; they stay
- **already in this version:** upstream made the same change
- **clash:** you and upstream changed the same lines. The terminal asks
  separately whether to update anyway. If you say yes, your changes are set
  aside rather than applied: they stay in the plugin's `git stash` and are
  saved as a patch in `~/.local/state/omarchy/updates-patches/`, so you can
  re-apply what you still need.

A copy of your changes is saved as a patch before any plugin with local edits
is updated. If anything fails halfway, the plugin goes back to exactly how it
was, edits included.

This deliberately doesn't use `omarchy plugin update`: quitting its diff
pager early makes `git diff` exit with SIGPIPE, and its `set -e` then stops
before the yes/no question.

## Dependencies

All part of a standard Omarchy install:

- Omarchy's commands: `omarchy-update`, `omarchy-update-available`,
  `omarchy-update-aur-pkgs`, `omarchy-update-mise`, `omarchy-theme-extras`,
  `omarchy-plugin-validate`, `omarchy-notification-send`,
  `omarchy-launch-floating-terminal-with-presentation`
- `checkupdates` (pacman-contrib), `jq`, `gum`, `flock` and `timeout`
- `git` 2.40 or newer (for `git merge-tree --merge-base`)

Optional: `yay` for AUR apps and `mise` for dev tools. Without them, those
rows stay empty.

## How it works

- `scripts/updates` is a bash script. `check` builds the list and writes it
  to `~/.cache/omarchy/updates.json`, `auto` is what the service runs, and
  `run` is what the terminal runs after you confirm.
  `scripts/updates run --dry-run all` shows what an update would do without
  changing anything. `OMARCHY_NO_NOTIFY=1` prints notifications instead of
  sending them.
- Checks take a lock, so two bars and the service never check at the same
  time; whoever comes second reuses the result. Only one update can run at a
  time, and the panel shows "Updating in a terminal…" while it does.

## License

MIT. See [LICENSE](LICENSE). Not affiliated with Omarchy, Arch Linux, the AUR
or mise.
