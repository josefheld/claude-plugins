# claude-plugins

`claude plugin update` has no `--all`. Updating twenty installed plugins means twenty commands. That is what `update-plugins` fixes, and it is one of four plugins in this [Claude Code](https://docs.claude.com/en/docs/claude-code) marketplace.

```
/plugin marketplace add josefheld/claude-plugins
/plugin install update-plugins@josefheld
```

Then `/update-plugins` walks the whole list for you:

```console
$ update-plugins.sh --dry-run
==> Refreshing marketplaces
--  cc-changelog@josefheld (dry-run)
--  code-review@claude-plugins-official (dry-run)
--  commit-commands@claude-plugins-official (dry-run)
--  fal-image-generator@josefheld (dry-run)
--  frontend-design@claude-plugins-official (dry-run)
--  llm-council@josefheld (dry-run)
--  playwright@claude-plugins-official (dry-run)
--  superpowers@superpowers-marketplace (dry-run)
--  update-plugins@josefheld (dry-run)

Dry-run beendet, nichts veraendert.
```

Drop `--dry-run` and it actually updates. Pick what you want:

| Plugin | Install | What it does |
|---|---|---|
| [`llm-council`](./plugins/llm-council/) | `/plugin install llm-council@josefheld` | Runs a decision past five advisors (Contrarian, First Principles, Expansionist, Outsider, Executor) who analyze it independently, peer-review each other anonymously, and get synthesized into one verdict by a chairman. Adapted from [Karpathy's LLM Council](https://github.com/karpathy/llm-council), using Claude sub-agents with different thinking lenses instead of different models. |
| [`cc-changelog`](./plugins/cc-changelog/) | `/plugin install cc-changelog@josefheld` | Fetches the latest Claude Code release notes and summarizes only what matters for your stack and role. Builds a profile once, then filters every future changelog through it. |
| [`fal-image-generator`](./plugins/fal-image-generator/) | `/plugin install fal-image-generator@josefheld` | Generates images via [fal.ai](https://fal.ai) (FLUX family). Text-to-image, image-to-image with a reference, native custom dimensions (1K/2K/4K), WebP/JPG/PNG output. |
| [`update-plugins`](./plugins/update-plugins/) | `/plugin install update-plugins@josefheld` | Refreshes every marketplace, then updates each installed plugin one by one, because `claude plugin update` has no `--all`. |

Separate plugins on purpose: you only pay the context cost of the ones you install.

## Setup

`llm-council`, `cc-changelog` and `update-plugins` work immediately. `update-plugins` needs `claude` and `node` on your PATH, nothing else.

`fal-image-generator` calls a paid external API and needs one-time setup:

```bash
bash "$(dirname "$(readlink -f ~/.claude/plugins/*/fal-image-generator*/skills/fal-image-generator/SKILL.md)")/setup.sh"
```

Or simply ask Claude to run the skill's `setup.sh` once. It creates a Python venv, installs the dependencies, checks the key, and runs an offline self-test. Get a key at [fal.ai/dashboard/keys](https://fal.ai/dashboard/keys), then add `export FAL_KEY=...` to your shell profile. Every generation costs money, see [fal.ai/pricing](https://fal.ai/pricing).

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
.claude-plugin/marketplace.json    the marketplace, lists all four plugins
plugins/<name>/
  .claude-plugin/plugin.json       the plugin manifest
  skills/<name>/SKILL.md           the skill itself
```

`update-plugins` deviates: its `SKILL.md` sits at the plugin root and it ships `scripts/`, because it is a real tool rather than a prompt document.

No plugin declares a `version`. That is deliberate: without one the commit SHA acts as the version, so every push reaches installed users. A `version` field would mean nothing updates until the number is bumped by hand. `claude plugin validate` warns about this, and the warning is safe to ignore here.

## License & attribution

MIT, see [LICENSE](./LICENSE).

`llm-council` is based on Andrej Karpathy's [LLM Council](https://github.com/karpathy/llm-council) methodology, popularized by [Ole Lehmann](https://x.com/itsolelehmann).

## About

These plugins come out of daily work with Claude Code on long-lived JavaScript and TypeScript codebases.

That is also the day job. [kigazon.com](https://kigazon.com/audit.html) runs fixed-price code audits for teams whose JS/TS codebase has been growing for more than three years, where changes have quietly become expensive and nobody can point at why. Three days, remote, a report short enough that management actually reads it.
