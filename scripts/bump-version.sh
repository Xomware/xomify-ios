#!/usr/bin/env bash
#
# Bumps MARKETING_VERSION in Xomify-iOS.xcodeproj/project.pbxproj.
#
# Usage:
#   scripts/bump-version.sh feat   # MAJOR.MINOR+1.0   (new feature)
#   scripts/bump-version.sh fix    # MAJOR.MINOR.PATCH+1 (bug fix)
#   scripts/bump-version.sh epic   # MAJOR+1.0.0       (huge release)
#
# The new version is printed to stdout. Exits non-zero if the kind is
# missing/unknown or if the current version isn't valid SemVer.

set -euo pipefail

KIND="${1:-}"
PBXPROJ="Xomify-iOS.xcodeproj/project.pbxproj"

if [[ -z "$KIND" ]]; then
  echo "usage: scripts/bump-version.sh <feat|fix|epic>" >&2
  exit 2
fi

CURRENT=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d ' ')

if ! [[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "MARKETING_VERSION '$CURRENT' is not MAJOR.MINOR.PATCH — fix manually first." >&2
  exit 3
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

case "$KIND" in
  feat)  MINOR=$((MINOR + 1)); PATCH=0 ;;
  fix)   PATCH=$((PATCH + 1)) ;;
  epic)  MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  *)     echo "unknown kind: $KIND (expected feat|fix|epic)" >&2; exit 2 ;;
esac

NEW="${MAJOR}.${MINOR}.${PATCH}"

# macOS sed lacks -i without an arg; portable form:
sed -i.bak -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${NEW};/g" "$PBXPROJ"
rm "${PBXPROJ}.bak"

echo "$NEW"
