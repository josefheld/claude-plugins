# update-plugins

A Claude Code skill that refreshes every marketplace and then updates each installed plugin one by one.

## The problem

Two commands are easy to confuse:

- `claude plugin marketplace update` only refreshes the catalog. The installed plugin version in the cache under `~/.claude/plugins/cache` stays untouched.
- `claude plugin update <plugin>` updates the plugin itself, but requires a plugin argument. There is no `--all` (as of 09/2026, see [#55415](https://github.com/anthropics/claude-code/issues/55415)).

So with many plugins installed, you end up running the second command once per plugin. This skill does both, in the right order.

If you don't need a skill for this: per-marketplace auto-update under `/plugin` > Marketplaces does the same thing automatically after session start. This repo is for people who want it on demand and deterministic.

## Installation

### Via the marketplace (recommended)

update-plugins ships from the [josefheld/claude-skills](https://github.com/josefheld/claude-skills) marketplace:

```bash
claude plugin marketplace add josefheld/claude-skills
claude plugin install update-plugins@josefheld
```

Invoke it as `/update-plugins`. Update it with `claude plugin update update-plugins@josefheld`, or let the plugin update itself, since it shows up in its own list.

`plugin.json` deliberately sets no `version` field, so the commit SHA serves as the version. Every push is an update, with no version number to maintain.

> Previously named `plugctl`. The marketplace carries the rename, so an installed copy follows along on the next `claude plugin marketplace update josefheld`.
>
> Before that it lived in the standalone `josefheld/plugctl` repo. If you still have that one, remove it first: `claude plugin uninstall plugctl@plugctl && claude plugin marketplace remove plugctl`.

### As a plain skill

No marketplace, but also no version tracking:

```bash
git clone https://github.com/josefheld/claude-skills.git
ln -s "$PWD/claude-skills/plugins/update-plugins" ~/.claude/skills/update-plugins
```

Invoke it as `/update-plugins`, update it with `git pull`. Note that installed this way it runs as an `@skills-dir` plugin, which the script skips, so it cannot update itself.

### Without Claude Code

The script also runs standalone:

```bash
./scripts/update-plugins.sh --dry-run
```

## Requirements

`claude` and `node` on your PATH. No `jq`, no npm dependencies.

## Options

| Option | Effect |
| --- | --- |
| `--dry-run`, `--check` | Only show which plugins would be touched |
| `--only <name>` | A single plugin, with or without `@marketplace` |
| `--scope <scope>` | Pin to one scope: `user`, `project`, `local` or `managed` |
| `--no-marketplace` | Skip the catalog refresh |

Exit codes: `0` all good, `1` some plugins failed, `2` aborted.

## Scopes

Without `--scope`, `claude plugin update` always assumes `user`. Plugins installed at project, local or managed scope then fail with `is not installed at scope user`. The script therefore tries the scopes in turn and notes in its output where it found the plugin. Genuine errors abort immediately, only a scope mismatch triggers the next attempt. Passing `--scope` turns the search off.

## Output

```
==> Refreshing marketplaces

OK  superpowers@ecc
      Updated superpowers@ecc to 2.0.0
==  claude-mem@thedotmack
OK  elements-of-style@superpowers-marketplace [scope: project]
      Updated to 0.4.0
!!  gstack@gstack-mp
      error: marketplace unreachable
--  my-helper@skills-dir (skipped, not a marketplace plugin)

3 updated, 1 already current, 1 failed, 1 skipped.
```

`OK` updated, `==` already current, `!!` failed, `--` skipped.

If anything was updated, it only takes effect in the running session after `/reload-plugins`.

## Known limits, not bugs

- Plugins that set a `version` field in their `plugin.json` only update when the author bumps that number. New commits without a bump change nothing, and `claude plugin update` correctly reports "already at the latest version" even though newer code sits in the repo. Without a `version` field the commit SHA acts as the version, so every change comes through.
- `@skills-dir`, `@synced` and `@inline` are skipped. Those plugins don't come from a marketplace, so `claude plugin update` can't handle them.
- Plugins with a `command` source ask for confirmation on update. The script runs with `</dev/null` so it can't hang, which means those plugins fail and need one manual update from a regular terminal.

## Why the parsing lives in Node

The structure of `claude plugin list --json` has already changed between Claude Code versions. `scripts/list-plugin-ids.js` walks the tree and collects anything that looks like a plugin entry, rather than relying on a fixed path. If it recognizes nothing, the script prints the raw output so you can see the actual structure.

## License

MIT
