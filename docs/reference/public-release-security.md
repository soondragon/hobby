# Public release audit — 2026-10-16

## Scope and results

Before making `soondragon/hobby` public, fetched all remote branches and tags and scanned all 513 reachable commits with Gitleaks 8.30.1 (`git --log-opts="--all --full-history"`, redacted reports outside the repository). Two detections were manually classified: a Swift `Curve25519.Signing.PrivateKey` type declaration and a test assertion for the public `default_claude_max_20x` rate-limit plan. Neither contains a credential. No historical environment file, signing key, credential store, or certificate private key was found. `server/.env.example` contains placeholders only. The native release bundle scan found no secrets.

All 153 unique historical PNG/JPEG/WebP image blobs were OCR scanned successfully. Gitleaks and additional credential-label/token-pattern checks found no secrets in the extracted text. OCR and automated scanning have limits; these results do not prove the absence of every possible secret. No actual private credential was found requiring history rewrite. Scan reports and OCR text remain outside the repository. The update signing private key remains outside source and deployment.

## Server verification

The full Python 3.12 backend regression suite passed: 64 tests against a new disposable local PostgreSQL 17 database, including separate account sessions, alias rename/save ownership, revoked-session rejection, growth validation, concurrency/CAS and release routes. Production requests without authentication to save read/write and auth-user endpoints return 401; a malformed refresh token returns 422; save selectors via query parameters are rejected; API documentation is disabled (404). Private responses retain no-store headers. No production player save was modified by these probes.

Live catalog checks confirmed all 18 game/account tables have RLS enabled, and anon, authenticated and trainer_api lack direct CRUD privileges. The runtime uses the restricted trainer_api role with verified TLS. Public and private save entry points retain existing checked-session/owner RPC boundaries; neither the privileged snapshot writer nor session-binding function is executable by anon, authenticated or trainer_api. No database grants, RLS policies, authentication settings, secrets or deployment environment values were changed for publication.

The advisor reports intentional deny-all RLS without policies for 12 private RPC-only tables. It also reports disabled leaked-password protection for Supabase password Auth; the app uses GitHub public-profile authentication, not Supabase passwords. See the [RLS advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) and [password protection documentation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Distribution

Public release: https://github.com/soondragon/hobby/releases/tag/cloud-v0.3.0

Version 0.3.0 archive is 3497994 bytes with SHA-256 `ca16dd6675fad75ff5a23b1c87a779d44375501baa6a6f4a945820c4d47ea979`. The GitHub release asset and existing signed update-feed artifact are identical. GitHub download requires no repository invitation; the installed app still requires GitHub authentication to access game saves. Local token usage remains client-reported input, as explicitly chosen by the product owner; server transition validation does not attest the authenticity of local tool logs. Apple notarization and live update-button replacement are not claimed as verified by this publication audit.
