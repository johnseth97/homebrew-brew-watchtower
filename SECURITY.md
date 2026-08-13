# Security policy

Please report suspected vulnerabilities privately through GitHub Security Advisories for `johnseth97/homebrew-brew-watchtower`. Do not include credentials, Homebrew tokens, VPN configuration, or other secrets in a public issue.

## Supported versions

Only the latest tagged release is supported with security fixes.

## Security boundaries

Homebrew Watchtower limits the authority of scheduled updates to the installing user. It does not sandbox Homebrew or upstream package installers, and it does not make user-writable Homebrew packages trustworthy against an attacker already controlling that user account.
