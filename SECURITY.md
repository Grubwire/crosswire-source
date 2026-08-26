# Security Policy

## Supported Versions

Only the latest release receives security updates. Crosswire is in early development
and does not maintain backport fixes for older versions.

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x (latest) | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues.

Email **security@grubwire.io** with the subject line `[Crosswire] Security Vulnerability`.
Include a description of the issue, steps to reproduce, and any relevant logs or screenshots.

You can expect an acknowledgement within 48 hours. We will keep you informed as we
investigate and will let you know when a fix is released or if we determine the report
is out of scope.

Crosswire runs Windows software on macOS using Wine. Security reports most relevant to
this project include:

- Sandbox or privilege escalation issues in the engine installation or update flow
- Signature verification bypass in the engine manifest (Ed25519 / SHA-256 checks)
- Path traversal or arbitrary file write during engine extraction
- Issues in bottle isolation that could allow a Windows process to affect the host system

Reports for vulnerabilities in Wine itself should be directed upstream to the
[Wine project](https://www.winehq.org/security).
