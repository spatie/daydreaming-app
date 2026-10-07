# Security

Please report vulnerabilities using [GitHub's private vulnerability reporting](https://github.com/spatie/daydreaming-app/security/advisories/new). Do not open a public issue containing an exploit, credentials, private images or personal logs.

Include the affected version, reproduction steps, impact and a minimal example. We will investigate and coordinate a fix before public disclosure. Use the latest release for normal bug reports and security testing.

## Credentials and test data

API keys belong in macOS Keychain. Release certificates, notarization keys, Sparkle private keys and storage credentials belong in the maintainer's secret stores or GitHub Actions secrets. Only public verification keys belong in Git.

Never commit `.env` files, `.p8` keys, certificate exports or real user data. Ignore patterns are not a substitute for checking staged files and Git history. If you accidentally expose a credential, revoke or rotate it immediately and notify the maintainers privately.

Automated tests use isolated app identifiers and fake providers. Pull-request workflows must not access release credentials or create paid images. Do not use a production app's preferences, Keychain service or desktop as a test environment.
