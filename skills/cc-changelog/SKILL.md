---
name: cc-changelog
description: Fetches the latest Claude Code release notes and produces a personalized summary filtered for the user's roles, stack, and interests. Adapts to whoever uses it via a profile system — works for solo developers, founders, agency consultants, students, anyone. Triggers whenever the user asks about new Claude Code versions, changes, updates, or features — phrases like "What's new in Claude Code", "Claude Code Changelog", "welche neue Version", "Claude Code Update", "what changed", "since version X", or even casual "Update?" / "new version?" in a Claude Code context. Use this skill any time the user mentions Claude Code versions or releases, even if they don't explicitly say "changelog" — the skill handles profile resolution, cut-off detection, source fetching, multi-lens filtering, and Markdown output end-to-end.
---

# Claude Code Changelog – Personalisierte Übersicht

Dieser Skill produziert eine personalisierte Markdown-Zusammenfassung der jüngsten Claude-Code-Änderungen, gefiltert auf Relevanz für **die jeweiligen Rollen und Schwerpunkte des Nutzers** plus eine **Honorable-Mentions-Linse** für alles Übrige, was erwähnenswert ist.

Der Skill **passt sich an den jeweiligen Nutzer an** via Profil-System (siehe Abschnitt „Profil-System" unten). Defaults sind so gewählt, dass auch ohne Profil ein sinnvoller Output entsteht.

---

## Quellen (in dieser Reihenfolge)

1. **Primär**: `https://code.claude.com/docs/en/changelog`
2. **Fallback**: `https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md`
3. **Big-picture context** (nur falls Major-Release dabei): `https://www.anthropic.com/news`

Immer zuerst Quelle 1 via `web_fetch` holen. Quelle 2 nur wenn 1 fehlschlägt. Quelle 3 nur als Querverweis bei größeren Announcements.

---

## Workflow

### Schritt 0 – Profil ermitteln

Das Profil bestimmt **Sprache, Linsen, Stack-Schwerpunkte, Honorable-Mentions-Themen und Drop-Regeln** für diesen Nutzer. Auflösungs-Reihenfolge:

1. **Bash verfügbar?** Versuche in dieser Reihenfolge zu lesen:
   - `.claude/changelog-profile.md` (Projekt-lokal)
   - `~/.claude/changelog-profile.md` (global)
   
   Wenn eine Datei gefunden wird → laden und verwenden.

2. **Kontext-/Memory-Hinweise auswerten**: Wenn der Skill keine Datei findet, aber im System-Kontext (z.B. CLAUDE.md im Projekt, Memory-System auf Claude.ai, Konversationshistorie) genug Information über den Nutzer steht — Rolle, Stack, Sprache — ein implizites Profil daraus ableiten. **Wichtig**: Beim ersten Mal dem Nutzer kurz zeigen, was abgeleitet wurde, und Bestätigung einholen, bevor das Profil dauerhaft gespeichert wird.

3. **Kein Profil ableitbar?** Einmaligen Setup-Flow starten — knappe Befragung (max. 5 Fragen):
   - Sprache des Outputs? (Default: Deutsch falls Nutzer auf Deutsch geschrieben hat, sonst Englisch)
   - Welche Rollen sind relevant? (z.B. „Entwickler + Entrepreneur" oder „Backend Engineer + Tech Lead" oder „Solo Founder")
   - Tech-Stack-Schwerpunkte? (z.B. „Supabase, Vercel, MCP-Server-Setups, Hooks" oder „AWS Bedrock, Enterprise Setup")
   - Plattformen/IDEs, die du *nicht* nutzt und in Honorable Mentions schieben kannst? (z.B. „Windows, JetBrains, Bedrock")
   - Speichern? (`.claude/changelog-profile.md` lokal oder `~/.claude/changelog-profile.md` global?)
   
   Profil aus den Antworten erzeugen und speichern. Format siehe „Profil-System" unten.

4. **Fallback ohne Profil**: Wenn der Nutzer die Setup-Fragen ablehnt oder Bash nicht verfügbar ist, mit folgenden **Default-Profil-Annahmen** weiterarbeiten und das am Anfang des Outputs als Hinweis erwähnen:
   - Sprache: Englisch
   - Linsen: „Developer" + „Founder/Entrepreneur"
   - Stack-Schwerpunkte: alle Kern-Features (MCP, Sub-Agents, Hooks, Plugins, Skills, Permissions, Commands)
   - Honorable Mentions: Plattform-spezifisches (Bedrock/Vertex/Foundry/JetBrains/Windows), neue Modelle, größere Refactorings
   - Drop: „Internal fixes"-Stubs, kosmetische Bugs

### Schritt 2 – Cut-off bestimmen

Vier Modi, je nachdem was der User sagt oder nicht sagt:

**Modus (b) – Auto-Detect installierter Version**
- Wenn der User „check meine Version", „was hab ich installiert", o.ä. sagt: Versuche `claude --version` via `bash_tool`.
- Output-Format ist üblicherweise `2.1.143 (Claude Code)` — parse die Versionsnummer.
- Wenn erfolgreich: Sage *„Du hast aktuell Version X.Y.Z installiert — ich zeige alles, was seither neu kam."*
- Wenn fehlgeschlagen (kein bash, nicht installiert, anderer Output): Fallback auf Modus (c).

**Modus (c) – Default: letzte 7 Tage**
- Wenn der User keinen expliziten Cut-off gibt und auch nicht nach „meiner Version" fragt.
- Sage kurz: *„Ich nehme die letzten 7 Tage (seit [Datum]). Sag Bescheid, wenn du einen anderen Zeitraum willst."*
- Heutiges Datum kommt aus dem System-Prompt.

**Modus (d) – Offener Cut-off (seit X bis heute)**
- User sagt „seit 2.1.130", „seit letzter Woche", „die letzten 3 Versionen", „seit gestern", etc.
- Direkt verwenden, nichts nachfragen. Untergrenze = X, Obergrenze = neueste verfügbare Version.

**Modus (e) – Range-Vergleich zwischen zwei Versionen oder Daten**
- User sagt: „zwischen 2.1.130 und 2.1.138", „von X bis Y", „2.1.130..2.1.138", „diff 2.1.130 2.1.138", „Vergleiche 2.1.130 mit 2.1.138", „was kam zwischen Version X und Y dazu", „alles zwischen X und Y", „Changelog von X bis Y".
- Auch mit Daten: „zwischen 1. Mai und 10. Mai", „April bis Mai".
- Parsen: Untergrenze = niedrigere Version/früheres Datum, Obergrenze = höhere Version/späteres Datum. Reihenfolge im Input ist egal — immer die niedrigere als Start nehmen.
- **Inklusiv beide Seiten**: Items aus Version X *und* Version Y werden inkludiert.
- Im Output-Header explizit Range angeben (siehe Output-Struktur).

Wenn unklar welcher Modus → ein einzelner Klärungssatz, dann weiter.

### Schritt 3 – Changelog holen

`web_fetch` auf die Primärquelle. Die Seite listet Versionen **rückwärtschronologisch** (neueste zuerst), mit Headern wie `2.1.143` und Datum wie `May 15, 2026`.

Beim Lesen für Modi (b)/(c)/(d): Versionen verarbeiten **bis** die Untergrenze erreicht ist.
Beim Lesen für Modus (e): Versionen verarbeiten, die zwischen Unter- und Obergrenze liegen (beide inklusiv). Versionen oberhalb der Obergrenze überspringen, Versionen unterhalb der Untergrenze stoppen.

### Schritt 4 – Pro Eintrag durch die Linsen filtern

Für jeden Bullet-Point in jeder Version: Prüfen, welche Linse(n) aus dem **Profil des Nutzers** das Item trifft. Wenn keine Linse trifft → in Honorable Mentions oder droppen.

**Die Linsen sind in dieser Version des Skills primär ein Klassifikations-Schema**, kein Output-Layout. Pro Item wird festgehalten, *welche* Linsen es trifft — diese Linsen erscheinen als kompaktes Tag (`Für: Entwickler, Entrepreneur`) am Item selbst. Items werden nicht mehr nach Linse gruppiert ausgegeben.

**Mehrfach-Treffer sind erlaubt und sogar erwünscht**: Wenn ein Item für Entwickler *und* Entrepreneur gleich relevant ist, beide Linsen taggen. Keine künstliche „primäre Linse"-Entscheidung mehr.

**Die folgenden Linsen-Beschreibungen sind Defaults** für ein typisches Developer-/Founder-Profil. Wenn das Nutzerprofil andere Linsen oder Schwerpunkte definiert, **diese aus dem Profil verwenden**, nicht die Defaults.

#### 🛠️ Default-Linse 1: Entwickler / Developer

Was reinkommt (Default — vom Profil überschreibbar):
- **MCP servers** (Supabase, Vercel, MongoDB, filesystem) — Connection, OAuth, Permissions, Config, Reconnect-Verhalten
- **Sub-agents, agent teams, `claude agents`, `/bg` background sessions** — Isolation, Worktrees, Lifecycle
- **Slash commands**, besonders custom commands in `.claude/commands/` (User hat `/handoff`, `/pstatus`, `/decision`)
- **Hooks** (PreToolUse, PostToolUse, UserPromptSubmit, Stop, SubagentStop, PreCompact, SessionStart)
- **Permissions** — allow/deny rules, `--dangerously-skip-permissions`, Wildcards, Sandbox, auto mode
- **Plugins** — Install, Marketplace, Dependencies, Validate
- **Skills** — Creation, Invocation, Frontmatter, Plugin-provided
- **Resume, Compact, Context Window, Effort Levels**
- **Performance/Stabilität** von Kern-Workflows (Edit, Read, Bash, Grep)
- **Alles, was als breaking / removed / changed default markiert ist**
- **Security-relevantes**

#### 💼 Default-Linse 2: Entrepreneur / Founder

Was reinkommt (Default — vom Profil überschreibbar) — alles, was Außenwirkung, Business-Hebel oder Sichtbarkeit betrifft:

*Business / Produkt-Hebel:*
- **Neue Capabilities, die Produkte/Services ermöglichen** — Bezug zum eigenen Stack/Business-Modell aus dem Profil
- **Pricing-relevantes** — Effort Levels, Model Defaults, Context Window Expansions, Cache TTL, Quota-Änderungen
- **Plattform-Erweiterungen** (Web, Desktop, Chrome, Slack, IDE) — verkaufbare/anbietbare Capabilities
- **Remote Control, Scheduling, Push Notifications, `claude agents`-Dashboard** — Backbone für Services
- **Enterprise/Compliance-Features** (managed settings, audit, OTel) — relevant für B2B-Angebote
- **Headless / SDK / CI-CD-Integration** — Automation in Produkte
- **Neue Modelle / Major Capability-Sprünge** — verändern „was man damit bauen kann"

*Sichtbarkeit / Content / Education:*
- **Sicht- und demonstrierbare Features** für Talks, Sessions, Blog-Posts
- **„Wow"-Features** für nicht-technisches Publikum (Voice mode, Push, Web/Mobile, neue IDE-Integrationen)
- **Use Cases für Content** (Blog, Talk, Tutorial, Newsletter)
- **Major Version Milestones**, gebrandete Features — Marketing-Hooks
- **Tutorials/Recipes-Potenzial** — Features mit klarer Anleitung, die als Blog/Video taugen

#### 📋 Default-Linse 3: Honorable Mentions

Alles, was **neu/geändert** ist, aber **nicht in eine der Hauptlinsen** passt — und trotzdem erwähnenswert ist, damit nichts „unter dem Radar" durchrutscht.

Was reinkommt (Default — vom Profil überschreibbar):
- **Plattformen, die der Nutzer aktuell nicht nutzt, aber kennen sollte** — Bedrock/Vertex/Foundry (für Kunden-Beratung), JetBrains/andere IDEs, Windows-spezifisches (für Demos/Schulungen)
- **Neue Modelle / Effort-Levels / Pricing-Änderungen** auch wenn er sie nicht direkt nutzt
- **Größere Refactorings / Architektur-Änderungen** (z.B. native binary, neue Renderer)
- **Interessante neue Capabilities ohne direkten Anwendungsfall**
- **Notable Security Fixes**, auch wenn ihn nicht direkt betroffen

Format: kürzer als die Hauptlinsen — meistens 1 Satz, keine Erklärung „warum wichtig für dich" und kein Anwendungsfall nötig. Einfach als Liste mit Versionsnummer + Datum.

#### Was *wirklich* gedroppt wird (ohne Erwähnung)

Nur diese Kategorien fliegen komplett raus (Profil kann das weiter einschränken):
- „Internal fixes"-Einträge ohne jeden Detail
- Hyper-spezifische Edge-Case-Fixes für Tools/Workflows, die im Profil nicht erscheinen
- Rein kosmetische Rendering-Bugs in einem einzigen exotischen Terminal/IDE

**Im-Zweifel-Regel**: lieber in „Honorable Mentions" packen als komplett droppen. Der Skill soll nichts Relevantes vor dem Nutzer verstecken.

### Schritt 5 – Output zusammenstellen

Markdown-Datei nach `/mnt/user-data/outputs/claude-code-changelog-<YYYY-MM-DD>.md` schreiben (Dateiname mit heutigem Datum) und via `present_files` zeigen.

**Ausnahme**: Wenn nach Filterung nur <10 Items übrig sind, inline antworten statt Datei.

#### Struktur

````markdown
# Claude Code – Was ist neu für dich

<Header je nach Modus:>

— Modus (b), (c), (d):
**Zeitraum**: <Cut-off> bis <heutiges Datum>
**Versionen verarbeitet**: <N> (von <älteste> bis <neueste>)

— Modus (e) Range-Vergleich:
**Vergleich**: v<Untergrenze> → v<Obergrenze>
**Versionen verarbeitet**: <N> (<Datum Untergrenze> bis <Datum Obergrenze>)

---

## 🎯 Executive Summary

<1 Satz Framing, optional — z.B. „Drei Dinge, die du mitnehmen solltest:">

1. **<Top-Item 1>** (v<Version>) — <ein Satz, knackig>
2. **<Top-Item 2>** (v<Version>) — <ein Satz, knackig>
3. **<Top-Item 3>** (v<Version>) — <ein Satz, knackig>

---

## 🆕 Neue Features

- **<Feature-Name>** (v<Version>, <Datum>) · *Für:* <Linse(n) aus Profil, kommagetrennt>
  - *Was:* <ein Satz, technisch was passiert>
  - *Nutzen:* <ein Satz, was der Nutzer davon hat — Pain Point, Vorteil, Zeit-/Aufwandsersparnis>
  - *Anwendung:* <ein Satz oder kompakter Code-Schnipsel, wie man's konkret nutzt — Flag, Command, Setting, Hook-Snippet, etc.>

- **<Feature-Name 2>** ...

## ⚠️ Breaking / Verhaltensänderungen

- **<Change>** (v<Version>, <Datum>) · *Für:* <Linse(n)>
  - *Änderung:* <was sich konkret ändert>
  - *Action:* <was der Nutzer anpassen muss; oder „nichts, einfach beachten">

## 🐛 Wichtige Bugfixes

- **<Fix>** (v<Version>, <Datum>) · *Für:* <Linse(n)>
  - *Vorher:* <was kaputt war>
  - *Jetzt:* <was jetzt funktioniert>
  - *Bemerkbar bei:* <wann/wo der Fix spürbar wird>

## 📋 Honorable Mentions

*Neu/geändert, aber nicht im Haupt-Fokus:*
- **<Item>** (v<Version>, <Datum>) — <1 Satz, was es ist>. *(Für: <Linse>)* — optional
- ...

---
*Quelle: code.claude.com/docs/en/changelog · Stand: <Datum>*
````

Wenn eine Sektion leer ist (z.B. keine Breaking Changes im Zeitraum): Sektion weglassen, nicht als leere Liste rendern.

### Reihenfolge innerhalb einer Sektion

Items innerhalb von „Neue Features" / „Breaking" / „Bugfixes" werden **nach Impact priorisiert, nicht chronologisch**. Top-Down-Lesbarkeit: das Wichtigste zuerst, das Periphere zuletzt. Wenn der Impact ähnlich ist, gewinnt das Stack-direkt-treffende Item.

In den Honorable Mentions reicht eine grobe thematische Gruppierung (z.B. erst Plattform-Items, dann UX-Verbesserungen, dann Konfigurations-Optionen).

### Executive-Summary-Auswahl

Die Executive Summary ist **das Wichtigste am Output** — viele Leute lesen nur das. Regeln:

- **3 Items als Default, 5 als Maximum.** Lieber zu wenig als zu viel.
- **Priorisierung, nicht Chronologie**: Reihenfolge nach Impact, nicht nach Versionsnummer.
- **Auswahlkriterien** (in dieser Reihenfolge):
  1. Items, die direkt Josefs aktiven Stack treffen (MCP-Server-Fixes, Paperclip/Agent-Workflow, Hooks, Skills)
  2. Größere neue Capabilities (neue Commands, neue Dashboards, neue Modelle)
  3. Breaking Changes, die er *wirklich* anpassen muss
- **Format pro Item**: `**<knapper Name>** (v<Version>) — <ein Satz>`. Kein zweiter Satz, kein „warum für dich" — das steht ja unten ausführlich.
- **Wenn nichts wirklich groß war**: Executive Summary trotzdem schreiben, aber ehrlich framen: *„Ruhige Woche — die wichtigsten Punkte:"* statt aufgeblähter Highlights.

---

## Stilregeln

- **Sprache aus dem Profil verwenden** (Default Englisch, falls nichts gesetzt). Konsistent durchziehen.
- **Dreiteiliges Format pro Hauptitem ist Pflicht** in den Sektionen Neue Features, Breaking und Bugfixes:
  - *Neue Features*: **Was / Nutzen / Anwendung**
  - *Breaking*: **Änderung / Action**
  - *Bugfixes*: **Vorher / Jetzt / Bemerkbar bei**
  
  Jede Komponente ist **ein Satz** (oder ein kompakter Code-Schnipsel bei *Anwendung*). Kein Padding, kein „Es ist erwähnenswert, dass…".
  
- **Was vs. Nutzen — klare Trennung:**
  - *Was* = die technische Änderung („Hooks spawnen Commands direkt ohne Shell-Wrapping")
  - *Nutzen* = der Pain Point, den's löst, oder Vorteil, den's bringt („Keine Shell-Escaping-Bugs mehr bei Pfaden mit Leerzeichen")
  - *Anwendung* = wie man's konkret einsetzt — gerne Code-Schnipsel, Flag, Setting-Name (z.B. `args: ["script.sh", "$file"]` statt `command: "script.sh '$file'"`)
  
- **`Für:`-Tag immer angeben** für Hauptitems. Komma-getrennte Liste der Linsen-Namen aus dem Profil. Bei Mehrfach-Treffern alle relevanten Linsen aufführen (keine „primäre Linse"-Entscheidung mehr).
  
- **Honorable Mentions bleiben einfach**: nur 1 Satz Beschreibung, kein dreiteiliges Schema. *Für:*-Tag optional, in Klammern am Ende, wenn es Mehrwert bringt.

- **Generisch formulieren, nicht namentlich personalisieren.** Die *Auswahl* der Items darf das Profil-Wissen nutzen (Stack, Rollen, Projekte), aber das *Wording* bleibt generisch. **Konkrete Eigennamen aus dem Profil (Firmen, Produkte, Personen, interne Tools) gehören nicht in den Output.** Stattdessen generische Begriffe: „Multi-Agent-Orchestrierung" statt eines konkreten Produktnamens, „B2B-Outreach-System" statt eines internen Tool-Namens, „Education-Plattform" statt einer konkreten Community, „eigenes Business" statt einer Firma. Begründung: Der Output sollte sich nicht wie Über-die-Schulter-Lesen anfühlen, sondern wie ein professionelles Briefing.

- **Technische Begriffe in Englisch lassen**: Sub-Agent, Hook, Plugin, MCP, Worktree, Permission. Nicht künstlich übersetzen, auch bei deutschem Output.

- **Versionsnummer + Datum immer dazu**, damit der Nutzer nachschlagen kann.

- **Keine Emojis im Fließtext**, nur in Section-Headern (🎯 🆕 ⚠️ 🐛 📋).

- **Wenn nichts Relevantes dabei war**: Ehrlich sein. *„Im Zeitraum X bis Y gab es nur Wartungsänderungen — N Bugfixes, alle nicht-kritisch für deinen Stack. Lohnt sich nicht im Detail."*

---

## Beispiel-Output (Mini, zur Orientierung)

````markdown
# Claude Code – Was ist neu für dich

**Zeitraum**: 12. Mai bis 18. Mai 2026
**Versionen verarbeitet**: 4 (2.1.140 bis 2.1.143)

---

## 🎯 Executive Summary

1. **`claude agents` neue Flags** (v2.1.142) — Dispatched Background-Sessions können jetzt mit `--mcp-config`, `--model`, `--effort` etc. vorkonfiguriert werden.
2. **Fast Mode nutzt Opus 4.7 by default** (v2.1.142) — Schnelleres Default-Modell, keine Action nötig.
3. **Plugin-Dependency-Enforcement** (v2.1.143) — Disable mit Abhängigkeits-Check, Enable zieht Dependencies mit.

---

## 🆕 Neue Features

- **`claude agents` neue Flags** (v2.1.142, 14. Mai) · *Für:* Entwickler, Entrepreneur
  - *Was:* Dispatched Background-Sessions werden jetzt per CLI-Flag konfiguriert: `--add-dir`, `--settings`, `--mcp-config`, `--permission-mode`, `--model`, `--effort`.
  - *Nutzen:* Pro Projekt unterschiedliche MCP-Configs, Permission-Profile und Effort-Level — ohne separate Wrapper-Scripts oder Setting-Switches.
  - *Anwendung:* `claude agents --mcp-config production.json --permission-mode strict --effort high --model opus`.

- **Plugin-Dependency-Enforcement** (v2.1.143, 15. Mai) · *Für:* Entwickler
  - *Was:* `claude plugin disable` verweigert sich bei aktiven Abhängigkeiten, `enable` zieht transitive Dependencies automatisch mit.
  - *Nutzen:* Keine versehentlich kaputten Plugin-Stacks mehr, wenn ein Base-Plugin deaktiviert wird, das andere benötigen.
  - *Anwendung:* Normales `claude plugin disable <name>` — die Disable-Chain wird automatisch geprüft und als copy-pasteable Hint ausgegeben.

- **Fast Mode nutzt Opus 4.7 by default** (v2.1.142, 14. Mai) · *Für:* Entrepreneur
  - *Was:* Default-Modell für schnelle Operationen (Auto-Title, kleine Tool-Calls) ist jetzt Opus 4.7 statt 4.6.
  - *Nutzen:* Qualitäts-Sprung in allen Hintergrund-Operationen ohne Setup-Aufwand; gleichzeitig saubere Education-Headline.
  - *Anwendung:* Keine Action nötig — automatisch aktiv nach Upgrade. Opt-out via `CLAUDE_CODE_OPUS_4_6_FAST_MODE_OVERRIDE=1`.

## ⚠️ Breaking / Verhaltensänderungen

- **PowerShell-Tool default-enabled auf Windows für Bedrock/Vertex/Foundry** (v2.1.143, 15. Mai) · *Für:* Entrepreneur
  - *Änderung:* Auf Windows-Systemen mit Bedrock/Vertex/Foundry-Auth ist das PowerShell-Tool jetzt standardmäßig aktiviert.
  - *Action:* Bei Beratung von Windows-Kunden bewusst sein; Opt-out via `CLAUDE_CODE_USE_POWERSHELL_TOOL=0` falls unerwünscht.

## 📋 Honorable Mentions

*Neu/geändert, aber nicht im Haupt-Fokus:*
- **`worktree.bgIsolation: "none"` Setting** (v2.1.143, 15. Mai) — Lässt Background-Sessions direkt im Working Copy editieren ohne EnterWorktree.
- **Stop-Hook-Loop-Cap** (v2.1.143, 15. Mai) — Blockierende Stop-Hooks beenden den Turn jetzt nach 8 Iterationen automatisch.
- **`/web-setup` warnt vor GitHub-App-Replace** (v2.1.142, 14. Mai).

---
*Quelle: code.claude.com/docs/en/changelog · Stand: 18. Mai 2026*
````

*(Dieser Beispiel-Output entspricht einem Profil mit Sprache = Deutsch, Linsen = Entwickler + Entrepreneur, Stack-Schwerpunkt = MCP / Sub-Agents / Hooks / Plugins.)*

---

## Profil-System

Das Profil ist eine Markdown-Datei mit fester Struktur. Der Skill liest sie zu Beginn jedes Trigger-Laufs und nutzt sie, um Linsen, Sprache, Schwerpunkte und Drop-Regeln zu bestimmen.

### Speicher-Ort

- **Projekt-lokal**: `.claude/changelog-profile.md` — empfohlen, wenn der Stack pro Projekt variiert
- **Global**: `~/.claude/changelog-profile.md` — empfohlen für Einzel-Personen mit konsistentem Stack

Wenn beide existieren, gewinnt projekt-lokal.

### Profil-Format

````markdown
# Claude Code Changelog Profile

## Language
<de | en | ...>  — Sprache des Outputs. „de" bedeutet Deutsch + Du-Form.

## Tone (optional)
<formell | direkt | knapp>  — Default: direkt.

## Lenses
Liste der Linsen, die im Output erscheinen sollen. Jede Linse hat einen Namen, Emoji, und eine Liste von Themen-Schwerpunkten.

### 🛠️ <Linsen-Name 1>
- <Schwerpunkt 1, z.B. „MCP servers (Supabase, Vercel)">
- <Schwerpunkt 2, z.B. „Sub-agents, agent teams, /bg">
- ...

### 💼 <Linsen-Name 2>
- <Schwerpunkt 1>
- ...

(beliebig viele Linsen möglich, aber 2-3 ist die ergonomische Obergrenze)

## Honorable Mentions
- <Was hier rein soll, z.B. „Bedrock/Vertex/Foundry-Items">
- ...

## Drop (komplett ausblenden)
- <Was komplett raus soll, z.B. „Internal fixes-Stubs">
- ...

## Context Hints (nicht im Output erscheinen)
Hier kann der Nutzer Memory-/Kontext-Hinweise notieren, die die *Auswahl* steuern, aber nicht im Output landen dürfen. Beispiel: konkrete Firmen-/Produkt-/Personennamen.
- <z.B. „Firma: <Name>, Tools: <Name>, Kollegen: <Name>">
````

### Beispiel-Profile

**Beispiel A — Solo-Founder mit Supabase-/Next.js-Stack:**

````markdown
# Claude Code Changelog Profile

## Language
de

## Lenses

### 🛠️ Entwickler
- MCP servers (Supabase, Vercel, Stripe)
- Hooks (PreToolUse, PostToolUse für Linting)
- Next.js / TypeScript Workflows
- Authentication flows (Clerk, Supabase Auth)
- Database tooling (RLS, Edge Functions)

### 💼 Founder
- B2B SaaS-Features (Multi-Tenant, Billing)
- Cost-effective AI usage (Pricing, Cache, Effort Levels)
- Customer-facing capabilities (Voice, Web, Mobile)
- Headless/CI-CD-Integration

## Honorable Mentions
- Bedrock/Vertex/Foundry-Items
- JetBrains, Windows-spezifisches
- Plugin-Development (nutze ich noch nicht aktiv)

## Drop
- Internal fixes-Stubs
- Hyper-spezifische Terminal-Rendering-Bugs

## Context Hints
- Hauptprojekt: <eigener Produkt-Name>
- Stack: Supabase, Next.js, Vercel, Stripe
````

**Beispiel B — Backend-Engineer im AWS-Shop:**

````markdown
# Claude Code Changelog Profile

## Language
en

## Lenses

### 🛠️ Backend Engineer
- AWS Bedrock integration (model selection, IAM)
- MCP server config (internal tools)
- Permissions, deny rules, sandboxing
- Hooks for compliance/audit logging
- Performance (resume, compact, cache)

### 🏗️ Tech Lead
- Team capabilities (agent teams, shared configs)
- Managed settings, enterprise features
- OTel/observability
- Skills + plugins for team rollout

## Honorable Mentions
- Vertex AI, Foundry, non-AWS providers
- Voice / mobile / consumer features
- JetBrains-specific items (we're on VSCode)

## Drop
- Internal fixes
- Cosmetic rendering bugs

## Context Hints
- Company runs on AWS Bedrock exclusively
- Team of 12 engineers, all on VSCode
````

### Profil-Updates

Wenn der Nutzer *„update mein Profil"*, *„mein Stack hat sich geändert"*, *„andere Linse hinzufügen"* o.ä. sagt:
1. Aktuelles Profil laden und anzeigen
2. Konkrete Änderungen mit dem Nutzer durchsprechen
3. Aktualisiertes Profil zurückschreiben in dieselbe Datei

---

## Edge Cases

- **Mehrere Versionen am gleichen Tag**: Zusammenfassen als ein Eintrag, neueste Version als Referenz nehmen.
- **Hotfix-only-Versionen** (z.B. „Internal fixes"): nur in „Honorable Mentions" erwähnen, nicht detaillieren.
- **Sehr großer Zeitraum** (>30 Tage, >20 Versionen): Vor dem Filtern sagen *„Das wird ein Brocken — soll ich's grob halten oder voll durchgehen?"* und auf User-Antwort warten.
- **Cut-off liegt nach der neuesten Version**: *„Du bist auf dem neuesten Stand."* — keine Datei generieren.
- **Range-Modus mit ungültigen Versionen**: Wenn Untergrenze > Obergrenze: still tauschen, kurz erwähnen („Ich habe das so verstanden: von X bis Y"). Wenn eine der beiden Versionen nicht im Changelog existiert: dem User sagen, welche existierenden Versionen am nächsten dran sind, und nachfragen.
- **Range-Modus, beide Versionen identisch**: Antworten *„Das ist eine einzelne Version — hier die Änderungen darin:"* und nur diese Version als Spezialfall verarbeiten.
