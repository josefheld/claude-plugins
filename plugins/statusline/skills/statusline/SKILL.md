---
name: statusline
description: Installs and configures the Claude Code statusline that ships with this plugin, including which segments appear, in which order, how wide the bars are, and at which percentage they turn yellow or red. Use this skill whenever the user wants to set up, change, reorder, trim or remove their statusline, for example "set up my statusline", "install the statusline", "show the cost in my statusline", "hide the rate limits", "my statusline is too long", "reorder the statusline", "remove the statusline", or the German equivalents "statusline einrichten", "statusline anpassen", "statusline kürzen", "was steht in meiner statusline", "statusline entfernen". Also use it when the statusline is misbehaving, for example a missing context bar, a missing cost, a wrong percentage, or a statusline that does not appear at all.
---

# Configurable statusline

The plugin ships `statusline-command.sh` plus an installer that points Claude
Code's `statusLine` setting at it. Because the setting points into the plugin
directory, every plugin update also updates the script. Nothing gets copied
into `~/.claude`.

## Prerequisite

`jq` must be on the PATH (`brew install jq`, `apt-get install jq`). Without it
the script prints nothing.

## Install

Run the installer. `${CLAUDE_PLUGIN_ROOT}` is set when the skill runs, so use
it verbatim:

```sh
sh "${CLAUDE_PLUGIN_ROOT}/scripts/install-statusline.sh"
```

It backs up `settings.json` first (`settings.json.bak-<timestamp>`), refuses to
touch the file if it is not valid JSON, and prints the resulting `statusLine`
entry.

`${CLAUDE_PLUGIN_ROOT}` points into `~/.claude/plugins/cache/<marketplace>/<plugin>/<sha>/`,
and that `<sha>` changes with every plugin update. The installer therefore
rewrites it to the stable `~/.claude/plugins/marketplaces/<marketplace>/plugins/<plugin>/`
before writing `settings.json`. Check the path it prints, and never hand-write
a cache path into `settings.json`. The statusline appears in the next session, not the current one, so tell
the user to restart Claude Code.

Variants:

| Command | Effect |
|---|---|
| `install-statusline.sh model,context,git` | only these segments, in this order |
| `install-statusline.sh --project` | writes `.claude/settings.json` in the current repo instead of the user settings |
| `install-statusline.sh --show` | prints the current `statusLine` entry |
| `install-statusline.sh --uninstall` | removes the `statusLine` entry again |

## Segments

Names go into `CC_STATUSLINE_SEGMENTS`, comma-separated. The list is also the
display order. A segment with no data prints nothing, so no placeholders
appear.

| Name | Shows |
|---|---|
| `model` | model, thinking mode (`T`), effort level |
| `context` | context window remaining, as a color bar |
| `cost` | session cost in USD |
| `limits` | 5h and 7d rate limits with reset times |
| `dir` | git repo root name, else the current directory |
| `git` | branch plus staged (`+N`) and modified (`~N`) counts |
| `worktree` | active worktree name |
| `duration` | session runtime as `HH:MM:SS` |
| `agent` | name of the running subagent |
| `session` | session name, if one is set |
| `style` | output style, unless it is `default` |
| `version` | `claude --version` |
| `codex` | `codex --version` |

Default is all of them. Unknown names are ignored rather than fatal.

## Knobs

| Variable | Default | Meaning |
|---|---|---|
| `CC_STATUSLINE_SEGMENTS` | all segments | which segments, in which order |
| `CC_STATUSLINE_BAR_WIDTH` | `8` | characters per bar |
| `CC_STATUSLINE_WARN` | `70` | percent used at which a bar turns yellow |
| `CC_STATUSLINE_CRIT` | `90` | percent used at which a bar turns red |
| `CC_STATUSLINE_TIME_FMT` | `%H:%M` | `date` format for the rate limit reset time; `%-I:%M%p` for 12h |

They go in front of the command in `settings.json`, which is what the installer
writes when segments are passed:

```json
{
  "statusLine": {
    "type": "command",
    "command": "CC_STATUSLINE_SEGMENTS=model,context,cost CC_STATUSLINE_BAR_WIDTH=12 sh /Users/you/.claude/plugins/marketplaces/josefheld/plugins/statusline/statusline-command.sh"
  }
}
```

To change only a knob without re-running the installer, edit that `command`
string in `settings.json` directly.

## When something is missing

1. **Nothing at all appears.** `jq` missing, or `disableAllHooks` is `true` in
   settings, or the workspace trust prompt was never accepted.
2. **Two segments are gone (`context` and `cost`).** That was the locale bug:
   `printf` and `awk` parse `62.4` through `LC_NUMERIC`, and a locale with a
   decimal comma rejects it. The script exports `LC_NUMERIC=C` for that reason.
   If it reappears, check whether something overrides it.
3. **`version` or `codex` make it feel slow.** Each spawns a process on every
   redraw. Drop them from the segment list.
4. **Anything else.** Feed the script a payload by hand and look at the output:

```sh
printf '%s' '{"model":{"display_name":"Opus 5"},"context_window":{"remaining_percentage":62.4}}' \
  | sh "${CLAUDE_PLUGIN_ROOT}/statusline-command.sh"
```

After editing the script, run its self-check:

```sh
sh "${CLAUDE_PLUGIN_ROOT}/test-statusline.sh"
```

## Credits

Based on [danielmackay/claude-code-statusline](https://github.com/danielmackay/claude-code-statusline).
