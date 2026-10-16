# Cloud release workflow

The cloud release channel is independent of the upstream workflow. Do not run the upstream release script on this branch: it targets the original cask, identity and landing page.

1. Confirm the version and notes under CLAUDE.md. Keep cloud and upstream source versions separate.
2. Run native integration/security tests and backend tests on disposable local PostgreSQL. Record incomplete full-suite gates explicitly.
3. Build into an absent bundle using `scripts/build-cloud-app.sh`; strictly verify code signature, bundle ID and version.
4. Run `scripts/package-cloud-release.py --app <staged-app> --signing-key <existing-private-key>`. It checks the key against the pinned public key and packages with `ditto --norsrc --noextattr -c -k --keepParent`. Sign version, canonical download URL, SHA-256, byte size, bundle ID, minimum OS and architecture with `scripts/cloud-release-sign.swift`.
5. Keep the private signing key outside source and deployment, owner-readable only. The app bundles only `config/TrainerUpdates.json` with the pinned public key and feed URL. Never implicitly replace a lost key.
6. Stage `yong-35b2/hobby-trainer` with Production configuration and no canonical domain assignment. Check health, auth failures, signed feed and downloaded package. Keep private tables accessible only through authenticated RPC.
7. Finish pending saves before replacing the installed bundle. Keep the old app recoverable. Verify real alias, server receipt and relaunch/Keychain restoration.
8. Promote the tested build; recheck canonical feed and archive hash. Never upload env files, tokens, private signing keys or credential traces. Log out temporary CLI credentials afterward.

The updater waits for normal process exit and never kills the app to bypass pending-save protection. Failure restores the previous bundle. Game saves are not exported to local files during recovery or update.

## GitHub direct installation

Publish the verified native ZIP to `soondragon/hobby` Releases with a `cloud-v<version>` tag targeting the exact source commit. Version 0.3.0 is tagged at `34b9fc12a89119b3480757eda0c99017db4c717e`. Users download, unzip, and move the app to Applications; no launcher or developer runtime is required. The repository and release are public after the source/history/package audit; anonymous users can download the native ZIP. The server-hosted signed feed remains independent and continues serving the same verified archive. Do not point this fork at the upstream Homebrew cask.
