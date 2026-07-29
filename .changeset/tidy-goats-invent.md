---
"looped-whisper": minor
---

Add style templates. `style.json` can now hold named variations — Email, Slack, whatever you write in — alongside the base profile. Name one while you speak ("style it as an email", "make it shorter as a slack message"), or set a default in Settings → Style so one applies whenever you don't say otherwise.

Templates add to the base rather than replacing it: guidance, substitutions and banned words merge, so a word you never use stays banned everywhere, while single values like `maxWords`, `voice.description` and `straightenQuotes` override. A template can also switch a base rule off. An unrecognized template name falls back to the base rather than failing, since a misheard word shouldn't cost you the rewrite.

The config stays as strict as before, and the strictness reaches inside templates: a typo in `templates.email.enforced` is the same hard error it would be at the top level, and pointing `defaultTemplate` at a template that doesn't exist is rejected rather than quietly ignored. "style it" now also reads as a plain rewrite instruction. Existing single-profile configs are unchanged and keep working.
