---
name: fal-image-generator
description: |
  Generiert Bilder via fal.ai (FLUX-Familie) mit konfigurierbarer
  Auflösung, Aspect-Ratio, Output-Format und Reference-Image-Support.
  Wird sowohl direkt vom User getriggert als auch von anderen Skills
  aufgerufen, die Bilder brauchen (z.B. Blog-Hero, Inline-Grafik).

  MANDATORY TRIGGERS: "fal-image-generator", "generate image",
  "Bild generieren", "erstell mir ein Bild", "Bild erzeugen mit fal",
  "Image-to-Image", "FLUX".

  STRONG TRIGGERS: "ich brauche ein Bild von X", "Hero-Bild für Y",
  "Illustration für Z", "Social-Media-Bild", "Thumbnail erstellen",
  "AI-generiertes Bild", "make me an image of", "create image",
  "image of X for my blog/post/article".

  PROACTIVE USE: Wenn ein anderer Skill ein Bild braucht, ist dies
  der Standard-Generator. Auch wenn der User
  nur sagt "und dazu ein passendes Bild" mitten in einem anderen
  Workflow — diesen Skill verwenden.

  NICHT triggern für: Reine Bildbearbeitung bestehender lokaler Bilder
  (Crop, Resize, Filter — das macht Pillow/ImageMagick direkt ohne API
  und ohne Kosten), Bild-Analyse oder OCR (nicht der Zweck dieses
  Tools), Vektor/Logo-Design (FLUX ist Raster, für Vektoren andere
  Tools), Stock-Photo-Suche (Search-Tool, nicht Generation).
metadata:
  version: 3.0.0
  provider: fal.ai
---

# fal Image Generator

