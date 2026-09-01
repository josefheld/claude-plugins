#!/usr/bin/env python3
"""
fal.ai Image Generator
======================

Generates images via fal.ai (FLUX family).
Preferred invocation via venv:

    ./venv/bin/python3 generate.py --prompt "..." --output ...

Or directly if the venv wrapper is active:

    ./generate.py --prompt "..." --output ...
"""
import argparse
import os
import sys
import time
import urllib.error
import urllib.request
from io import BytesIO
from pathlib import Path

try:
    import fal_client
    from PIL import Image
except ImportError as e:
    print(f"❌ Missing dependency: {e}", file=sys.stderr)
    print("Run: bash setup.sh  (in the skill directory)", file=sys.stderr)
    sys.exit(2)


# ---- Configuration ----
# Endpoint IDs verified against
#   https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=<id>
# If fal deprecates a model, update here (cross-check the schema there).
MODELS = {
    "flux-dev":     "fal-ai/flux/dev",
    "flux-schnell": "fal-ai/flux/schnell",
    "flux-pro":     "fal-ai/flux-pro/v1.1-ultra",
}

# Image-to-image counterpart, selected automatically with --reference.
MODELS_I2I = {
    "flux-dev":     "fal-ai/flux/dev/image-to-image",
    # ponytail: schnell has no dedicated i2i endpoint, falls back to dev.
    "flux-schnell": "fal-ai/flux/dev/image-to-image",
    "flux-pro":     "fal-ai/flux-pro/kontext",
}

# Models with native image_size {width,height}. The rest only know aspect_ratio.
NATIVE_DIMENSIONS = {"flux-dev", "flux-schnell"}

# aspect_ratio enum of fal-ai/flux-pro/kontext, does not know 4:5.
KONTEXT_ASPECTS = {"21:9", "16:9", "4:3", "3:2", "1:1", "2:3", "3:4", "9:16", "9:21"}
ASPECT_FALLBACK = {"4:5": "3:4"}  # closest match; post_process crops to exact afterward

ASPECT_DIMENSIONS = {
    # Target dimensions per (aspect, resolution)
    ("1:1",  "1K"): (1024, 1024),
    ("1:1",  "2K"): (2048, 2048),
    ("1:1",  "4K"): (4096, 4096),
    ("16:9", "1K"): (1280, 720),
    ("16:9", "2K"): (1920, 1080),
    ("16:9", "4K"): (3840, 2160),
    ("9:16", "1K"): (720, 1280),
    ("9:16", "2K"): (1080, 1920),
    ("9:16", "4K"): (2160, 3840),
    ("4:5",  "1K"): (1024, 1280),
    ("4:5",  "2K"): (1638, 2048),
    ("4:5",  "4K"): (3277, 4096),
    ("3:4",  "1K"): (960, 1280),
    ("3:4",  "2K"): (1536, 2048),
    ("3:4",  "4K"): (3072, 4096),
}

# ponytail: FLUX is trained on ~1-2MP. Beyond that it repeats motifs instead
# of delivering detail. So generate at a max long edge of 2048 and upscale
# the rest via LANCZOS. Upgrade path if native 4K is ever needed: put a real
# upscaler endpoint (fal-ai/clarity-upscaler) in between.
GEN_MAX_LONG_SIDE = 2048

MAX_RETRIES = 3
BASE_BACKOFF_SEC = 2
DOWNLOAD_TIMEOUT_SEC = 120


