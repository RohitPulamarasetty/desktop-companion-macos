# CLAUDE.md — rules for development agents

## Project identity

Desktop Companion is a **macOS-only** desktop companion: a small pixel character
that lives on the Mac desktop. It is not an AI assistant and not a chatbot.

Current scope: **macOS only.** No Windows, no Linux, no website, no backend,
no cloud, no telemetry. Core behavior is deterministic and local-first.

## Layout

- `Sources/Core` — platform-neutral logic: `PetBrain` (the single behavior
  engine), personality, mood, memory, settings, storage. No AppKit.
- `Sources/Platform/macOS` — AppKit UI: transparent window, menu, settings,
  dashboard, picker, onboarding.
- `Sources/App` — app entry point and wiring.
- `Sources/CoreTestsRunner` — dependency-free test runner (`swift run CoreTestsRunner`).
- `Characters/` — shipped character packs. `LocalCharacters/` is git-ignored.
- `scripts/` — `package_app.sh`, `package_dmg.sh`, `build_dogs.py`, `build_icon.py`.
- `docs/` — architecture, feature matrix, release notes (for maintainers).

## Engineering rules

- Inspect existing implementation before changing it. Do not blindly rewrite working systems.
- Prefer simple, maintainable solutions. Do not over-engineer.
- No unnecessary dependencies. No heavy AI. Keep the app lightweight.
- Activities must go through `PetBrain`; never add a second behavior engine.
- Test every meaningful feature. Add a regression test for every bug.
- Never claim a feature works without testing it. Never fabricate test results.
- Never fabricate platform support or licensing.
- No dead UI: every control must do something.
- Do not create unnecessary files.
- Only ship artwork whose license is understood; credit it in `THIRD_PARTY.md`.

## Git rules

- Never add an AI as co-author or contributor. Never mention an AI tool in
  commit messages, and never add `Co-authored-by` lines for one.
- Commit messages are short and human-readable (`feat: add cursor follow`).
- Make focused commits; review `git diff` before committing.
- Do not commit secrets, machine-specific files, build caches, or generated
  artifacts (DMGs go in GitHub Releases, not in the repository).

## Product rule

This is the owner's project. README and docs describe it as such — no AI
attribution anywhere in the project.
