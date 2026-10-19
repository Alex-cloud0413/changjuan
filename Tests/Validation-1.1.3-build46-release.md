# 1.1.3 (46) release validation

## Scope and authorization

On 2026-10-20, the user authorized installing the current fix, pushing the independent GitHub repository and submitting the App Store update. App Store Connect then showed 1.1.2 (42) as available for distribution, so this release uses 1.1.3 (46) rather than replacing an already published version. Build 46 changes only version identifiers relative to the standard Build 45 application code; its fixes and evidence are described in [Build 45 validation](Validation-1.1.2-build45-local.md).

The standard signed Release was installed in place and read back as 1.1.3 (46); no uninstall or cache cleanup was performed. App and widget versions match. The source recordings stay local and are not included in GitHub or the App Store package.

The previous true-device replay measured 6.532 seconds for the algorithm on one explicitly authorized 140-frame input. It excludes Photos saving and notification delivery. The user has not yet reported a fresh end-to-end recording acceptance for this fix; installation, automated tests, replay and acceptance must not be conflated.

## Verification

Signed Release build, archive and Apple Distribution export succeeded. Both exported targets are arm64, Apple Distribution signed, `get-task-allow=false`, version 1.1.3 (46), minimum iOS 27.0. Strict signature verification passed in the system trust environment; Chinese/English resources are present and benchmark, snapshot and raw-frame export hooks are absent.

The initial numbered-release regression stopped because one test hardcoded marketing version 1.1.2; its native storage checks passed. The assertion now verifies four synchronized, valid marketing versions rather than a stale literal. No runtime source was changed by that test correction. The failed report remains at `Build/regression-ih0xeX/`.

The full rerun passed **27/27 gates** (`Build/regression-gtbV6l/report.json`). Source fingerprint before/after the test and in the clean release checkout: `340a99ff4bf64b84242612afe62ca23d9b8ff81d1dc5de96bc544ebf1aea97ef` (101 source/config/test files). It covers frozen columns, independent body matching, jitter, floating controls, qualified partial results, reverse/revisit, explicit cross-page capture, cache equivalence and cleanup, notification/localization, actual rendered control symbols and both Release builds. Vertical 90-frame/3-page comparison remains byte-identical to the accepted baseline. Performance stage budgets all passed; the simulator total medians were 2.0295 → 1.7983 seconds. This is fixture evidence, not a phone end-to-end speedup claim.

The independent public repository was freshly cloned from `a626a8c`; changes are copied using an explicit 25-file allowlist. Runtime source/config/test fingerprints match; unrelated history and remote files are retained. Private images, session recordings, device identifiers, logs, packages and signing material are excluded. No application source is added to the workspace repository.

## Platform state

- Source commit `26ad213aa4ec4c9ee5a455d3e4aee9d69dcf3c34` was pushed to independent public repository `Alex-cloud0413/changjuan`. `git ls-remote` and a second clean clone confirmed the commit. All 25 allowlisted files matched byte-for-byte and all 101 source/config/test files matched the regression fingerprint.
- Xcode reported upload success at 2026-10-20 02:12 GMT+8 and confirmed that Apple had begun processing the package. App and widget are 1.1.3 (46). This alone is not review submission.
- Version 1.1.3 was created with updated Chinese release notes, accurate partial-output/storage disclosures and English review instructions. Existing screenshots, automatic release, immediate updates and existing ratings were retained. No price, region, review contact or privacy-collection setting was changed.
- Apple finished processing Build 46; it was selected for 1.1.3 and saved. Review submission was completed and verified on 2026-10-20. Internal platform identifiers and detailed receipts are retained locally, not published in this repository.
- Approval and public availability remain pending; 1.1.2 (42) remains the last verified public version. Automatic release is configured for after approval; submission is not publication.