Generiert Bilder via [fal.ai](https://fal.ai). Standard-Modell ist **FLUX.1 [dev]** (`fal-ai/flux/dev`) — gutes Preis/Leistungs-Verhältnis und **native Custom-Dimensionen**, d.h. du bekommst exakt die Pixelmaße, die du bestellst.

## Modelle

| Alias | Endpoint | Charakter |
|---|---|---|
| `flux-dev` **(Default)** | `fal-ai/flux/dev` | Preis/Leistung. Native `image_size {width,height}`. 28 Steps. |
| `flux-schnell` | `fal-ai/flux/schnell` | Drafts und Iterationen. 4 Steps, deutlich billiger, sichtbar gröber. |
| `flux-pro` | `fal-ai/flux-pro/v1.1-ultra` | Beste Qualität. Nur `aspect_ratio`-Enum, keine freien Maße. |

Bei `--reference` wird automatisch auf das Image-to-Image-Gegenstück umgeschaltet:

| Alias | i2i-Endpoint | Steuerung |
|---|---|---|
| `flux-dev` | `fal-ai/flux/dev/image-to-image` | `--strength` (0 = wie Original, 1 = frei) |
| `flux-schnell` | *(fällt auf flux-dev zurück)* | kein eigenes i2i-Endpoint bei fal |
| `flux-pro` | `fal-ai/flux-pro/kontext` | instruktionsbasiertes Editieren |

## Kosten-Awareness

**Jeder Call kostet Geld.** fal rechnet je nach Modell pro Megapixel oder pro Bild ab — die Tarife ändern sich, deshalb stehen hier bewusst keine eingefrorenen Zahlen.

👉 Aktuelle Preise: **https://fal.ai/pricing**

Vor einem Massenlauf (z.B. Batch-Artikel) einmal prüfen. Faustregeln, die unabhängig vom Tarif gelten:

- `flux-schnell` ist ~10× billiger als `flux-dev` — für Draft-Iterationen nutzen, erst final auf `flux-dev` wechseln
- Höhere Auflösung kostet mehr. `--resolution 1K` reicht für 1280×720 Blog-Hero
- `--seed` setzen wenn du ein Ergebnis reproduzieren willst — spart Wiederholungs-Calls

---

## Setup (einmalig)

```bash
# Im Skill-Verzeichnis
cd "$(dirname $(readlink ~/.claude/skills/fal-image-generator/SKILL.md))"
bash setup.sh
```

Das `setup.sh` legt das venv an, installiert Dependencies, prüft den API-Key und fährt den Offline-Self-Test.

Manuell falls nötig:
```bash
python3 -m venv scripts/venv
./scripts/venv/bin/pip install -r scripts/requirements.txt
export FAL_KEY="dein-key-hier"   # in ~/.zshrc dauerhaft setzen
```

### Key-Handling

`FAL_KEY` gehört in `~/.zshrc` — **nicht** in dieses Skill-Verzeichnis, nicht in eine `.env` neben dem Code, nicht in ein Verzeichnis das je deployed oder synchronisiert wird. Die `.gitignore` im Repo-Root ignoriert `.env*` zusätzlich, aber das ist Gürtel-und-Hosenträger: die Datei soll gar nicht erst existieren.

`setup.sh` gibt bewusst nur die *Länge* des Keys aus, kein Prefix — sonst landet der Wert im Terminal-Scrollback, in CI-Logs und in Agent-Transkripten.

---

## Parameter (CLI)

| Parameter | Pflicht | Default | Beschreibung |
|---|---|---|---|
| `--prompt` | ✅ | — | Text-Prompt für das Bild |
| `--output` | ✅ | — | Pfad für die Output-Datei (Format wird aus Extension erkannt) |
| `--reference` | — | — | Referenz-Bild (lokaler Pfad oder URL). **Nur 1** — fal-Endpoints nehmen genau ein `image_url` |
| `--resolution` | — | `1K` | `1K` / `2K` / `4K` |
| `--aspect` | — | `1:1` | `1:1` / `16:9` / `9:16` / `4:5` / `3:4` |
| `--format` | — | aus Output-Extension | `png` / `webp` / `jpg` |
| `--quality` | — | `90` | 1-100 für WebP/JPG (PNG ignoriert) |
| `--model` | — | `flux-dev` | `flux-dev` / `flux-schnell` / `flux-pro` |
| `--strength` | — | `0.85` | Nur bei `--reference` mit flux-dev: 0 = nah am Original, 1 = frei |
| `--seed` | — | — | Reproduzierbarer Output |
| `--no-resize` | — | false | Skippt Post-Processing (Debug) |
| `--self-test` | — | — | Offline-Checks der Dimensions-Logik, **keine API-Calls, keine Kosten** |

---

## Beispiele

### Text-to-Image (Standard)
```bash
./scripts/generate.py \
  --prompt "Minimalist tech illustration on dark navy background, golden geometric lines, abstract circuit pattern" \
  --output hero.webp \
  --resolution 2K \
  --aspect 16:9 \
  --quality 85
```

### Image-to-Image mit Referenz
```bash
./scripts/generate.py \
  --prompt "Same style, but with focus on cloud architecture instead" \
  --reference existing-hero.webp \
  --strength 0.7 \
  --output new-hero.webp \
  --resolution 2K \
  --aspect 16:9
```

### Billig-Modus für Drafts/Iterationen
```bash
./scripts/generate.py \
  --prompt "Quick draft" \
  --output draft.png \
  --model flux-schnell
```

### Reproduzierbar
```bash
./scripts/generate.py --prompt "..." --output a.webp --seed 42
```

---

## Wie Auflösung und Aspect-Ratio wirklich funktionieren

Bei vielen Image-Skills sind `--aspect` und `--resolution` nur **Prompt-Hinweise** plus nachträglicher Crop — du bezahlst ein 1:1-Bild und wirfst ~44% der Pixel weg. Hier nicht:

1. **`flux-dev` / `flux-schnell`** bekommen `image_size: {width, height}` nativ. Bestellst du 16:9 @ 2K, generiert fal direkt 1920×1080. Der Crop-Schritt ist ein No-Op.
2. **`flux-pro`** kennt nur ein `aspect_ratio`-Enum. Passt das nicht exakt, cropt Pillow nach.
3. **`flux-pro/kontext`** (i2i) kennt **kein 4:5** — der Skill mappt auf `3:4` und cropt auf exakt 4:5 nach.
4. **4K** wird bei max. 2048px langer Kante generiert und per LANCZOS hochskaliert. FLUX ist auf ~1-2 MP trainiert; darüber wiederholt es Motive statt Details zu liefern. Wenn echtes 4K gebraucht wird, gehört ein Upscaler-Endpoint (`fal-ai/clarity-upscaler`) dazwischen — steht als `ponytail:`-Kommentar im Script.

Das Post-Processing bleibt trotzdem drin: es **garantiert** exakte Zielmaße, egal was das Modell liefert.

### Format

fal liefert nur `jpeg` oder `png`. Der Skill fragt immer **PNG** an (verlustfreie Quelle) und kodiert lokal auf WebP/JPG/PNG mit Quality-Control um. WebP nutzt `method=6` (kleinste Dateien).

---

## Workflow-Integration

### Aufruf aus einem anderen Skill
Ein Content- oder Blog-Skill ruft den Generator direkt per CLI auf. Typisch für ein Hero-Bild (1280×720):

```bash
./scripts/generate.py \
  --prompt "<thematischer Prompt>" \
  --output "$SITE_ROOT/img/blog/${slug}-hero.webp" \
  --resolution 1K \
  --aspect 16:9 \
  --quality 85
```

Da der Generator nativ WebP rausgibt, **entfällt** ein nachgelagerter `cwebp`-Schritt.

---

## Fehler-Diagnose

| Fehler | Ursache | Fix |
|---|---|---|
| `FAL_KEY not set` | API-Key fehlt | `export FAL_KEY=...` in `~/.zshrc` |
| `401` / `Unauthorized` | Key falsch oder revoked | Neuen Key unter [fal.ai/dashboard/keys](https://fal.ai/dashboard/keys) |
| `403` / `Exhausted balance` | Guthaben leer | Billing im fal-Dashboard aufladen |
| `422 Unprocessable Entity` | Argument passt nicht zum Endpoint-Schema | Schema prüfen: `curl "https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=fal-ai/flux/dev"` |
| `429` | Rate-Limit | Script retried automatisch 3× mit Backoff |
| Bild kommt zurück, aber NSFW-Warnung | fal Safety-Checker | Prompt umformulieren |
| `No image in response` | Safety-Block oder Modellfehler | Prompt umformulieren, `--verbose` für Details |
| `venv/bin/python3 not found` | Setup nicht ausgeführt | `bash setup.sh` im Skill-Verzeichnis |

---

## Hinweise zur Prompt-Qualität

FLUX ist gut bei:
- Abstrakten Tech-Illustrationen, geometrischen Mustern
- Photorealismus (deutlich besser als Nano Banana es war)
- Text-Rendering in Bildern (kurze Strings)
- Prompt-Treue bei langen, detaillierten Beschreibungen

FLUX ist schwach bei:
- Komplexen Text-Layouts (mehrere Phrasen → inkonsistent)
- Konsistenten Charakteren über mehrere Bilder (dafür `--seed` + i2i)
- Sehr spezifischen Marken/Logos

**Prompt-Tipps:**
- Konkret: "minimalist line illustration" statt "nice illustration"
- FLUX mag lange Prompts — ganze Sätze funktionieren besser als Keyword-Listen
- Farben explizit: "navy background (#0d0f14), muted gold accents (#c8a96e)"
- Komposition: "centered subject, ample negative space"
- Negative Prompts gibt es bei FLUX **nicht** — "no text" positiv umformulieren ("clean surface, unmarked")

---

## Was dieser Skill NICHT macht

- **Keine Bild-zu-Vektor-Konvertierung** — Output ist immer Raster (PNG/WebP/JPG)
- **Keine Animation/Video** — nur Standbilder
- **Keine Photo-Editing-Operationen** — kein Background-Removal, kein Object-Cleanup. Dafür Pillow/ImageMagick direkt
- **Keine Bild-Analyse** — Input-Bilder sind nur i2i-Referenz, kein OCR
- **Keine Multi-Image-Fusion** — fal-Endpoints nehmen genau eine Referenz
- **Keine Stock-Photo-Suche**

---

## Modell-Updates

Wenn fal ein neues Modell released oder ein altes abkündigt:
1. Schema gegenprüfen: `curl "https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=<neue-id>"`
2. `MODELS` / `MODELS_I2I` in `scripts/generate.py` updaten
3. Wenn es freie Dimensionen kann: Alias in `NATIVE_DIMENSIONS` aufnehmen
4. `./scripts/generate.py --self-test` (kostenlos) + ein echter Test-Call
5. Commit + Push

Endpoint-IDs in diesem Skill verifiziert gegen die fal-OpenAPI-Schemas: **August 2026**.
