---
name: cc-changelog
description: Fetches the latest Claude Code release notes and produces a personalized summary filtered for the user's roles, stack, and interests. Adapts to whoever uses it via a profile system, so it works for solo developers, founders, agency consultants, students, anyone. Triggers whenever the user asks about new Claude Code versions, changes, updates, or features, in any language. English phrasings "What's new in Claude Code", "Claude Code changelog", "what changed", "since version X", or a casual "Update?" / "new version?" in a Claude Code context. German phrasings "welche neue Version", "Claude Code Update", "was ist neu in Claude Code", "was hat sich geändert", "seit Version X". Use this skill any time the user mentions Claude Code versions or releases, even if they never say "changelog". The skill handles profile resolution, cut-off detection, source fetching, multi-lens filtering, and Markdown output end to end. It answers in the language the user wrote in.
---

# Claude Code Changelog, personalized overview

This skill produces a personalized Markdown summary of recent Claude Code changes, filtered for relevance to **the user's own roles and focus areas**, plus an **honorable mentions lens** for everything else worth knowing.

The skill **adapts to whoever is using it** via a profile system (see "Profile system" below). The defaults are chosen so that the output is useful even without a profile.

> **Output language: match the user.** Write the summary in the language the user wrote their request in. A German question gets a German summary, an English question gets an English one. An explicit `Language` in the profile overrides this. Everything below documents the skill in English, that says nothing about the language of the output.

---

## Sources (in this order)

1. **Primary**: `https://code.claude.com/docs/en/changelog`
2. **Fallback**: `https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md`
3. **Big-picture context** (only if a major release is involved): `https://www.anthropic.com/news`

Always fetch source 1 via `web_fetch` first. Source 2 only if 1 fails. Source 3 only as a cross-reference for larger announcements.

---

## Workflow

### Step 0, determine the profile

The profile decides **language, lenses, stack focus, honorable-mention topics and drop rules** for this user. Resolution order:

1. **Bash available?** Try to read, in this order:
   - `.claude/changelog-profile.md` (project-local)
   - `~/.claude/changelog-profile.md` (global)

   If a file is found, load it and use it.

2. **Evaluate context and memory hints**: if the skill finds no file but the system context (a project CLAUDE.md, a memory system, the conversation history) holds enough information about the user (role, stack, language), derive an implicit profile from it. **Important**: the first time, briefly show the user what was derived and get confirmation before storing the profile permanently.

3. **No profile derivable?** Start a one-time setup flow, a short interview (max 5 questions):
   - Output language? (Default: the language the user wrote in)
   - Which roles are relevant? (e.g. "developer + entrepreneur", "backend engineer + tech lead", "solo founder")
   - Tech stack focus? (e.g. "Supabase, Vercel, MCP server setups, hooks" or "AWS Bedrock, enterprise setup")
   - Platforms/IDEs you do *not* use, that can go into honorable mentions? (e.g. "Windows, JetBrains, Bedrock")
   - Store it? (`.claude/changelog-profile.md` local or `~/.claude/changelog-profile.md` global?)

   Build the profile from the answers and save it. Format in "Profile system" below.

4. **Fallback without a profile**: if the user declines the setup questions or Bash is unavailable, continue with these **default profile assumptions** and mention them as a note at the top of the output:
   - Language: whatever the user wrote in
   - Lenses: "developer" + "founder/entrepreneur"
   - Stack focus: all core features (MCP, sub-agents, hooks, plugins, skills, permissions, commands)
   - Honorable mentions: platform-specific items (Bedrock/Vertex/Foundry/JetBrains/Windows), new models, larger refactorings
   - Drop: "internal fixes" stubs, cosmetic bugs

### Step 2, determine the cut-off

Four modes, depending on what the user says or does not say:

**Mode (b), auto-detect the installed version**
- If the user says "check my version", "what do I have installed", or similar: try `claude --version` via `bash_tool`.
- The output format is usually `2.1.143 (Claude Code)`, parse the version number out of it.
- On success, say: *"You are currently on version X.Y.Z, I will show everything that landed since."*
- On failure (no bash, not installed, unexpected output): fall back to mode (c).

**Mode (c), default: the last 7 days**
- When the user gives no explicit cut-off and does not ask about "my version".
- Say briefly: *"I am taking the last 7 days (since [date]). Tell me if you want a different range."*
- Today's date comes from the system prompt.

