# Security Policy

lidawake installs a helper that runs with administrator (root) privileges, so we
take security seriously and welcome reports.

## Reporting a vulnerability

Please email **security@zayco.it** with the details. We'll acknowledge within a few
days and keep you posted on a fix. Please don't open a public issue for security
problems — give us a chance to ship a fix first.

## What the privileged helper does

The root helper's only job is to run macOS's `pmset disablesleep` (and
`pmset displaysleepnow`). It does not touch the network, your files, or any user
data. Before any privileged action, the app and helper validate each other's code
signature over XPC (Developer ID, team `FXNTJBLQ2F`), which closes the
impersonation class of attacks against XPC helpers.

## Updates

Updates are delivered automatically via Sparkle and are **EdDSA-signed** — a user's
copy refuses any update that isn't signed with our private key, even if a download
host is compromised.

## Supported versions

The latest release receives security updates.
