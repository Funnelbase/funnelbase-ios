# Releasing

Swift Package Manager reads versions straight from this repository's git tags, so a release is a
tag. There is nothing to upload and no registry account.

1. Raise `Sdk.version` in `Sources/FunnelbaseCore/Wire.swift` (it is what every upload reports as
   `sdk_version`), add the version's entry at the top of `CHANGELOG.md`, and update the version in
   the README's `from:` line. Merge that to `main`.
2. Tag `main` with the version, plain semver and no `v` (SwiftPM resolves `0.3.0`, not `v0.3.0`):

   ```bash
   git tag 0.3.0
   git push origin 0.3.0
   ```

3. The `release` workflow checks that the tag equals `Sdk.version`, runs `swift test`, and creates
   the GitHub release with the changelog entry as its notes. If the check fails, delete the tag
   (`git push origin :refs/tags/0.3.0`), fix, and tag again — but never move or delete a tag after
   its release exists: apps resolve it by its commit, and a moved tag breaks their `Package.resolved`.

No repository secrets are needed: the workflow uses the default `GITHUB_TOKEN`.

The Flutter plugin ([funnelbase-flutter](https://github.com/Funnelbase/funnelbase-flutter)) depends
on this package by version, so a release it needs comes first, then the plugin's.
