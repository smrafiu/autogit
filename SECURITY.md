# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| 1.x     | Yes       |

## Reporting a Vulnerability

Please do not report security vulnerabilities through public issues.

Use GitHub's private vulnerability reporting instead:

1. Open the [Security tab](https://github.com/smrafiu/autogit/security) of this repository.
2. Choose **Report a vulnerability**.
3. Describe the problem, the affected script and its version (`--version`), and how to reproduce it.

You can expect an acknowledgement within 7 days. Once the report is confirmed, a fix is prepared privately and released together with a note in the [changelog](CHANGELOG.md).

## How tokens are handled

- A token is read from a masked prompt, from the `AUTOPUSH_TOKEN` / `AUTOCLONE_TOKEN` environment variable, or from standard input. It is never accepted as a command-line flag, because arguments are visible to other processes.
- A token is never written to disk and never stored in `.git/config`. The remote URL stays free of credentials.
- Git receives the token through a credential helper that reads it from the environment of the git process.
- Error output is scrubbed of the token before it is shown.

## Recommendations for users

- Prefer a fine-grained token limited to a single repository, with a short expiry. `Contents: Read and write` is enough to push, `Contents: Read-only` is enough to clone.
- Read a script before piping it into a shell, or pin the command to a release tag instead of `main`:

  ```sh
  curl -fsSL https://raw.githubusercontent.com/smrafiu/autogit/v1.0.0/autopush.sh | bash
  ```

- If a token is ever pasted somewhere public by mistake, revoke it immediately in your GitHub settings.
