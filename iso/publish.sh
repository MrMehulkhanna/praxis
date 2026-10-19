#!/usr/bin/env bash
# ============================================================================
#  Publish a built Praxis ISO as a GitHub release.
#
#    iso/publish.sh                     newest ISO in the build dir
#    iso/publish.sh path/to/praxis.iso
#
#  Uses the GitHub CLI (`gh auth login` once). The tag is v<ISO date>.
#  GitHub caps release assets at 2 GiB; larger ISOs are split into parts
#  with reassembly instructions in the notes.
# ============================================================================
set -euo pipefail
die() { printf '\n\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

REPO_SLUG=${PRAXIS_GITHUB_REPO:-MrMehulkhanna/praxis}
BUILD=${PRAXIS_BUILD_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/praxis-iso}
ISO=${1:-$(ls -t "$BUILD"/out/praxis-*.iso 2>/dev/null | head -1 || true)}
[ -n "$ISO" ] && [ -f "$ISO" ] || die "no ISO found — build one with iso/build.sh or pass its path"
command -v gh >/dev/null || die "GitHub CLI missing: sudo pacman -S github-cli && gh auth login"
gh auth status >/dev/null 2>&1 || die "not logged in: gh auth login"

NAME=$(basename "$ISO")
VERSION=$(sed -E 's/^praxis-([0-9.]+)-x86_64\.iso$/\1/' <<<"$NAME")
TAG="v$VERSION"
DIR=$(dirname "$ISO")
LIMIT=$((2 * 1024 * 1024 * 1024))

(cd "$DIR" && sha256sum "$NAME" > "$NAME.sha256")
ASSETS=("$DIR/$NAME.sha256")
REASSEMBLE=""
if [ "$(stat -c %s "$ISO")" -gt "$LIMIT" ]; then
    rm -f "$ISO".part-*
    split -b 1900M -d -a 2 "$ISO" "$ISO.part-"
    ASSETS+=("$ISO".part-*)
    REASSEMBLE=$(printf '\n### Reassemble\n\nThis ISO is larger than GitHub'"'"'s 2 GiB asset limit, so it is split:\n\n```sh\ncat %s.part-* > %s\nsha256sum -c %s.sha256\n```\n' "$NAME" "$NAME" "$NAME")
else
    ASSETS+=("$ISO")
fi

NOTES=$(cat <<EOF
Praxis Linux $VERSION — live + installer ISO (x86_64, UEFI).

**Try it:** write the ISO to a USB drive (\`iso/flash.sh\`, Ventoy, or balenaEtcher), boot it with
Secure Boot disabled, and click **Install Praxis Linux** in the dock. If the target disk has free,
unallocated space, the installer uses only that space and keeps Windows in the boot menu.

**Verify:** \`sha256sum -c $NAME.sha256\`
$REASSEMBLE
EOF
)

gh release create "$TAG" "${ASSETS[@]}" --repo "$REPO_SLUG" --title "Praxis Linux $VERSION" --notes "$NOTES"
printf '\n\033[1;32mPublished\033[0m  https://github.com/%s/releases/tag/%s\n' "$REPO_SLUG" "$TAG"
