# Contributing

Create a feature branch and open a pull request against `main`. Direct pushes, force pushes and deletion of `main` are blocked by an active GitHub ruleset, with no bypass actors. Resolve review conversations before merging.

A second person's approval is not mandatory, so the maintainer can merge their own PR. Contributors should explain the change, report local validation, and distinguish automated checks from hardware testing.

GitHub Actions run only when manually dispatched. Do not enable automatic push, pull-request or tag builds; this keeps runner usage under the maintainer's control. For release builds, follow [the release guide](docs/RELEASING.md).

Do not include signing credentials, proprietary vendor files, personal settings, raw input captures or private diagnostic logs in commits. Report hardware problems using the app version, connection type, steps to reproduce, and a minimal redacted log excerpt.
