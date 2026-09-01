---
name: update
description: Refreshes every Claude Code marketplace and then updates each installed plugin one by one, because "claude plugin update" has no --all flag. Use this skill whenever the user wants to update their plugins, bring them up to date, or check whether any plugin is outdated, for example "update my plugins", "are my plugins current", "check for plugin updates", "what's outdated", or the German equivalents "update meine plugins", "plugins aktualisieren", "sind meine plugins aktuell". Also use it when the user only mentions refreshing marketplaces, since a marketplace refresh alone does not update the installed plugins.
---

# Bulk plugin update

## Why this skill exists

Two things are easy to confuse:

- `claude plugin marketplace update` only refreshes the **catalog**. The installed plugin version in the cache under `~/.claude/plugins/cache` stays untouched.
- `claude plugin update <plugin>` updates the **plugin itself**, but requires a plugin argument. There is no `--all` (as of 09/2026, open feature request in anthropics/claude-code).

The script handles both, in the right order: catalog first, then each plugin.

## How to run it

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/update-plugins.sh"
```

`${CLAUDE_PLUGIN_ROOT}` points at the directory this plugin is currently loaded from. Do not replace it with a fixed path: in a marketplace install the plugin lives in a versioned cache directory that changes with every update.

Useful options:

| Option | Effect |
| --- | --- |
| `--dry-run` | Only shows which plugins would be touched |
| `--only <name>` | A single plugin, with or without `@marketplace` |
| `--scope <scope>` | Pin to one scope: `user`, `project`, `local` or `managed` |
| `--no-marketplace` | Skip the catalog refresh |

If the user only wants to know whether anything is outdated, use `--dry-run`. It lists the candidates without changing anything.

## Reading the output

Each line is marked:

- `OK` updated
- `==` already current
- `!!` failed, with the error message indented below it
- `--` skipped

A `[scope: project]` or `[scope: local]` after a plugin name means it was not installed at user scope. That is normal, the script works through the scopes itself.

A count line follows at the end. Summarize the result for the user in a sentence or two rather than repeating the whole output. For failed plugins, name the plugin and the cause from its error message.

## After the run

If at least one plugin was updated, point the user at `/reload-plugins`. Without it the current session keeps running the old versions, and hooks and MCP servers still resolve to the old cache directory. Do not run `/reload-plugins` yourself, leave that to the user: a reload can invalidate the session's prompt cache and therefore cost tokens.

## When nothing is found

If the script aborts with "Keine Plugins erkannt", it prints the raw output of `claude plugin list --json`. The structure of that output has changed between Claude Code versions before. In that case adapt `scripts/list-plugin-ids.js` to the actual structure rather than patching the bash script.

## Known limits, not bugs

- Plugins that set a `version` field in their `plugin.json` only update when the author bumps that number. New commits without a bump change nothing, and `claude plugin update` correctly reports "already at the latest version" even though newer code sits in the repo. Without a `version` field the commit SHA acts as the version, so every change comes through.
- `@skills-dir`, `@synced` and `@inline` are skipped. Those plugins do not come from a marketplace, so `claude plugin update` cannot handle them.
- Plugins with a `command` source ask for confirmation on update. The script runs with `</dev/null` so it cannot hang, which means those plugins fail and need one manual update from a regular terminal, not from inside a Claude Code session.

## Self-update

When this plugin is itself installed from the marketplace, it appears in its own list and updates along with everything else. The running script keeps working out of the old cache directory, which is intended and not an error. The new version takes effect after `/reload-plugins` or on the next start.
