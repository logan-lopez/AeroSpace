---
description: "The fork's docs live only in new paths; upstream's README, dev-docs, adoc site and CONTRIBUTING aren't edited"
decided: 2026-11-01
by: "Logan"
covers: ["README.md", "dev-docs/", "docs/guide.adoc", "CONTRIBUTING.md"]
---
# Fork docs stay out of upstream files

## Choice

The fork's own docs go only in paths upstream doesn't have: `docs/briefs/`, `docs/decisions/`,
`docs/architecture/`, `docs/guide/`, `AGENTS.md`, `CLAUDE.md` and `.claude/rules/`. Upstream's
root `README.md`, `dev-docs/`, the asciidoc site under `docs/` (`*.adoc`, `assets/`, `util/`,
`config-examples/`, `index.html`) and `CONTRIBUTING.md` stay as upstream has them. The one
exception is three lines appended to `.gitignore` so `.claude/rules/` can be committed.

So the brief layout's root-README step (MIGRATE.md step 3) is skipped here: the fork's front
matter is `AGENTS.md`'s project paragraph and the briefs README.

## Why

The fork tracks upstream `main` and merges it in. Any edit to a file upstream also edits turns
into a merge conflict on the next sync, and upstream's README and docs change often. New paths
never conflict. `build-docs.sh` copies only `docs/*.adoc` and named directories, so new
directories under `docs/` don't reach the site or man pages.

Approved in brief-init's Parley round, 2026-11-01.