**Mode (d), open cut-off (since X until today)**
- The user says "since 2.1.130", "since last week", "the last 3 versions", "since yesterday", etc.
- Use it directly, ask nothing. Lower bound = X, upper bound = the newest available version.

**Mode (e), range comparison between two versions or dates**
- The user says: "between 2.1.130 and 2.1.138", "from X to Y", "2.1.130..2.1.138", "diff 2.1.130 2.1.138", "compare 2.1.130 with 2.1.138", "what landed between version X and Y", "everything between X and Y", "changelog from X to Y".
- Dates work too: "between May 1 and May 10", "April to May".
- Parsing: lower bound = the lower version / earlier date, upper bound = the higher version / later date. The order in the input does not matter, always take the lower one as the start.
- **Inclusive on both sides**: items from version X *and* version Y are included.
- State the range explicitly in the output header (see output structure).

If it is unclear which mode applies, ask one single clarifying sentence, then continue.

### Step 3, fetch the changelog

`web_fetch` the primary source. The page lists versions **in reverse chronological order** (newest first), with headers like `2.1.143` and dates like `May 15, 2026`.

When reading for modes (b)/(c)/(d): process versions **until** the lower bound is reached.
When reading for mode (e): process the versions that fall between the lower and upper bound (both inclusive). Skip versions above the upper bound, stop at versions below the lower bound.

### Step 4, filter every entry through the lenses

For each bullet point in each version: check which lens or lenses from the **user's profile** the item hits. If no lens hits, it goes to honorable mentions or gets dropped.

**In this version of the skill the lenses are primarily a classification scheme**, not an output layout. For each item, record *which* lenses it hits. Those lenses appear as a compact tag (`For: developer, entrepreneur`) on the item itself. Items are no longer grouped by lens in the output.

**Multiple hits are allowed and in fact wanted**: if an item is equally relevant for a developer *and* an entrepreneur, tag both lenses. No more artificial "primary lens" decision.

**The lens descriptions below are defaults** for a typical developer/founder profile. If the user profile defines other lenses or focus areas, **use those from the profile**, not the defaults.

#### 🛠️ Default lens 1: developer

What gets in (default, overridable by the profile):
- **MCP servers** (Supabase, Vercel, MongoDB, filesystem): connection, OAuth, permissions, config, reconnect behaviour
- **Sub-agents, agent teams, `claude agents`, `/bg` background sessions**: isolation, worktrees, lifecycle
- **Slash commands**, especially custom commands in `.claude/commands/`
- **Hooks** (PreToolUse, PostToolUse, UserPromptSubmit, Stop, SubagentStop, PreCompact, SessionStart)
- **Permissions**: allow/deny rules, `--dangerously-skip-permissions`, wildcards, sandbox, auto mode
- **Plugins**: install, marketplace, dependencies, validate
- **Skills**: creation, invocation, frontmatter, plugin-provided
- **Resume, compact, context window, effort levels**
- **Performance and stability** of core workflows (Edit, Read, Bash, Grep)
- **Anything marked breaking / removed / changed default**
- **Anything security-relevant**

#### 💼 Default lens 2: entrepreneur / founder

What gets in (default, overridable by the profile): anything that touches outward effect, business leverage or visibility.

*Business and product leverage:*
- **New capabilities that enable products or services**, related to the stack and business model in the profile
- **Pricing-relevant items**: effort levels, model defaults, context window expansions, cache TTL, quota changes
- **Platform extensions** (web, desktop, Chrome, Slack, IDE): capabilities you can sell or offer
- **Remote control, scheduling, push notifications, the `claude agents` dashboard**: backbone for services
- **Enterprise and compliance features** (managed settings, audit, OTel): relevant for B2B offerings
- **Headless / SDK / CI-CD integration**: automation inside products
- **New models and major capability jumps**: they change what you can build

*Visibility, content, education:*
- **Features you can show and demo** in talks, sessions, blog posts
- **"Wow" features** for a non-technical audience (voice mode, push, web/mobile, new IDE integrations)
- **Use cases for content** (blog, talk, tutorial, newsletter)
- **Major version milestones** and branded features: marketing hooks
- **Tutorial and recipe potential**: features with a clear how-to that works as a blog post or video

#### 📋 Default lens 3: honorable mentions

Everything that is **new or changed** but does **not fit one of the main lenses**, and is still worth a mention so nothing slips through unnoticed.

