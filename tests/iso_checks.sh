#!/usr/bin/env bash
# Static + unit checks for the ISO tree. No root, no disks, no network.
#   tests/iso_checks.sh
set -uo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
AIRO=$REPO/iso/airootfs
pass=0; fail=0
ok()  { pass=$((pass + 1)); printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  \033[31m✗\033[0m %s\n' "$*"; }
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1  (want '$3', got '$2')"; }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

section "shell syntax"
while IFS= read -r f; do
    check "bash -n ${f#"$REPO"/}" bash -n "$f"
done < <(find "$REPO/iso" -type f \( -name '*.sh' -o -perm -u+x \) -exec grep -lE '^#!.*(ba)?sh' {} + ; find "$AIRO/usr/local/lib" -name '*.sh')
while IFS= read -r f; do
    check "python syntax ${f#"$REPO"/}" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f"
done < <(grep -lE '^#!.*python' "$AIRO"/usr/local/bin/* 2>/dev/null)

# shellcheck source=../iso/airootfs/usr/local/lib/praxis/hwdetect.sh
. "$AIRO/usr/local/lib/praxis/hwdetect.sh"

section "CPU microcode"
eq "Intel → intel-ucode"   "$(praxis_ucode GenuineIntel)" "intel-ucode"
eq "AMD → amd-ucode"       "$(praxis_ucode AuthenticAMD)" "amd-ucode"
eq "unknown → nothing"     "$(praxis_ucode SomethingElse)" ""

section "GPU drivers (real lspci -nn lines)"
INTEL='00:02.0 VGA compatible controller [0300]: Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics] [8086:46a6] (rev 0c)'
RTX4050='01:00.0 3D controller [0302]: NVIDIA Corporation AD107M [GeForce RTX 4050 Max-Q / Mobile] [10de:28a1] (rev a1)'
GTX1060='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB] [10de:1c03] (rev a1)'
RADEON='03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600] [1002:73ff] (rev c7)'
ETH='02:00.0 Ethernet controller [0200]: Intel Corporation Ethernet Controller I225-V [8086:15f3] (rev 03)'
eq "Intel iGPU"                       "$(praxis_gpu_pkgs "$INTEL")"            "mesa vulkan-intel intel-media-driver"
eq "Intel + RTX 4050 (hybrid laptop)" "$(praxis_gpu_pkgs "$INTEL"$'\n'"$RTX4050")" "mesa vulkan-intel intel-media-driver nvidia-open nvidia-utils"
# on many hybrid laptops the iGPU is a "Display controller" (class 0380), not VGA
IGPU_0380='00:02.0 Display controller [0380]: Intel Corporation Raptor Lake-P [Iris Xe Graphics] [8086:a7a0] (rev 04)'
RTX4050_VGA='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD107M [GeForce RTX 4050 Max-Q / Mobile] [10de:28a1] (rev a1)'
eq "iGPU listed as Display controller" "$(praxis_gpu_pkgs "$IGPU_0380"$'\n'"$RTX4050_VGA")" "mesa vulkan-intel intel-media-driver nvidia-open nvidia-utils"
eq "'Corporation' is not AMD"         "$(praxis_gpu_pkgs "$RTX4050")"          "nvidia-open nvidia-utils"
eq "pre-Turing NVIDIA → nouveau"      "$(praxis_gpu_pkgs "$GTX1060")"          "mesa vulkan-nouveau"
eq "AMD Radeon"                       "$(praxis_gpu_pkgs "$RADEON")"           "mesa vulkan-radeon xf86-video-amdgpu"
eq "non-GPU Intel device ignored"     "$(praxis_gpu_pkgs "$ETH")"              "mesa"
eq "nothing detected → mesa"          "$(praxis_gpu_pkgs "")"                  "mesa"

section "GPU detection under the installer's strict mode"
# the engine runs with set -Eeuo pipefail and an ERR trap; detection must never
# trip it (no NVIDIA GPU used to fire the trap inside $(…) and unmount the target)
VIRTIO='00:03.0 VGA compatible controller [0300]: Red Hat, Inc. Virtio 1.0 GPU [1af4:1050] (rev 01)'
for g in "$VIRTIO" "$INTEL" "$RADEON"; do
    out=$(bash -c 'set -Eeuo pipefail; shopt -s inherit_errexit; . "$1"; trap "echo TRAPPED" ERR; praxis_gpu_pkgs "$2"' _ "$AIRO/usr/local/lib/praxis/hwdetect.sh" "$g" 2>&1)
    [[ "$out" != *TRAPPED* ]] && ok "no error trap for: ${g:46:40}" || bad "error trap fired for: ${g:46:40}"
done
check "the engine's error trap ignores subshells" grep -q '\[ "\$BASHPID" = "\$\$" \] || return "\$rc"' "$AIRO/usr/local/bin/praxis-install-engine"

section "free-space detection (parted -sm output)"
WIN='BYT;
/dev/nvme0n1:488386MiB:nvme:512:512:gpt:disk;
1:1.00MiB:100MiB:99MiB:fat32:EFI:esp;
2:100MiB:116MiB:16MiB::MSR:msftres;
3:116MiB:336000MiB:335884MiB:ntfs:Windows:msftdata;
1:336000MiB:488386MiB:152386MiB:free;'
FULL='BYT;
/dev/sda:476940MiB:scsi:512:512:gpt:disk;
1:1.00MiB:476940MiB:476939MiB:ntfs:Data:msftdata;'
SMALL='BYT;
1:476000MiB:486000MiB:10000MiB:free;'
eq "finds 148 GiB after Windows" "$(praxis_largest_free "$WIN")"   "336000MiB 488386MiB 152386"
eq "no free space → empty"       "$(praxis_largest_free "$FULL")"  ""
eq "< 30 GiB free is ignored"    "$(praxis_largest_free "$SMALL")" ""
eq "custom minimum honoured"     "$(praxis_largest_free "$SMALL" 8000)" "476000MiB 486000MiB 10000"

section "installer safety guards"
ENG=$AIRO/usr/local/bin/praxis-install-engine
INST=$AIRO/usr/local/bin/praxis-install
GUI=$AIRO/usr/local/share/praxis/installer
check "refuses the USB drive it runs from"      grep -q "is the USB drive Praxis is running from" "$ENG"
check "requires UEFI"                           grep -q "Praxis needs UEFI" "$ENG"
check "plan values are parsed, never executed"  grep -q "only known keys, never executed" "$ENG"
check "saves the partition table first"         grep -q 'sfdisk --dump "$DISK"' "$ENG"
check "Windows shrink: test run before the real one" grep -q -- '--no-action --size "$FS_BYTES"' "$ENG"
check "Windows shrink: NTFS sized to its partition"  grep -q 'FS_BYTES=$((NEW_MIB \* 1048576))' "$ENG"
check "Windows shrink: verified before going on" grep -q "does not look healthy after shrinking" "$ENG"
check "never formats a foreign EFI partition"   grep -q "Praxis won't change it" "$ENG"
check "test runs never touch the host firmware" grep -q -- '--no-nvram' "$ENG"
check "text installer: erase needs ERASE"       grep -q 'WORD=ERASE' "$INST"
check "text installer: connects Wi-Fi first"    grep -q 'online()' "$INST"
check "text installer hands off to the engine"  grep -q 'praxis-install-engine "$PLAN"' "$INST"
check "graphical installer: erase needs a tick" grep -q 'wipeConfirmed' "$GUI/State/Inst.qml"
check "graphical installer hands off to the engine" grep -q 'praxis-install-engine' "$GUI/State/Inst.qml"
check "partition installer folded into the main one" grep -q 'exec /usr/local/bin/praxis-install' "$AIRO/usr/local/bin/praxis-install-partition"
check "disk probe is valid python"              python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$AIRO/usr/local/lib/praxis/install_probe.py"
check "dock entry opens the graphical installer" grep -q '^Exec=/usr/local/bin/praxis-installer$' "$AIRO/usr/share/applications/praxis-install.desktop"
check "graphical installer launcher is executable" test -x "$AIRO/usr/local/bin/praxis-installer"

section "live session"
check "installer app entry is valid"      desktop-file-validate "$AIRO/usr/share/applications/praxis-install.desktop"
check "live user setup only on live media" grep -q "ConditionPathExists=/run/archiso" "$AIRO/etc/systemd/system/praxis-live-setup.service"
check "live setup service is enabled"      test -L "$AIRO/etc/systemd/system/multi-user.target.wants/praxis-live-setup.service"
check "autologin targets 'praxis'"         grep -q -- "--autologin praxis" "$AIRO/etc/systemd/system/getty@tty1.service.d/autologin.conf"
check "login goes straight to the desktop"  bash -c "! grep -q praxis-welcome '$AIRO/etc/skel/.bash_profile'"
check "welcome offers the installer"       grep -q 'action=install' "$AIRO/usr/local/bin/praxis-first-boot"

section "installed system = live desktop"
. "$AIRO/usr/local/lib/praxis/install-common.sh"
DESK=$(mktemp); trap 'rm -f "$DESK"' EXIT
sed '/^# @live-only/,$d' "$REPO/iso/packages.x86_64" | grep -vE '^\s*(#|$)' > "$DESK"   # as build.sh does
PKGS=$(PRAXIS_DESKTOP_LIST=$DESK PRAXIS_REPO_DIR=/nonexistent praxis_packages)
has() { grep -qx "$1" <<<"$PKGS"; }
check "@live-only marker splits the list"      grep -q '^# @live-only' "$REPO/iso/packages.x86_64"
for p in base linux grub polkit-kde-agent adwaita-fonts pavucontrol jq python networkmanager bluez; do
    check "installs $p" has "$p"
done
for p in vulkan-nouveau libva-intel-driver waybar polkit-gnome ttf-jetbrains-mono-nerd; do
    check "does not install $p" bash -c "! grep -qx '$p' <<<\"\$1\"" _ "$PKGS"
done
check "the engine installs the shared list"     grep -q 'praxis_packages' "$AIRO/usr/local/bin/praxis-install-engine"
svc_has() { praxis_target_services | grep -qx "$1"; }
for u in NetworkManager bluetooth power-profiles-daemon earlyoom fstrim.timer; do
    check "targets enable $u" svc_has "$u"
done
for p in wtype earlyoom ntfsprogs; do check "installs $p" has "$p"; done
check "memory tuning ships to targets"         bash -c "grep -q '80-praxis-memory.conf' '$AIRO/usr/local/lib/praxis/install-common.sh' && test -f '$AIRO/etc/sysctl.d/80-praxis-memory.conf'"
check "AI service limits ship to targets"      bash -c "grep -q 'aios.service.d' '$AIRO/usr/local/lib/praxis/install-common.sh' && grep -q OOMScoreAdjust '$AIRO/usr/lib/systemd/user/aios.service.d/10-praxis.conf'"
check "zram swap is configured"                grep -q '^\[zram0\]' "$AIRO/etc/systemd/zram-generator.conf"

section "live network & remote access"
check "NetworkManager runs the live network"   grep -q 'NetworkManager.service "$UNITS/multi-user.target.wants' "$REPO/iso/build.sh"
check "releng's iwd/networkd are switched off" bash -c "grep -q 'iwd.service' '$REPO/iso/build.sh' && grep -q 'systemd-networkd.service' '$REPO/iso/build.sh'"
check "Bluetooth runs in the live session"     grep -q 'bluetooth.target.wants/bluetooth.service' "$REPO/iso/build.sh"
check "sshd is off on live media"              grep -q 'rm -f "$UNITS/multi-user.target.wants/sshd.service"' "$REPO/iso/build.sh"
check "live account never logs in over SSH"    grep -qE '^\s*PasswordAuthentication no' "$AIRO/etc/ssh/sshd_config.d/10-praxis-live.conf"

section "keybinds only call what Praxis ships"
LUA=$REPO/desktop/hypr/hyprland.lua
while IFS= read -r c; do
    # shellcheck disable=SC2088  # the bind text itself holds a literal ~
    case "$c" in
        "~/.config/hypr/scripts/"*) check "script $c" test -x "$REPO/desktop/hypr/scripts/${c##*/}" ;;
        praxis-*)                    check "tool $c"   test -x "$AIRO/usr/local/bin/$c" ;;
    esac
done < <(grep -o 'exec_cmd("[^" ]*' "$LUA" | sed 's/exec_cmd("//' | sort -u)
check "no exec starts with '[' (Hyprland reads it as rules)" bash -c "! grep -qE 'exec_cmd\\(\"\\[' '$LUA'"
check "no binds into ~/aios (absent until AI setup)" bash -c "! grep -q 'exec_cmd(\"~/aios' '$LUA'"
check "no binds through /tmp pipes"            bash -c "! grep -q '/tmp/qs-ipc-pipe' '$LUA'"
check "autostarted polkit agent is installed"  bash -c "! grep -q polkit-kde-authentication-agent '$LUA' || grep -qx polkit-kde-agent '$DESK'"

section "branding"
check "installer icon is shipped"   bash -c "grep -q '^Icon=praxis-install$' '$AIRO/usr/share/applications/praxis-install.desktop' && test -s '$AIRO/usr/share/icons/hicolor/scalable/apps/praxis-install.svg'"
check "os-release logo is shipped"  test -s "$AIRO/usr/share/icons/hicolor/scalable/apps/$(sed -n 's/^LOGO=//p' "$AIRO/usr/lib/praxis/os-release").svg"
check "os-release says Praxis"   grep -q '^ID=praxis' "$AIRO/usr/lib/praxis/os-release"
check "tmpfiles keeps branding"  grep -q '/usr/lib/praxis/os-release' "$AIRO/usr/lib/tmpfiles.d/praxis.conf"
check "no /home/mk in the image" bash -c "! grep -rIl '/home/mk' '$AIRO' '$REPO/desktop'"

section "packages"
if command -v pacman >/dev/null; then
    missing=$(grep -vE '^\s*(#|$)' "$REPO/iso/packages.x86_64" | while read -r p; do pacman -Si "$p" >/dev/null 2>&1 || echo "$p"; done)
    [ -z "$missing" ] && ok "every live package exists in the repos" || bad "unknown packages: $missing"
    # what the installers pacstrap (the bundled AUR packages come from the ISO's [praxis] repo)
    missing=$(PRAXIS_DESKTOP_LIST=$DESK PRAXIS_REPO_DIR=/nonexistent praxis_packages | while read -r p; do pacman -Si "$p" >/dev/null 2>&1 || echo "$p"; done)
    [ -z "$missing" ] && ok "every package the installers request exists" || bad "installers would fail on: $missing"
    # optional app bundles ([multilib] packages are only checked when this host has that repository)
    missing=$(praxis_app_bundles | cut -d'|' -f4 | tr ' ' '\n' | while read -r p; do
        [ -n "$p" ] || continue
        case "$p" in lib32-*|steam) pacman -Sl multilib >/dev/null 2>&1 || continue ;; esac
        pacman -Si "$p" >/dev/null 2>&1 || echo "$p"; done)
    [ -z "$missing" ] && ok "every app-bundle package exists" || bad "app bundles would fail on: $missing"
fi

printf '\n\033[1m%d passed, %d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
