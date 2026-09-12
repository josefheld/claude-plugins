# llm-council

One model gives you one answer, and no way to tell whether it is good. This runs a decision past five advisors who think from deliberately incompatible angles, lets them peer-review each other anonymously, and has a chairman turn the whole thing into one verdict.

Adapted from Andrej Karpathy's [LLM Council](https://github.com/karpathy/llm-council), which dispatches the same question to several different models. This does it with Claude sub-agents under different thinking lenses instead.

## Install

```
/plugin marketplace add josefheld/claude-plugins
/plugin install llm-council@josefheld
```

No setup, no dependencies, no API key.

## Use

Ask in plain language. The skill triggers on "council this", "run the council", "war room this", "pressure-test this", "stress-test this", "debate this", and on real decisions phrased as "should I X or Y", "which option", "is this the right move", "I'm torn between".

```
council this: should I launch a 97 EUR workshop or a 497 EUR course?
pressure-test this positioning: "code audits for legacy JS teams"
```

What then happens, without further input from you:

1. The question gets framed, with context pulled from the conversation.
2. Five advisors answer in parallel: the Contrarian, the First Principles Thinker, the Expansionist, the Outsider, the Executor.
3. Each advisor reviews the other four anonymously, so nobody defers to a thinking style they recognize.
4. A chairman synthesizes: where the council agrees, where it clashes, which blind spots it caught, the recommendation, and the one thing to do first.

Two files land in the working directory:

| File | For |
|---|---|
| `council-report-<timestamp>.html` | self-contained visual report, opens automatically, advisor sections collapsed |
| `council-transcript-<timestamp>.md` | full transcript: framing, all five answers, all peer reviews with the anonymization revealed, the synthesis |

Both are ignored by this repo's `.gitignore`, so a council run inside a clone leaves no artifacts behind.

Worth knowing before you run it: the council is for questions where being wrong is expensive. A factual lookup or a writing task gets nothing out of it, and if you only want validation, expect to be told what you would rather not hear. That is the point of the Contrarian.

## Configure

Nothing. This is a prompt document, not a program, so there are no flags, no config file, no environment variables. What actually changes the outcome:

| Lever | Effect |
|---|---|
| How much context you give | The framing step enriches the question from the conversation. A decision with stakes, options and constraints spelled out produces sharper advisors than a one-liner. |
| Which question you ask | Ask for a decision, not a fact. "Should I X or Y, and why" beats "what do you think about X". |
| Forking `skills/llm-council/SKILL.md` | The five lenses, the peer review rules and the report layout all live there in plain Markdown. Change an advisor, change the council. |

## License & credits

MIT, see the [repo LICENSE](../../LICENSE). Based on Andrej Karpathy's [LLM Council](https://github.com/karpathy/llm-council) methodology, popularized by [Ole Lehmann](https://x.com/itsolelehmann).
