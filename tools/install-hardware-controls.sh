#!/usr/bin/env bash
# Install the *only* elevated AIOS entry point and authorize the active owner.
# Run once: sudo ./tools/install-hardware-controls.sh
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
owner="${SUDO_USER:-}"
if [[ -z "$owner" && -n "${PKEXEC_UID:-}" ]]; then owner="$(id -nu "$PKEXEC_UID")"; fi
[[ -n "$owner" ]] || { echo "run through sudo or pkexec from the desktop owner" >&2; exit 2; }
install -D -o root -g root -m 0755 "$script_dir/aios-hardware" /usr/local/libexec/aios-hardware
install -D -o root -g root -m 0644 /dev/stdin /etc/polkit-1/rules.d/49-aios-hardware.rules <<RULE
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "/usr/local/libexec/aios-hardware" &&
        subject.local && subject.active && subject.user == "${owner}") {
        return polkit.Result.YES;
    }
});
RULE
echo "AIOS fan and charge-limit controls enabled for ${owner} without password prompts."
