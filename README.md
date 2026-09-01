# claude-skills

Three general-purpose [Claude Code](https://docs.claude.com/en/docs/claude-code) skills.

| Skill | What it does |
|---|---|
| [`llm-council`](./skills/llm-council/) | Runs any decision past five advisors — Contrarian, First Principles, Expansionist, Outsider, Executor — who analyze it independently, peer-review each other anonymously, and get synthesized into one verdict by a chairman. Adapted from [Karpathy's LLM Council](https://github.com/karpathy/llm-council), but using Claude sub-agents with different thinking lenses instead of different models. No API keys, no setup. |
| [`cc-changelog`](./skills/cc-changelog/) | Fetches the latest Claude Code release notes and summarizes only what matters for *your* stack and role. Builds a profile once, then filters every future changelog through it. |
| [`fal-image-generator`](./skills/fal-image-generator/) | Generates images via [fal.ai](https://fal.ai) (FLUX family). Text-to-image, image-to-image with a reference, native custom dimensions (1K/2K/4K), WebP/JPG/PNG output. Needs a `FAL_KEY`. |

Skill documentation is in German; the skills themselves answer in whatever language you write in.

## Install

As a plugin (recommended — Claude Code keeps it updated):

```
/plugin marketplace add josefheld/claude-skills
/plugin install claude-skills@josefheld
```

Or symlink the skills straight into `~/.claude/skills/`:

```bash
git clone https://github.com/josefheld/claude-skills.git
cd claude-skills
./install.sh
```

`./install.sh` symlinks by default, so `git pull` updates the skills with no re-install. Use `--copy` for real copies, `--dry-run` to preview, `--help` for the rest.

## Setup

`llm-council` and `cc-changelog` work immediately — they run entirely inside Claude Code.

`fal-image-generator` needs one-time setup, because it calls a paid external API:

```bash
bash skills/fal-image-generator/setup.sh
```

That creates a Python venv, installs the deps, and runs an offline self-test. `install.sh` triggers it automatically on first link. Get a key at [fal.ai/dashboard/keys](https://fal.ai/dashboard/keys), then put `export FAL_KEY=...` in your shell profile. Every generation costs money — see [fal.ai/pricing](https://fal.ai/pricing).

## Where API keys go

In your shell profile (`~/.zshrc`, `~/.bashrc`), never in this repo. Not in a `.env` next to the code, not in any directory that gets committed, deployed or synced. The `.gitignore` here also excludes `.env*`, but that is a second line of defence — the file should not exist in the first place.

## License

MIT — see [LICENSE](./LICENSE).
