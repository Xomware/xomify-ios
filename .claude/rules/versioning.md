---
paths:
  - "Xomify-iOS.xcodeproj/**"
  - ".github/workflows/**"
  - "scripts/bump-version.sh"
---
# Versioning Rules

`MARKETING_VERSION` in `Xomify-iOS.xcodeproj/project.pbxproj` is the canonical
app version (SemVer: MAJOR.MINOR.PATCH). The TestFlight workflow reads it
directly; build numbers are timestamps so reusing a marketing version across
builds is fine.

## Bump policy

Use `scripts/bump-version.sh <kind>` -- never hand-edit `MARKETING_VERSION`:

- `feat` -- new feature shipped to users -> `MAJOR.MINOR+1.0`
- `fix`  -- bug fix or small patch       -> `MAJOR.MINOR.PATCH+1`
- `epic` -- huge release / breaking      -> `MAJOR+1.0.0`

The script prints the new version on stdout. Bump in the same commit as the
feature/fix it goes with so the version on `master` always matches what's
deployed.

## What NOT to do

- Don't always bump the patch digit -- match the kind of change
- Don't compute the version from git tags / commit count -- pbxproj is the
  source of truth
- Don't bump `MARKETING_VERSION` in a docs-only or CI-only PR
