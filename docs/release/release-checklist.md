# Swarm Release Checklist

## Goal

Publish a `Swarm` GitHub tag that downstream users can resolve and build without any sibling local checkouts.

## Agent-Owned Steps

1. Update release notes and changelog content.
2. Verify `Package.swift` uses the intended published dependency graph for remote consumers.
3. Run remote-only verification:
   - `scripts/ci/verify-remote-release.sh`
4. Confirm no compiler warnings or errors appear in the release build logs.
5. Smoke-test consumption from a clean external package after tagging.

## User-Owned Steps

1. Push the release branch to GitHub.
2. Create and push the SemVer tag.
3. Publish the GitHub release entry and release notes.

## Pre-Tag Gate

- Working tree is intentional and reviewed.
- `swift build` passes.
- `swift test` passes.
- `scripts/ci/verify-remote-release.sh` passes.
- README/examples still match the public package interface.
- If `Swarm` depends on newer published internal tags, those upstream tags already exist.

## Tagging Sequence

1. Finalize the dependency graph in `Package.swift`.
2. Run `scripts/ci/verify-remote-release.sh`.
3. Tag `Swarm`.
4. Publish the GitHub release.
5. Only after that, update `Colony` to the exact new `Swarm` tag.
