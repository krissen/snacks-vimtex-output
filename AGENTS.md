# Contributor Guidance

## Purpose
- This repository ships the `snacks-vimtex-output` module described in [README.md](README.md). Keep every change aligned with the stated goal: provide a commented, well-documented Neovim helper that renders VimTeX compiler output inside Snacks-friendly floating windows.

## Coding Standards
- Write idiomatic Lua that follows general Neovim, VimTeX, and Snacks best practices.
- Favor DRY solutions; extract helpers whenever logic is reused.
- Every code block you touch **must be commented** in English to explain intent.
- Never wrap imports in `pcall`-based try/catch purely for style reasons—only when guarding optional dependencies.

## Documentation
- Documentation and comments are always written in English.
- Update documentation whenever functionality or defaults change.
- Example configurations must always reflect the current defaults unless you explicitly document a non-default use case.
- README is the canonical place for describing project purpose, defaults, and usage; keep it synchronized with the implementation.

## Workflow
- Prefer commit messages prefixed with a concise scope tag such as `(docs)` or `(mini-float)` followed by a short description.
- Keep pull request summaries aligned with the actual behavior changes.
- When editing files under nested directories, create additional `AGENTS.md` files if specialized instructions are required there.
