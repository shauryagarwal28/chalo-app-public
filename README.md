# Chalo

> "Ride Together" — group riding companion app for the Indian biking community.

Flutter mobile app (`app/`) with a planned Node.js backend (`backend/`). Full product/technical context lives in `docs/` — start there, not here.

## Repo layout

```
app/      Flutter client (Android + iOS) — see app/README.md for setup
backend/  Node.js/Express API (not yet started) — see backend/README.md
docs/     Single source of truth for product, technical, and design decisions
.claude/  Claude Code subagent definitions (pm, senior-engineer, junior-engineer)
```

## Where to start

- **New to the project?** Read `docs/README.md` first — it's the knowledge base index (what Chalo is, current build status, key decisions, directory map).
- **Setting up the app?** `app/README.md`.
- **Working on the backend?** `backend/README.md`.
- **Picking up mid-project?** `docs/process/build-status.md` for current state, `docs/process/working-agreements.md` for how this repo is built and its session log.

## Working with Claude Code on this repo

See `CLAUDE.md` — it points a fresh session at the right docs and explains the PM/senior-engineer/junior-engineer subagent setup in `.claude/agents/`.
