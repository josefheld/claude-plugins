# fal-image-generator

Image generation via [fal.ai](https://fal.ai) from inside Claude Code: text-to-image, image-to-image with a reference, real custom dimensions instead of a fixed aspect-ratio enum, and WebP, JPG or PNG output. FLUX family.

**Every call costs money.** Current rates: [fal.ai/pricing](https://fal.ai/pricing).

## Install

```
/plugin marketplace add josefheld/claude-plugins
/plugin install fal-image-generator@josefheld
```

Then the one-time setup, or simply ask Claude to run the skill's `setup.sh`:

```bash
bash "$(dirname "$(readlink -f ~/.claude/plugins/*/fal-image-generator*/skills/fal-image-generator/SKILL.md)")/setup.sh"
```

It creates the venv, installs the dependencies, checks the key, and runs an offline self-test that makes no API calls.

Get a key at [fal.ai/dashboard/keys](https://fal.ai/dashboard/keys) and put it in your shell profile:

```bash
export FAL_KEY="..."   # ~/.zshrc, never in this repo
```

Never in a `.env` next to the code, not in any directory that gets committed, deployed or synced. `setup.sh` prints only the *length* of the key, never a prefix, so the value stays out of terminal scrollback, CI logs and agent transcripts.

The venv lives at `~/.cache/fal-image-generator/venv`, deliberately outside the plugin: a marketplace install is unpacked into a versioned cache directory that is replaced on every update, and a venv next to the code would be wiped each time.

## Use

Ask in plain language and the skill assembles the call:

```
generate a 16:9 hero image for the article about legacy JS audits, muted blues, no text
take this screenshot as a reference and turn it into a clean illustration
```

Or call the script directly. Two paths, then every call is a one-liner:

```bash
PY="${XDG_CACHE_HOME:-$HOME/.cache}/fal-image-generator/venv/bin/python3"
GEN=~/.claude/plugins/marketplaces/josefheld/plugins/fal-image-generator/skills/fal-image-generator/scripts/generate.py

"$PY" "$GEN" --prompt "a lighthouse in fog, cinematic" --output hero.webp --aspect 16:9 --resolution 1K
"$PY" "$GEN" --prompt "same scene, warmer" --reference hero.webp --output hero-warm.webp --strength 0.6
"$PY" "$GEN" --self-test     # offline dimension checks, no API calls, no cost
```

Always go through `$PY`, never the script's shebang: the dependencies are in the venv, not in the system Python. If `$PY` does not exist, setup has not run.

## Configure

### Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `--prompt` | yes | — | text prompt |
| `--output` | yes | — | output path, the format is inferred from the extension |
| `--reference` | — | — | reference image, local path or URL. Exactly one: fal endpoints accept a single `image_url` |
| `--resolution` | — | `1K` | `1K`, `2K`, `4K` |
| `--aspect` | — | `1:1` | `1:1`, `16:9`, `9:16`, `4:5`, `3:4` |
| `--format` | — | from the extension | `png`, `webp`, `jpg` |
| `--quality` | — | `90` | 1-100 for WebP and JPG, ignored for PNG |
| `--model` | — | `flux-dev` | `flux-dev`, `flux-schnell`, `flux-pro` |
| `--strength` | — | `0.85` | only with `--reference` on flux-dev: 0 stays close to the original, 1 is free |
| `--seed` | — | — | reproducible output |
| `--no-resize` | — | `false` | skips post-processing, for debugging |
| `--self-test` | — | — | offline checks of the dimension logic, no API calls |

### Models

| Alias | Endpoint | Character |
|---|---|---|
| `flux-dev` (default) | `fal-ai/flux/dev` | price/performance, native `{width,height}`, 28 steps |
| `flux-schnell` | `fal-ai/flux/schnell` | drafts, 4 steps, roughly 10x cheaper, visibly coarser |
| `flux-pro` | `fal-ai/flux-pro/v1.1-ultra` | best quality, only an `aspect_ratio` enum, no free-form dimensions |

With `--reference` the skill switches to the image-to-image counterpart by itself: `fal-ai/flux/dev/image-to-image` for flux-dev, `fal-ai/flux-pro/kontext` for flux-pro (instruction-based editing), and flux-schnell falls back to flux-dev because fal has no schnell i2i endpoint.

### Environment

| Variable | Default | Purpose |
|---|---|---|
| `FAL_KEY` | — | required, the API key |
| `FAL_IMAGE_VENV` | `~/.cache/fal-image-generator/venv` | move the venv elsewhere |

### Keeping the bill down

- Iterate on `flux-schnell`, switch to `flux-dev` only for the final image.
- `--resolution 1K` is enough for a 1280x720 blog hero. Higher resolution costs more.
- Set `--seed` when you want to reproduce a result instead of paying for the same image twice.

## License

MIT, see the [repo LICENSE](../../LICENSE).
