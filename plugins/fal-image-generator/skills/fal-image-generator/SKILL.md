---
name: fal-image-generator
description: |
  Generates images via fal.ai (FLUX family) with configurable
  resolution, aspect ratio, output format, and reference image support.
  Triggered both directly by the user and by other skills that need
  images (e.g. blog hero, inline graphic).

  MANDATORY TRIGGERS: "fal-image-generator", "generate image",
  "Bild generieren" / "generate an image", "erstell mir ein Bild" /
  "make me an image", "Bild erzeugen mit fal" / "generate an image
  with fal", "Image-to-Image", "FLUX".

  STRONG TRIGGERS: "ich brauche ein Bild von X" / "I need an image
  of X", "Hero-Bild für Y" / "hero image for Y", "Illustration für Z"
  / "illustration for Z", "Social-Media-Bild" / "social media image",
  "Thumbnail erstellen" / "create a thumbnail", "AI-generiertes Bild"
  / "AI-generated image", "make me an image of", "create image",
  "image of X for my blog/post/article".

  PROACTIVE USE: When another skill needs an image, this is the
  default generator. Even if the user just says "und dazu ein
  passendes Bild" / "and a matching image for that" in the middle of
  another workflow, use this skill.

  Do NOT trigger for: pure editing of existing local images (crop,
  resize, filter; Pillow/ImageMagick handle that directly, no API,
  no cost), image analysis or OCR (not this tool's purpose),
  vector/logo design (FLUX is raster, use other tools for vectors),
  stock photo search (a search tool, not generation).
metadata:
  version: 3.0.0
  provider: fal.ai
---

# fal Image Generator

Generates images via [fal.ai](https://fal.ai). The default model is **FLUX.1 [dev]** (`fal-ai/flux/dev`): good price/performance ratio and **native custom dimensions**, meaning you get exactly the pixel dimensions you order.

## Models

| Alias | Endpoint | Character |
|---|---|---|
| `flux-dev` **(Default)** | `fal-ai/flux/dev` | Price/performance. Native `image_size {width,height}`. 28 steps. |
| `flux-schnell` | `fal-ai/flux/schnell` | Drafts and iterations. 4 steps, significantly cheaper, visibly coarser. |
| `flux-pro` | `fal-ai/flux-pro/v1.1-ultra` | Best quality. Only an `aspect_ratio` enum, no free-form dimensions. |

With `--reference`, the skill automatically switches to the image-to-image counterpart:

| Alias | i2i endpoint | Control |
|---|---|---|
| `flux-dev` | `fal-ai/flux/dev/image-to-image` | `--strength` (0 = like the original, 1 = free) |
| `flux-schnell` | *(falls back to flux-dev)* | no dedicated i2i endpoint at fal |
| `flux-pro` | `fal-ai/flux-pro/kontext` | instruction-based editing |

## Cost Awareness

**Every call costs money.** Depending on the model, fal bills per megapixel or per image. Rates change, so this document deliberately does not contain frozen numbers.

👉 Current prices: **https://fal.ai/pricing**

Check before a bulk run (e.g. batch articles). Rules of thumb that hold regardless of the rate:

- `flux-schnell` is ~10x cheaper than `flux-dev`: use it for draft iterations, switch to `flux-dev` only for the final result
- Higher resolution costs more. `--resolution 1K` is enough for a 1280×720 blog hero
- Set `--seed` if you want to reproduce a result: saves repeat calls

---

## Setup (one-time)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/fal-image-generator/setup.sh"
```

`setup.sh` creates the venv, installs dependencies, checks the API key, and runs the offline self-test.

**The venv lives outside the plugin**, at `~/.cache/fal-image-generator/venv`. That is deliberate: a marketplace install unpacks the plugin into a versioned cache directory that is replaced on every update, so a venv sitting next to the code would be wiped by each update. Override the location with `FAL_IMAGE_VENV` if you need to.

Manually, if needed:
```bash
python3 -m venv ~/.cache/fal-image-generator/venv
~/.cache/fal-image-generator/venv/bin/pip install -r "${CLAUDE_PLUGIN_ROOT}/skills/fal-image-generator/scripts/requirements.txt"
export FAL_KEY="your-key-here"   # make it permanent in ~/.zshrc
```

## How to invoke it

Two paths matter. Set them once, then every example below is a one-liner:

```bash
PY="${XDG_CACHE_HOME:-$HOME/.cache}/fal-image-generator/venv/bin/python3"
GEN="${CLAUDE_PLUGIN_ROOT}/skills/fal-image-generator/scripts/generate.py"
```

Always call the script through `$PY`, never through its shebang: the dependencies live in the venv, not in the system Python. If `$PY` does not exist, setup has not run yet.

### Key Handling

`FAL_KEY` belongs in `~/.zshrc`, **not** in this skill directory, not in a `.env` next to the code, not in any directory that ever gets deployed or synced. The `.gitignore` at the repo root additionally ignores `.env*`, but that is belt and suspenders: the file should not exist there in the first place.

`setup.sh` deliberately prints only the *length* of the key, never a prefix: otherwise the value ends up in terminal scrollback, in CI logs, and in agent transcripts.

---

## Parameters (CLI)

| Parameter | Required | Default | Description |
|---|---|---|---|
| `--prompt` | ✅ | — | Text prompt for the image |
| `--output` | ✅ | — | Path for the output file (format is inferred from the extension) |
| `--reference` | — | — | Reference image (local path or URL). **Only 1**: fal endpoints accept exactly one `image_url` |
| `--resolution` | — | `1K` | `1K` / `2K` / `4K` |
| `--aspect` | — | `1:1` | `1:1` / `16:9` / `9:16` / `4:5` / `3:4` |
| `--format` | — | from output extension | `png` / `webp` / `jpg` |
| `--quality` | — | `90` | 1-100 for WebP/JPG (PNG ignores it) |
| `--model` | — | `flux-dev` | `flux-dev` / `flux-schnell` / `flux-pro` |
| `--strength` | — | `0.85` | Only with `--reference` on flux-dev: 0 = close to the original, 1 = free |
| `--seed` | — | — | Reproducible output |
| `--no-resize` | — | false | Skips post-processing (debug) |
| `--self-test` | — | — | Offline checks of the dimension logic, **no API calls, no cost** |

---

## Examples

### Text-to-image (default)
```bash
"$PY" "$GEN" \
  --prompt "Minimalist tech illustration on dark navy background, golden geometric lines, abstract circuit pattern" \
  --output hero.webp \
  --resolution 2K \
  --aspect 16:9 \
  --quality 85
```

### Image-to-image with reference
```bash
"$PY" "$GEN" \
  --prompt "Same style, but with focus on cloud architecture instead" \
  --reference existing-hero.webp \
  --strength 0.7 \
  --output new-hero.webp \
  --resolution 2K \
  --aspect 16:9
```

### Cheap mode for drafts/iterations
```bash
"$PY" "$GEN" \
  --prompt "Quick draft" \
  --output draft.png \
  --model flux-schnell
```

### Reproducible
```bash
"$PY" "$GEN" --prompt "..." --output a.webp --seed 42
```

---

## How resolution and aspect ratio actually work

In many image skills, `--aspect` and `--resolution` are just **prompt hints** plus a crop afterward: you pay for a 1:1 image and throw away ~44% of the pixels. Not here:

1. **`flux-dev` / `flux-schnell`** get `image_size: {width, height}` natively. If you order 16:9 @ 2K, fal generates 1920×1080 directly. The crop step is a no-op.
2. **`flux-pro`** only knows an `aspect_ratio` enum. If that doesn't match exactly, Pillow crops afterward.
3. **`flux-pro/kontext`** (i2i) does **not** know 4:5: the skill maps it to `3:4` and crops to exactly 4:5 afterward.
4. **4K** is generated at a max long edge of 2048px and upscaled via LANCZOS. FLUX is trained on ~1-2 MP; beyond that it repeats motifs instead of delivering detail. If real 4K is needed, an upscaler endpoint (`fal-ai/clarity-upscaler`) belongs in between: this is noted as a `ponytail:` comment in the script.

The post-processing stays in regardless: it **guarantees** exact target dimensions no matter what the model delivers.

### Format

fal only delivers `jpeg` or `png`. The skill always requests **PNG** (lossless source) and re-encodes locally to WebP/JPG/PNG with quality control. WebP uses `method=6` (smallest files).

---

## Workflow Integration

### Calling from another skill
A content or blog skill calls the generator directly via CLI. Typical for a hero image (1280×720):

```bash
"$PY" "$GEN" \
  --prompt "<thematic prompt>" \
  --output "$SITE_ROOT/img/blog/${slug}-hero.webp" \
  --resolution 1K \
  --aspect 16:9 \
  --quality 85
```

Since the generator natively outputs WebP, a downstream `cwebp` step is **not needed**.

---

## Error Diagnosis

| Error | Cause | Fix |
|---|---|---|
| `FAL_KEY not set` | API key missing | `export FAL_KEY=...` in `~/.zshrc` |
| `401` / `Unauthorized` | Key is wrong or revoked | Get a new key at [fal.ai/dashboard/keys](https://fal.ai/dashboard/keys) |
| `403` / `Exhausted balance` | Balance is empty | Top up billing in the fal dashboard |
| `422 Unprocessable Entity` | Argument doesn't match the endpoint schema | Check the schema: `curl "https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=fal-ai/flux/dev"` |
| `429` | Rate limit | Script retries automatically 3x with backoff |
| Image comes back, but with an NSFW warning | fal safety checker | Rephrase the prompt |
| `No image in response` | Safety block or model error | Rephrase the prompt, use `--verbose` for details |
| `venv/bin/python3 not found` | Setup wasn't run | `bash setup.sh` in the skill directory |

---

## Notes on Prompt Quality

FLUX is good at:
- Abstract tech illustrations, geometric patterns
- Photorealism (significantly better than Nano Banana was)
- Text rendering in images (short strings)
- Prompt fidelity with long, detailed descriptions

FLUX is weak at:
- Complex text layouts (multiple phrases → inconsistent)
- Consistent characters across multiple images (use `--seed` + i2i for that)
- Very specific brands/logos

**Prompt tips:**
- Be concrete: "minimalist line illustration" instead of "nice illustration"
- FLUX likes long prompts: full sentences work better than keyword lists
- Be explicit about colors: "navy background (#0d0f14), muted gold accents (#c8a96e)"
- Composition: "centered subject, ample negative space"
- FLUX has **no** negative prompts: rephrase "no text" positively ("clean surface, unmarked")

---

## What this skill does NOT do

- **No image-to-vector conversion**: output is always raster (PNG/WebP/JPG)
- **No animation/video**: still images only
- **No photo editing operations**: no background removal, no object cleanup. Use Pillow/ImageMagick directly for that
- **No image analysis**: input images are only i2i references, no OCR
- **No multi-image fusion**: fal endpoints accept exactly one reference
- **No stock photo search**

---

## Model Updates

When fal releases a new model or deprecates an old one:
1. Cross-check the schema: `curl "https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=<new-id>"`
2. Update `MODELS` / `MODELS_I2I` in `scripts/generate.py`
3. If it supports free-form dimensions: add the alias to `NATIVE_DIMENSIONS`
4. `"$PY" "$GEN" --self-test` (free) + a real test call
5. Commit + push

Endpoint IDs in this skill verified against the fal OpenAPI schemas: **August 2026**.
