#!/bin/bash
# Releases Cobrain: bumps VERSION, updates CHANGELOG.md, commits, tags `cobrain-vX.Y.Z`, builds the Mac app,
# pushes main and the tag, and publishes a GitHub release with the app attached.
#
#   scripts/release.sh patch|minor|major     next version from VERSION (1.0.0 → 1.0.1 / 1.1.0 / 2.0.0)
#   scripts/release.sh 1.2.3                 an explicit version (for the first release, or after editing CHANGELOG.md by hand)
#   --dry-run    show what would happen, change nothing        --no-assets    don't build and attach the Mac app
#
# Versioning (semantic): MAJOR for changes that break saved files or workflows, MINOR for new features,
# PATCH for fixes. The tag has a `cobrain-` prefix so it never collides with WordCraft's own `vX.Y.Z` tags.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"

BUMP="${1:-}"; DRY=0; ASSETS=1
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --no-assets) ASSETS=0;; esac; done
[[ -n "$BUMP" && "$BUMP" != --* ]] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
run() { if [[ $DRY == 1 ]]; then echo "[dry-run] $*"; else "$@"; fi; }

# --- checks
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || { echo "Release from main (you are on $(git rev-parse --abbrev-ref HEAD))."; exit 1; }
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { echo "Commit or stash your changes first."; exit 1; }
git fetch -q origin main --tags 2>/dev/null || git fetch -q origin main
[[ "$(git rev-list --count HEAD..origin/main)" == 0 ]] || { echo "origin/main has commits you don't have: git merge origin/main first."; exit 1; }

# --- version
CUR="$(tr -d '[:space:]' < VERSION)"
IFS=. read -r MA MI PA <<<"$CUR"
case "$BUMP" in
  patch) NEXT="$MA.$MI.$((PA + 1))";;
  minor) NEXT="$MA.$((MI + 1)).0";;
  major) NEXT="$((MA + 1)).0.0";;
  [0-9]*.[0-9]*.[0-9]*) NEXT="$BUMP";;
  *) echo "Unknown version '$BUMP'"; exit 1;;
esac
TAG="cobrain-v$NEXT"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "$TAG already exists."; exit 1; }
echo "Releasing Cobrain $CUR → $NEXT ($TAG)"

# --- changelog: keep a hand-written section for this version, else build one from the commits since the last release
LAST="$(git tag --list 'cobrain-v*' --sort=-v:refname | head -1)"
NOTES="$(mktemp)"
if grep -q "^## \[$NEXT\]" CHANGELOG.md 2>/dev/null; then
  awk -v v="$NEXT" '$0 ~ "^## \\["v"\\]" {p=1; next} /^## \[/ {p=0} p' CHANGELOG.md > "$NOTES"
else
  { git log ${LAST:+$LAST..HEAD} --no-merges --format='- %s' | grep -v '^- Release ' || true; } > "$NOTES"
  [[ -s "$NOTES" ]] || echo "- Maintenance release" > "$NOTES"
  if [[ $DRY == 0 ]]; then
    { echo "# Changelog"; echo; echo "## [$NEXT] - $(date +%Y-%m-%d)"; echo; cat "$NOTES"; echo; tail -n +3 CHANGELOG.md 2>/dev/null || true; } > CHANGELOG.md.new
    mv CHANGELOG.md.new CHANGELOG.md
  fi
fi
echo "--- release notes"; cat "$NOTES"; echo "---"

# --- commit and tag
if [[ $DRY == 0 ]]; then
  echo "$NEXT" > VERSION
  git add VERSION CHANGELOG.md
  git diff --cached --quiet || git commit -q -m "Release $NEXT

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
fi
run git tag -a "$TAG" -m "Cobrain $NEXT"

# --- the Mac app (records this commit and the version), zipped
ASSET=""
if [[ $ASSETS == 1 ]]; then
  run macos/scripts/build-app.sh
  mkdir -p dist
  ASSET="dist/Cobrain-$NEXT-macos.zip"
  run ditto -c -k --keepParent macos/build/Cobrain.app "$ASSET"
fi

# --- publish
run git push origin main
run git push origin "$TAG"
run gh release create "$TAG" ${ASSET:+"$ASSET"} --title "Cobrain $NEXT" --notes-file "$NOTES" --verify-tag
echo "Released Cobrain $NEXT"
