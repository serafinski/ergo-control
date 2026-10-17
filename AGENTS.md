# Repository workflow

- Never push directly to `main`, force-push it, or bypass its GitHub ruleset. Make changes on a `codex/` branch and open a pull request targeting `main`.
- Keep pull requests open for the user's review. Merge only when the user explicitly authorizes merging.
- GitHub Actions are manual-only to conserve runner minutes. Do not add push/PR/tag triggers or dispatch a workflow without the user's authorization. Run appropriate checks locally and report the results in the PR.
- Never commit signing keys, passwords, private research/vendor artifacts, user configuration, or captured input/system logs. Respect existing ignore rules.