def log(msg: str, *, err: bool = False) -> None:
    print(msg, file=sys.stderr if err else sys.stdout, flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate images via fal.ai (FLUX family).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --prompt "Tech illustration, dark blue, gold accents" \\
           --output hero.webp --resolution 2K --aspect 16:9
  %(prog)s --prompt "Same style, blue tones" \\
           --reference original.png --output variant.webp
  %(prog)s --prompt "Quick draft" --output draft.png --model flux-schnell
""",
    )
    parser.add_argument("--prompt", help="Text prompt for image generation")
    parser.add_argument("--output", help="Output file path (format inferred from extension)")
    parser.add_argument(
        "--reference",
        action="append",
        help="Reference image for image-to-image (local path or URL; only 1 supported)",
    )
    parser.add_argument("--resolution", default="1K", choices=["1K", "2K", "4K"], help="Output resolution")
    parser.add_argument(
        "--aspect",
        default="1:1",
        choices=["1:1", "16:9", "9:16", "4:5", "3:4"],
        help="Aspect ratio (native on flux-dev/schnell, enum + crop elsewhere)",
    )
    parser.add_argument(
        "--format",
        default=None,
        choices=["png", "webp", "jpg", "jpeg"],
        help="Output format (default: inferred from --output extension)",
    )
    parser.add_argument("--quality", type=int, default=90, help="Quality 1-100 for WebP/JPG (default: 90)")
    parser.add_argument(
        "--model",
        default="flux-dev",
        choices=list(MODELS.keys()),
        help="Model to use (default: flux-dev)",
    )
    parser.add_argument(
        "--strength",
        type=float,
        default=0.85,
        help="Image-to-image strength 0-1: how far to move from the reference (default: 0.85)",
    )
    parser.add_argument("--seed", type=int, default=None, help="Seed for reproducible output")
    parser.add_argument("--no-resize", action="store_true", help="Skip post-processing crop/resize")
    parser.add_argument("--verbose", action="store_true", help="Verbose logging")
    parser.add_argument("--self-test", action="store_true", help="Run offline sanity checks (no API calls)")
    args = parser.parse_args()
    if not args.self_test and (not args.prompt or not args.output):
        parser.error("--prompt and --output are required (unless --self-test)")
    return args


def check_api_key() -> None:
    if not os.environ.get("FAL_KEY"):
        log("❌ FAL_KEY environment variable not set.", err=True)
        log("   Set with: export FAL_KEY='your-api-key-here'", err=True)
        log("   Get a key at: https://fal.ai/dashboard/keys", err=True)
        sys.exit(1)


def target_dims(aspect: str, resolution: str) -> tuple[int, int]:
    return ASPECT_DIMENSIONS[(aspect, resolution)]


def generation_dims(aspect: str, resolution: str) -> tuple[int, int]:
    """Dimensions we actually request from fal (capped to the model's sweet spot)."""
    w, h = target_dims(aspect, resolution)
    long_side = max(w, h)
    if long_side <= GEN_MAX_LONG_SIDE:
        return w, h
    scale = GEN_MAX_LONG_SIDE / long_side
    # round to a multiple of 16, diffusion models like that
    return (max(16, round(w * scale / 16) * 16), max(16, round(h * scale / 16) * 16))


def resolve_reference(ref: str) -> str:
    """Upload a local path to the fal CDN; pass URLs through unchanged."""
    if ref.startswith(("http://", "https://", "data:")):
        return ref
    path = Path(ref)
    if not path.is_file():
        log(f"❌ Reference image not found: {ref}", err=True)
        sys.exit(1)
    log(f"  📎 Uploading reference: {ref}")
    try:
        return fal_client.upload_file(str(path))
    except Exception as e:
        log(f"❌ Reference upload failed: {e}", err=True)
        sys.exit(1)


def build_arguments(
    model_key: str,
    endpoint: str,
    prompt: str,
    aspect: str,
    resolution: str,
    reference_url: str | None,
    strength: float,
    seed: int | None,
) -> dict:
    """Build the argument dict per endpoint, the schemas differ significantly."""
    # Request PNG and re-encode locally: lossless source for the WebP/JPG stage.
    args: dict = {"prompt": prompt, "num_images": 1, "output_format": "png"}
    if seed is not None:
        args["seed"] = seed

    if reference_url:
        args["image_url"] = reference_url
        if endpoint.endswith("/image-to-image"):
            args["strength"] = strength
        elif "kontext" in endpoint:
            wanted = ASPECT_FALLBACK.get(aspect, aspect)
            if wanted in KONTEXT_ASPECTS:
                args["aspect_ratio"] = wanted
        return args

    if model_key in NATIVE_DIMENSIONS:
        gw, gh = generation_dims(aspect, resolution)
        args["image_size"] = {"width": gw, "height": gh}
    else:
        args["aspect_ratio"] = ASPECT_FALLBACK.get(aspect, aspect)
    return args


def run_with_retry(endpoint: str, arguments: dict, *, verbose: bool = False) -> dict:
    """fal_client.run with retry on transient errors."""
    last_err = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            return fal_client.run(endpoint, arguments=arguments)
        except Exception as e:
            last_err = e
            err_str = str(e).lower()
            # Retryable: rate limit, transient server errors, queue timeouts
            if any(s in err_str for s in ["429", "rate", "timeout", "500", "502", "503", "unavailable"]):
                wait = BASE_BACKOFF_SEC * (2 ** (attempt - 1))
                log(f"  ⏳ Transient error (attempt {attempt}/{MAX_RETRIES}), retry in {wait}s: {e}", err=True)
                time.sleep(wait)
                continue
            # Not retryable: auth, empty balance, safety block, invalid schema
            raise
    raise RuntimeError(f"Generation failed after {MAX_RETRIES} attempts: {last_err}")


def fetch_image(result: dict) -> Image.Image | None:
    """Load the first image from the fal result. fal delivers CDN URLs, not bytes."""
    images = result.get("images") or []
    if not images:
        return None
    url = images[0].get("url")
    if not url:
        return None
    if result.get("has_nsfw_concepts", [False])[0]:
        log("  ⚠️  fal safety checker flagged this image as NSFW", err=True)
    try:
        with urllib.request.urlopen(url, timeout=DOWNLOAD_TIMEOUT_SEC) as resp:
            data = resp.read()
    except urllib.error.URLError as e:
        log(f"❌ Could not download generated image: {e}", err=True)
        sys.exit(1)
    img = Image.open(BytesIO(data))
    img.load()  # decode now, so errors surface here, not later
    return img


def post_process(
    img: Image.Image,
    aspect: str,
    resolution: str,
    *,
    skip: bool = False,
) -> Image.Image:
    """Crop to aspect ratio + resize to target resolution.

    For flux-dev/schnell this is mostly a no-op (fal already delivers the exact
    dimensions). It stays in as a guarantee for i2i and aspect_ratio endpoints,
    which choose their own dimensions.
    """
    if skip:
        return img

    target = ASPECT_DIMENSIONS.get((aspect, resolution))
    if not target:
        return img
    target_w, target_h = target

    cur_w, cur_h = img.size
    cur_aspect = cur_w / cur_h
    target_aspect = target_w / target_h

    # Center crop if the aspect ratio doesn't match
    if abs(cur_aspect - target_aspect) > 0.01:
        if cur_aspect > target_aspect:
            new_w = int(cur_h * target_aspect)
            offset = (cur_w - new_w) // 2
            img = img.crop((offset, 0, offset + new_w, cur_h))
        else:
            new_h = int(cur_w / target_aspect)
            offset = (cur_h - new_h) // 2
            img = img.crop((0, offset, cur_w, offset + new_h))

    if img.size != (target_w, target_h):
        img = img.resize((target_w, target_h), Image.Resampling.LANCZOS)

    return img


def save_image(img: Image.Image, output_path: str, fmt: str | None, quality: int) -> None:
    """Saves the image in the desired format with quality control."""
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    if fmt:
        save_format = fmt.upper().replace("JPG", "JPEG")
    else:
        ext = path.suffix.lower().lstrip(".")
        save_format = {"jpg": "JPEG", "jpeg": "JPEG", "png": "PNG", "webp": "WEBP"}.get(ext, "PNG")

    if save_format == "JPEG" and img.mode != "RGB":
        img = img.convert("RGB")

    save_kwargs = {}
    if save_format in ("WEBP", "JPEG"):
        save_kwargs["quality"] = max(1, min(100, quality))
    if save_format == "WEBP":
        save_kwargs["method"] = 6  # highest compression quality (slower, smaller)

    img.save(output_path, format=save_format, **save_kwargs)


def self_test() -> None:
    """Offline checks for the dimension logic. Costs nothing, calls nothing."""
    # Every aspect/resolution combination exists and matches the ratio
    for (aspect, res), (w, h) in ASPECT_DIMENSIONS.items():
        aw, ah = (int(x) for x in aspect.split(":"))
        assert abs((w / h) - (aw / ah)) < 0.02, f"{aspect}@{res} = {w}x{h} is not {aspect}"

    # 1K/2K stay untouched, 4K is capped to the sweet spot
    assert generation_dims("16:9", "1K") == (1280, 720)
    assert generation_dims("16:9", "2K") == (1920, 1080)
    gw, gh = generation_dims("16:9", "4K")
    assert max(gw, gh) == GEN_MAX_LONG_SIDE, f"4K not capped: {gw}x{gh}"
    assert abs((gw / gh) - (16 / 9)) < 0.02, f"cap broke aspect: {gw}x{gh}"
    assert gw % 16 == 0 and gh % 16 == 0, f"not multiple of 16: {gw}x{gh}"

    # post_process delivers exactly the target dimensions, no matter what comes in
    for src in [(1024, 1024), (1920, 1080), (900, 1600)]:
        out = post_process(Image.new("RGB", src), "16:9", "2K")
        assert out.size == (1920, 1080), f"{src} -> {out.size}, expected (1920, 1080)"

    # flux-dev gets image_size, flux-pro gets aspect_ratio
    a = build_arguments("flux-dev", MODELS["flux-dev"], "x", "16:9", "2K", None, 0.85, None)
    assert a["image_size"] == {"width": 1920, "height": 1080}, a
    b = build_arguments("flux-pro", MODELS["flux-pro"], "x", "16:9", "2K", None, 0.85, None)
    assert "image_size" not in b and b["aspect_ratio"] == "16:9", b

    # kontext doesn't know 4:5 -> fallback to 3:4, post_process crops to exact afterward
    c = build_arguments("flux-pro", MODELS_I2I["flux-pro"], "x", "4:5", "1K", "https://x/y.png", 0.85, None)
    assert c["aspect_ratio"] == "3:4", c
    assert c["image_url"] == "https://x/y.png"

    # i2i gets strength, t2i doesn't
    d = build_arguments("flux-dev", MODELS_I2I["flux-dev"], "x", "1:1", "1K", "https://x/y.png", 0.5, None)
    assert d["strength"] == 0.5 and "image_size" not in d, d

    print("✅ self-test passed")


def main() -> None:
    args = parse_args()

    if args.self_test:
        self_test()
        return

    check_api_key()

    references = args.reference or []
    if len(references) > 1:
        log(f"⚠️  fal endpoints accept 1 reference image, got {len(references)}. Using the first.")
        references = references[:1]

    endpoint = (MODELS_I2I if references else MODELS)[args.model]
    if references and args.model == "flux-schnell":
        log("⚠️  flux-schnell has no image-to-image endpoint, using flux-dev instead.")

    log(f"🎨 Model: {endpoint}")
    log(f"📐 Target: {args.resolution} @ {args.aspect} = {target_dims(args.aspect, args.resolution)}")

    reference_url = resolve_reference(references[0]) if references else None

    arguments = build_arguments(
        args.model, endpoint, args.prompt, args.aspect, args.resolution,
        reference_url, args.strength, args.seed,
    )
    if args.verbose:
        log(f"📝 Arguments:\n{arguments}\n")

    log("⚙️  Generating...")
    try:
        result = run_with_retry(endpoint, arguments, verbose=args.verbose)
    except Exception as e:
        log(f"❌ Generation failed: {e}", err=True)
        sys.exit(1)

    img = fetch_image(result)
    if img is None:
        log("❌ No image in response (possibly safety-blocked or model error)", err=True)
        sys.exit(1)

    log(f"  ✓ Generated: {img.size[0]}×{img.size[1]} {img.mode}  (seed: {result.get('seed')})")

    img = post_process(img, args.aspect, args.resolution, skip=args.no_resize)
    log(f"  ✓ Final: {img.size[0]}×{img.size[1]}")

    save_image(img, args.output, args.format, args.quality)
    log(f"✅ Saved: {args.output}")


if __name__ == "__main__":
    main()
