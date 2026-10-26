# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-26

### Added

- `autopush.sh` pushes a local folder to a GitHub repository with one guided command.
  - Interactive prompts, or fully non-interactive use through flags.
  - Works with fine-grained and classic personal access tokens.
  - Token input is masked, never written to disk and never passed on a command line.
  - Live progress bar and a result summary with the elapsed time.
  - Clear `Error` and `Reason` rows when a push cannot be completed.
- `autoclone.sh` clones a GitHub repository with the same interface.
  - Detects public and private repositories and asks for a token only when one is needed.
  - Shallow clone by default (latest commit only); `--full` fetches the entire history.
  - Retries interrupted downloads automatically.
  - Never overwrites an existing folder; uses `name-2`, `name-3` and so on instead.
- Both scripts are written for Bash 3.2 or newer and target Termux, Linux, macOS and Windows (Git Bash or WSL).

[Unreleased]: https://github.com/smrafiu/autogit/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/smrafiu/autogit/releases/tag/v1.0.0
