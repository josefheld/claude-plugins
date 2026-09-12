# claude-plugins

Five plugins for [Claude Code](https://docs.claude.com/en/docs/claude-code), in one marketplace. They are separate plugins on purpose: you only pay the context cost of the ones you install.

```
/plugin marketplace add josefheld/claude-plugins
/plugin install <plugin>@josefheld
```

## The plugins

| Plugin | What it does | Needs |
|---|---|---|
| [`statusline`](./plugins/statusline/) | One status line with model, context window, cost, both rate limits, git state and session runtime. Segments are configuration, not a code edit. | `jq`, one install command |
| [`update-plugins`](./plugins/update-plugins/) | Refreshes every marketplace, then updates each installed plugin one by one, because `claude plugin update` has no `--all`. | `claude`, `node` |
| [`llm-council`](./plugins/llm-council/) | Runs a decision past five advisors with incompatible thinking lenses, lets them peer-review each other anonymously, and has a chairman synthesize one verdict. One of the five runs on a foreign model so the council does not share a blind spot. | nothing, `codex` optional |
| [`cc-changelog`](./plugins/cc-changelog/) | Fetches the Claude Code release notes and filters every entry through your roles, stack and language. | nothing |
| [`fal-image-generator`](./plugins/fal-image-generator/) | Generates images via [fal.ai](https://fal.ai) (FLUX): text-to-image, image-to-image, real custom dimensions, WebP/JPG/PNG. Paid API. | `FAL_KEY`, `setup.sh` |

Each plugin's own README covers the two questions that matter: **how to use it**, and **what you can configure**. This page stays an index.

## Where API keys go

In your shell profile (`~/.zshrc`, `~/.bashrc`), never in this repo. Not in a `.env` next to the code, not in any directory that gets committed, deployed or synced. The `.gitignore` here also excludes `.env*`, but that is a second line of defence: the file should not exist in the first place.

## Working on these locally

Point a marketplace at your clone instead of at GitHub, then edits take effect on the next session with no push:

```bash
git clone https://github.com/josefheld/claude-plugins.git
claude plugin marketplace add ./claude-plugins
claude plugin install llm-council@josefheld
```

Validate before pushing:

```bash
claude plugin validate .
claude plugin details llm-council@josefheld     # component inventory and token cost
```

## Repo layout

```
.claude-plugin/marketplace.json    the marketplace, lists every plugin
plugins/<name>/
  .claude-plugin/plugin.json       the plugin manifest
  README.md                        usage and configuration
  skills/<name>/SKILL.md           the skill itself
```

Two plugins deviate, both because they ship a real tool rather than a prompt document. `update-plugins` puts its `SKILL.md` at the plugin root and adds `scripts/`. `statusline` adds `scripts/install-statusline.sh`, the `statusline-command.sh` that Claude Code runs on every redraw, and `test-statusline.sh` next to it.

No plugin declares a `version`. That is deliberate: without one the commit SHA acts as the version, so every push reaches installed users. A `version` field would mean nothing updates until the number is bumped by hand. `claude plugin validate` warns about this, and the warning is safe to ignore here.

One path rule for anything that writes into `settings.json` or keeps state: never point at `~/.claude/plugins/cache/<marketplace>/<plugin>/<sha>/`. That last element is the commit and it changes with every update. Use the marketplace clone at `~/.claude/plugins/marketplaces/<marketplace>/plugins/<plugin>/`, or a location outside the plugin entirely, the way `fal-image-generator` keeps its venv in `~/.cache`.

## License

MIT, see [LICENSE](./LICENSE). Third-party attribution sits in the README of the plugin it concerns.

## About

These plugins come out of daily work with Claude Code on long-lived JavaScript and TypeScript codebases.

That is also the day job. [kigazon.com](https://kigazon.com/audit.html) runs fixed-price code audits for teams whose JS/TS codebase has been growing for more than three years, where changes have quietly become expensive and nobody can point at why. Three days, remote, a report short enough that management actually reads it.
