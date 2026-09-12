# cc-changelog

The Claude Code changelog is written for everyone, which means most of any release does not concern you. This fetches the release notes and filters every entry through your roles, your stack and your language, so a 60-entry release arrives as the five lines that change your work.

## Install

```
/plugin marketplace add josefheld/claude-plugins
/plugin install cc-changelog@josefheld
```

No dependencies, no API key.

## Use

Ask about versions or releases in any phrasing, in any language:

```
what's new in Claude Code?
was ist neu in Claude Code seit 2.1.180?
Update?
```

The first run resolves a profile (see below), then every run does the same four steps: determine the cut-off (what you have already seen), fetch the changelog, filter each entry through your lenses, and assemble the output. It answers in the language you wrote in.

Sources, in this order:

1. `https://code.claude.com/docs/en/changelog`
2. `https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md`, only if the first fails
3. `https://www.anthropic.com/news`, only as cross-reference for a major release

The output is Markdown: an executive summary, then new features, breaking and behaviour changes, notable bugfixes, and honorable mentions for the things that exist but are not yours.

## Configure

Everything runs off one profile file. Resolution order, first hit wins:

| Path | When to use it |
|---|---|
| `.claude/changelog-profile.md` | per project, when the stack differs between repos |
| `~/.claude/changelog-profile.md` | globally, for a consistent stack |

If neither exists, the skill derives a profile from context (a project `CLAUDE.md`, memory, the conversation) and shows you what it derived before storing it. If nothing is derivable, it asks at most five questions once: language, roles, stack focus, platforms you do not use, and where to store the file. Decline and it proceeds with a documented default profile and says so at the top of the output.

The file is plain Markdown with fixed section names:

| Section | Controls |
|---|---|
| `## Language` | output language, e.g. `de` or `en` |
| `## Tone` | `formal`, `direct` or `terse`, optional, default `direct` |
| `## Lenses` | one `### emoji name` block per lens, each with its topic focus areas. Two to three lenses is the ergonomic maximum |
| `## Honorable Mentions` | what gets one line instead of a section, e.g. Bedrock, Vertex, JetBrains, Windows items |
| `## Drop (hide completely)` | what gets cut, e.g. "internal fixes" stubs, cosmetic bugs |
| `## Context Hints` | steers the selection without ever appearing in the output: company, product or people names |

Editing the file is the whole configuration surface. To change what a release looks like for you, change a lens; to stop seeing a category, put it under `Drop`.

## License

MIT, see the [repo LICENSE](../../LICENSE).
