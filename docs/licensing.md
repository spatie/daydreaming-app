# Daydreaming licenses

Daydreaming can verify Pro licenses locally without contacting a server. The app contains only an Ed25519 public key. The private signing key lives outside the repository on the issuer's Mac.

The free tier allows up to two new image generations per local calendar day. Reusing a cached image does not count. Pro removes the frequency restriction; the user's separate daily generation safety cap still applies. A license does not pay for OpenAI usage, so each person still supplies their own API key.

## Signing key

From the repository root, run:

```sh
swift scripts/license-issuer.swift init
```

The signing key is created at `~/Library/Application Support/Daydreaming Licensing/issuer.key` with permissions limited to its owner. Back it up securely. Losing it prevents issuing more licenses that existing versions of the app can verify. Never put it in Git, attach it to a support request, or pass its contents to a build service. The script prints only the public key. That public key must match `LicenseManager.bundledPublicKeyBase64` before distributing a build.

Running `init` again fails rather than replacing the key. To confirm the public key, run:

```sh
swift scripts/license-issuer.swift public-key
```

## Issue a license manually

```sh
swift scripts/license-issuer.swift issue --output ~/Desktop/daydreaming-license.txt
```

The output file contains the customer's license token. The script prints its path and ID but does not print the token. It refuses to overwrite an existing file. An optional `--expires YYYY-MM-DD` makes the license valid through that date in UTC. Without it, the license does not expire. An optional `--id UUID` lets a future sales system supply its own order-linked identifier without putting customer data in the token.

The token format is `DDL1.<base64url JSON>.<base64url Ed25519 signature>`. The signed JSON includes a format version, the product identifier `be.spatie.daydreaming`, license ID, Pro tier, issue timestamp, and optional expiry timestamp. The signature covers the exact JSON bytes. The app verifies the signature and dates before saving the token to Keychain.

## Later sales integration

A small Laravel app can issue licenses after a verified payment and deliver the token to the buyer. Keep the private signing key on that trusted service only. The current script supports manual pilot issuance; it does not implement checkout, payment verification, customer accounts, activation limits, revocation, or a Laravel backend.

Offline licenses can be copied to another Mac and cannot be revoked without an online check or app update. For a small pilot this is a deliberate tradeoff. If the sales model needs machine limits or refunds with prompt revocation, add a server-backed entitlement check before selling at scale.
