# Project Agent Rules

Follow `~/AGENTS.md` for the canonical user-wide policy.

## Required Validation

- Run `markdownlint` on every Markdown file you create or edit, using
  `~/.markdownlint.json`.
- Run `shellcheck --enable=all` on every shell script you create or edit.
- Fix findings instead of silencing them unless suppression is justified.

## Documentation Rules

- Keep `README.md` lint-clean.
- For material `README.md` updates, refresh the table of contents.
- Keep user-facing runtime usage in `README.md`.
- Keep maintainer workflow notes here rather than in the README when they are
  not needed by normal users.

## Versioning

- The canonical software version lives in
  [src/pcloud-drive-watchdog.sh](src/pcloud-drive-watchdog.sh)
  as `WATCHDOG_VERSION`.
- When bumping the version, update:
  `WATCHDOG_VERSION` in the runtime script,
  the current release entry in `CHANGELOG.md`,
  and any user-facing version mention in `README.md` if present.
- Prefer semantic versioning.
- If the project does not yet have a released semantic version, start at
  `0.1.0`.
- For patch releases, increment `0.1.x` by one unless the change clearly
  requires a minor or major bump.
