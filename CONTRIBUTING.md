# Contributing

Thank you for your interest in improving autogit. Bug reports, ideas and pull requests are all welcome. By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs and requesting features

Open an issue and pick the matching template. For a bug, include:

- the script and its version (`bash autopush.sh --version`)
- your platform (Termux, Linux, macOS, Git Bash, WSL) and Bash version
- the exact steps and the terminal output

Remove or hide your access token before you paste anything. Security problems must not be reported in public issues; see [SECURITY.md](SECURITY.md).

## Making a change

There is no build step. Each script is a single Bash file.

1. Fork the repository and create a branch.
2. Make your change.
3. Run the checks below.
4. Open a pull request.

### Checks

```sh
for f in autopush.sh autoclone.sh; do bash -n "$f"; done
shellcheck --severity=warning autopush.sh autoclone.sh
bash autopush.sh --help
bash autoclone.sh --help
```

Then try the change against a throwaway repository, using a fine-grained token limited to that repository. The same checks run automatically on every pull request.

### Code style

- Plain Bash that also runs on Bash 3.2 (macOS). Avoid associative arrays, `mapfile` and `${var,,}`.
- Keep the code self-explanatory and free of comments, as in the existing scripts.
- User-facing text lives in variables at the top of each script, so it is easy to customize.
- Both scripts share the same look and helper functions. A change to the interface usually belongs in both.
- Never log, echo or pass a token on a command line.

### Pull requests

- Keep each pull request focused on one change.
- Describe what changed and why.
- Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