What gets in (default, overridable by the profile):
- **Platforms the user does not currently use but should know about**: Bedrock/Vertex/Foundry (for advising clients), JetBrains and other IDEs, Windows-specific items (for demos and training)
- **New models, effort levels, pricing changes**, even when the user does not use them directly
- **Larger refactorings and architecture changes** (e.g. native binary, new renderers)
- **Interesting new capabilities without a direct use case**
- **Notable security fixes**, even ones that did not affect the user directly

Format: shorter than the main lenses, usually one sentence. No "why this matters to you" and no use case needed. Just a list with version number and date.

#### What actually gets dropped (no mention at all)

Only these categories are cut completely (the profile can narrow this further):
- "Internal fixes" entries with no detail whatsoever
- Hyper-specific edge-case fixes for tools or workflows that do not appear in the profile
- Purely cosmetic rendering bugs in one single exotic terminal or IDE

**When in doubt**: put it in honorable mentions rather than dropping it. The skill must not hide anything relevant from the user.

### Step 5, assemble the output

Write a Markdown file to `/mnt/user-data/outputs/claude-code-changelog-<YYYY-MM-DD>.md` (filename with today's date) and show it via `present_files`.

**Exception**: if fewer than 10 items remain after filtering, answer inline instead of writing a file.

#### Structure

````markdown
# Claude Code, what is new for you

<Header depending on the mode:>

— Modes (b), (c), (d):
**Range**: <cut-off> to <today's date>
**Versions processed**: <N> (from <oldest> to <newest>)

— Mode (e), range comparison:
**Comparison**: v<lower bound> to v<upper bound>
**Versions processed**: <N> (<date of lower bound> to <date of upper bound>)

---

## 🎯 Executive summary

<1 sentence of framing, optional, e.g. "Three things worth taking away:">

1. **<top item 1>** (v<version>) — <one crisp sentence>
2. **<top item 2>** (v<version>) — <one crisp sentence>
3. **<top item 3>** (v<version>) — <one crisp sentence>

---

## 🆕 New features

- **<feature name>** (v<version>, <date>) · *For:* <lens or lenses from the profile, comma separated>
  - *What:* <one sentence, technically what happens>
  - *Benefit:* <one sentence, what the user gets out of it: pain point, advantage, time or effort saved>
  - *Usage:* <one sentence or a compact code snippet showing how to actually use it: flag, command, setting, hook snippet>

- **<feature name 2>** ...

## ⚠️ Breaking changes and behaviour changes

- **<change>** (v<version>, <date>) · *For:* <lens(es)>
  - *Change:* <what concretely changes>
  - *Action:* <what the user has to adjust, or "nothing, just be aware">

## 🐛 Notable bugfixes

- **<fix>** (v<version>, <date>) · *For:* <lens(es)>
  - *Before:* <what was broken>
  - *Now:* <what works now>
  - *Noticeable when:* <when and where the fix shows up>

## 📋 Honorable mentions

*New or changed, but not in the main focus:*
- **<item>** (v<version>, <date>) — <one sentence on what it is>. *(For: <lens>)* — optional
- ...

---
*Source: code.claude.com/docs/en/changelog · as of <date>*
````

If a section is empty (no breaking changes in the range, for instance): leave the section out, do not render it as an empty list.

### Ordering within a section

Items inside "new features" / "breaking" / "bugfixes" are **prioritized by impact, not chronologically**. Top-down readability: the most important first, the peripheral last. When impact is comparable, the item that hits the user's stack directly wins.

For honorable mentions a rough thematic grouping is enough (platform items first, then UX improvements, then configuration options).

### Choosing the executive summary

The executive summary is **the most important part of the output**, many people read only that. Rules:

- **3 items by default, 5 at most.** Too few beats too many.
- **Prioritization, not chronology**: order by impact, not by version number.
- **Selection criteria** (in this order):
  1. Items that hit the user's active stack directly (MCP server fixes, agent workflow, hooks, skills)
  2. Larger new capabilities (new commands, new dashboards, new models)
  3. Breaking changes the user *actually* has to adapt to
- **Format per item**: `**<short name>** (v<version>) — <one sentence>`. No second sentence, no "why this matters to you", that is spelled out further down.
- **When nothing was truly big**: still write an executive summary, but frame it honestly: *"Quiet week, the main points:"* instead of inflated highlights.

---

## Style rules

- **Use the language from the profile**, and without a profile the language the user wrote in. Stay consistent throughout.
- **The three-part format per main item is mandatory** in the new features, breaking and bugfixes sections:
  - *New features*: **What / Benefit / Usage**
  - *Breaking*: **Change / Action**
  - *Bugfixes*: **Before / Now / Noticeable when**

  Each component is **one sentence** (or a compact code snippet for *usage*). No padding, no "it is worth noting that...".

- **What vs benefit, keep them separate:**
  - *What* = the technical change ("hooks spawn commands directly without shell wrapping")
  - *Benefit* = the pain point it solves or the advantage it brings ("no more shell escaping bugs on paths with spaces")
  - *Usage* = how to actually apply it, ideally a snippet, flag or setting name (e.g. `args: ["script.sh", "$file"]` instead of `command: "script.sh '$file'"`)

- **Always give the `For:` tag** on main items. Comma-separated list of lens names from the profile. On multiple hits, list every relevant lens (no more "primary lens" decision).

- **Honorable mentions stay simple**: one sentence of description, no three-part scheme. The *For:* tag is optional, in parentheses at the end, when it adds something.

- **Phrase it generically, do not personalize by name.** The *selection* of items may use the profile knowledge (stack, roles, projects), but the *wording* stays generic. **Concrete proper nouns from the profile (companies, products, people, internal tools) do not belong in the output.** Use generic terms instead: "multi-agent orchestration" rather than a specific product name, "B2B outreach system" rather than an internal tool name, "education platform" rather than a specific community, "your own business" rather than a company name. The reason: the output should not feel like reading over someone's shoulder, it should feel like a professional briefing.

- **Leave technical terms in English**: sub-agent, hook, plugin, MCP, worktree, permission. Do not translate them artificially, not even in non-English output.

- **Always include version number and date**, so the user can look it up.

- **No emoji in body text**, only in section headers (🎯 🆕 ⚠️ 🐛 📋).

- **When nothing relevant landed**: be honest. *"Between X and Y there were only maintenance changes, N bugfixes, none of them critical for your stack. Not worth going through in detail."*

---

## Example output (small, for orientation)

````markdown
# Claude Code, what is new for you

**Range**: May 12 to May 18, 2026
**Versions processed**: 4 (2.1.140 to 2.1.143)

---

## 🎯 Executive summary

1. **New flags for `claude agents`** (v2.1.142) — dispatched background sessions can now be preconfigured with `--mcp-config`, `--model`, `--effort` and more.
2. **Fast mode uses Opus 4.7 by default** (v2.1.142) — faster default model, no action needed.
3. **Plugin dependency enforcement** (v2.1.143) — disable checks dependencies, enable pulls them in.

---

## 🆕 New features

- **New flags for `claude agents`** (v2.1.142, May 14) · *For:* developer, entrepreneur
  - *What:* dispatched background sessions are now configured via CLI flags: `--add-dir`, `--settings`, `--mcp-config`, `--permission-mode`, `--model`, `--effort`.
  - *Benefit:* different MCP configs, permission profiles and effort levels per project, without separate wrapper scripts or setting switches.
  - *Usage:* `claude agents --mcp-config production.json --permission-mode strict --effort high --model opus`.

- **Plugin dependency enforcement** (v2.1.143, May 15) · *For:* developer
  - *What:* `claude plugin disable` refuses when there are active dependents, `enable` pulls transitive dependencies in automatically.
  - *Benefit:* no more accidentally broken plugin stacks when a base plugin that others need gets disabled.
  - *Usage:* a normal `claude plugin disable <name>`, the disable chain is checked automatically and printed as a copy-pasteable hint.

- **Fast mode uses Opus 4.7 by default** (v2.1.142, May 14) · *For:* entrepreneur
  - *What:* the default model for fast operations (auto-title, small tool calls) is now Opus 4.7 instead of 4.6.
  - *Benefit:* a quality jump across all background operations with no setup effort, and a clean education headline at the same time.
  - *Usage:* no action needed, active automatically after the upgrade. Opt out via `CLAUDE_CODE_OPUS_4_6_FAST_MODE_OVERRIDE=1`.

## ⚠️ Breaking changes and behaviour changes

- **PowerShell tool enabled by default on Windows for Bedrock/Vertex/Foundry** (v2.1.143, May 15) · *For:* entrepreneur
  - *Change:* on Windows systems using Bedrock/Vertex/Foundry auth, the PowerShell tool is now on by default.
  - *Action:* be aware of it when advising Windows clients. Opt out via `CLAUDE_CODE_USE_POWERSHELL_TOOL=0` if unwanted.

## 📋 Honorable mentions

*New or changed, but not in the main focus:*
- **`worktree.bgIsolation: "none"` setting** (v2.1.143, May 15) — lets background sessions edit directly in the working copy without EnterWorktree.
- **Stop hook loop cap** (v2.1.143, May 15) — blocking stop hooks now end the turn automatically after 8 iterations.
- **`/web-setup` warns about GitHub app replacement** (v2.1.142, May 14).

---
*Source: code.claude.com/docs/en/changelog · as of May 18, 2026*
````

*(This example matches a profile with lenses = developer + entrepreneur and stack focus = MCP / sub-agents / hooks / plugins. The same run against a profile with `Language: de` produces the identical structure in German.)*

---

## Profile system

The profile is a Markdown file with a fixed structure. The skill reads it at the start of every triggered run and uses it to determine lenses, language, focus areas and drop rules.

### Storage location

- **Project-local**: `.claude/changelog-profile.md`, recommended when the stack varies per project
- **Global**: `~/.claude/changelog-profile.md`, recommended for individuals with a consistent stack

If both exist, project-local wins.

### Profile format

````markdown
# Claude Code Changelog Profile

## Language
<de | en | ...>  — language of the output. "de" means German, informal address.

## Tone (optional)
<formal | direct | terse>  — default: direct.

## Lenses
List of the lenses that should appear in the output. Each lens has a name, an emoji, and a list of topic focus areas.

### 🛠️ <lens name 1>
- <focus 1, e.g. "MCP servers (Supabase, Vercel)">
- <focus 2, e.g. "sub-agents, agent teams, /bg">
- ...

### 💼 <lens name 2>
- <focus 1>
- ...

(any number of lenses is possible, but 2 to 3 is the ergonomic upper limit)

## Honorable Mentions
- <what belongs here, e.g. "Bedrock/Vertex/Foundry items">
- ...

## Drop (hide completely)
- <what should be cut entirely, e.g. "internal fixes stubs">
- ...

## Context Hints (never appear in the output)
Here the user can note memory and context hints that steer the *selection* but must not end up in the output. For example concrete company, product or people names.
- <e.g. "company: <name>, tools: <name>, colleagues: <name>">
````

### Example profiles

**Example A, solo founder on a Supabase/Next.js stack:**

````markdown
# Claude Code Changelog Profile

## Language
de

## Lenses

### 🛠️ Entwickler
- MCP servers (Supabase, Vercel, Stripe)
- Hooks (PreToolUse, PostToolUse for linting)
- Next.js / TypeScript workflows
- Authentication flows (Clerk, Supabase Auth)
- Database tooling (RLS, edge functions)

### 💼 Founder
- B2B SaaS features (multi-tenant, billing)
- Cost-effective AI usage (pricing, cache, effort levels)
- Customer-facing capabilities (voice, web, mobile)
- Headless/CI-CD integration

## Honorable Mentions
- Bedrock/Vertex/Foundry items
- JetBrains, Windows-specific items
- Plugin development (not used actively yet)

## Drop
- Internal fixes stubs
- Hyper-specific terminal rendering bugs

## Context Hints
- Main project: <own product name>
- Stack: Supabase, Next.js, Vercel, Stripe
````

**Example B, backend engineer in an AWS shop:**

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

### Profile updates

When the user says *"update my profile"*, *"my stack has changed"*, *"add another lens"* or similar:
1. Load the current profile and show it
2. Walk through the concrete changes with the user
3. Write the updated profile back to the same file

---

## Edge cases

- **Several versions on the same day**: merge them into one entry, use the newest version as the reference.
- **Hotfix-only versions** (e.g. "internal fixes"): mention them in honorable mentions only, do not detail them.
- **Very large range** (>30 days, >20 versions): before filtering, say *"That is a big one, should I keep it rough or go through it fully?"* and wait for the user's answer.
- **Cut-off is after the newest version**: *"You are up to date."* Do not generate a file.
- **Range mode with invalid versions**: if the lower bound is greater than the upper bound, swap them silently and mention it briefly ("I read that as: from X to Y"). If one of the two versions does not exist in the changelog, tell the user which existing versions are closest and ask.
- **Range mode with two identical versions**: answer *"That is a single version, here is what changed in it:"* and process only that version as a special case.
